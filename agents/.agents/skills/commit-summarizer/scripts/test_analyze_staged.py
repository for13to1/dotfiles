#!/usr/bin/env python3
"""Tests for analyze_staged.infer_change_type.

Pins down every branch of the primary-type inference plus the regression
cases that motivated recent fixes (e.g. rename + feat signal must NOT
short-circuit to refactor).

Run directly:  python3 test_analyze_staged.py
With pytest:   pytest test_analyze_staged.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from analyze_staged import infer_change_type  # noqa: E402


def _f(status, path, raw_status=None):
    """Build a minimal file dict as get_staged_files would produce."""
    return {"status": status, "path": path, "raw_status": raw_status or status}


# (name, files, diff, expect_type, expect_conf)
BRANCH_CASES = [
    # 1. only_docs → docs/high
    ("only_docs", [_f("M", "README.md")], "+docs change", "docs", "high"),
    # 2. only_tests → test/high
    ("only_tests", [_f("M", "test_foo.py")], "+test", "test", "high"),
    # 3. has_rename, no feat/fix signal → refactor/medium
    ("rename_no_signal", [_f("R", "new.py", "R100")],
     "rename old to new", "refactor", "medium"),
    # 4. is_rename_heavy (A+D) + refactor signal > feat → refactor/medium
    ("rename_heavy_refactor_signal",
     [_f("A", "new_loc.py"), _f("D", "old_loc.py")],
     "+# refactor: move module\n+# extract helper", "refactor", "medium"),
    # 5. feat > fix and feat > refactor → feat/low
    ("feat_signal_dominant", [_f("M", "main.py")],
     "+add feature\n+implement x", "feat", "low"),
    # 6. fix > feat → fix/low
    ("fix_signal_dominant", [_f("M", "main.py")],
     "+fix bug\n+resolve issue", "fix", "low"),
    # 7. has_new and not has_delete → feat/medium
    ("new_file_no_signal", [_f("A", "new.py")], "+x", "feat", "medium"),
    # 8. has_modify and not has_new, no signal → chore/low (conservative)
    ("modify_only_no_signal", [_f("M", "main.py")], "+x=1", "chore", "low"),
    # 9. else (only delete, no signal) → chore/low
    ("delete_only", [_f("D", "old.py")], "-x", "chore", "low"),
]

# Regression: rename + feat/fix signal must NOT short-circuit to refactor.
# These cases motivated the fix that narrowed the has_rename condition.
REGRESSION_CASES = [
    # rename + feat signal → feat (not refactor)
    ("rename_with_feat_signal", [_f("R", "new.py", "R100")],
     "+def new_feature():\n+# add oauth", "feat"),
    # rename + fix signal → fix (not refactor)
    ("rename_with_fix_signal", [_f("R", "fixed.py", "R100")],
     "+# fix: resolve null pointer", "fix"),
]

# (name, files, diff, expect_conf)
NOTE_CASES = [
    ("high_conf_docs", [_f("M", "README.md")], "+doc", "high"),
    ("medium_conf_rename", [_f("R", "new.py", "R100")], "rename", "medium"),
    ("low_conf_chore", [_f("M", "main.py")], "+x", "low"),
]


def test_branch_coverage():
    """Every elif arm in infer_change_type gets at least one positive case."""
    for name, files, diff, expect_type, expect_conf in BRANCH_CASES:
        r = infer_change_type(files, diff)
        assert r["primary_type"] == expect_type, (
            f"{name}: expected type {expect_type}, got {r['primary_type']}"
        )
        assert r["confidence"] == expect_conf, (
            f"{name}: expected confidence {expect_conf}, got {r['confidence']}"
        )


def test_rename_with_signals_not_refactor():
    """Regression: rename + feat/fix signal must not short-circuit to refactor."""
    for name, files, diff, expect_type in REGRESSION_CASES:
        r = infer_change_type(files, diff)
        assert r["primary_type"] == expect_type, (
            f"{name}: rename + signal must not short-circuit to refactor; "
            f"got {r['primary_type']}"
        )


def test_note_only_present_when_low_confidence():
    """note must be non-None iff confidence is low."""
    for name, files, diff, expect_conf in NOTE_CASES:
        r = infer_change_type(files, diff)
        assert r["confidence"] == expect_conf, (
            f"{name}: expected confidence {expect_conf}, got {r['confidence']}"
        )
        if r["confidence"] == "low":
            assert r["note"] is not None, (
                f"{name}: low confidence must carry a note"
            )
        else:
            assert r["note"] is None, (
                f"{name}: non-low confidence should not carry a note"
            )


def test_signal_counts():
    """feat/fix/refactor signal counts must match diff content."""
    files = [_f("M", "main.py")]
    diff = "+add feature\n+fix bug\n+refactor module"
    r = infer_change_type(files, diff)
    sig = r["signals"]
    assert sig["feat_signals"] == 1, (
        f"feat_signals: expected 1, got {sig['feat_signals']}"
    )
    assert sig["fix_signals"] == 1, (
        f"fix_signals: expected 1, got {sig['fix_signals']}"
    )
    assert sig["refactor_signals"] == 1, (
        f"refactor_signals: expected 1, got {sig['refactor_signals']}"
    )


def test_signal_file_counts():
    """new_files / deleted_files / modified_files counts reflect file statuses."""
    files = [
        _f("A", "new.py"),
        _f("D", "old.py"),
        _f("M", "main.py"),
        _f("R", "renamed.py", "R100"),
    ]
    r = infer_change_type(files, "+x")
    sig = r["signals"]
    assert sig["new_files"] == 1, f"new_files: expected 1, got {sig['new_files']}"
    assert sig["deleted_files"] == 1, f"deleted_files: expected 1, got {sig['deleted_files']}"
    # modified_files counts both M and R
    assert sig["modified_files"] == 2, (
        f"modified_files: expected 2 (M + R), got {sig['modified_files']}"
    )


def test_word_boundary_filters_substring_matches():
    """Word boundaries must reject substring matches that caused false positives
    under the old regex (e.g. 'add' in 'addition', 'fix' in 'prefix'). 'new' is
    dropped entirely, so new_feature no longer counts as a feat signal.
    """
    files = [_f("M", "main.py")]
    # Substring false positives — must NOT match after word-boundary tightening
    r = infer_change_type(files, "+addition of prefix in newspaper")
    sig = r["signals"]
    assert sig["feat_signals"] == 0, (
        f"'addition'/'newspaper' should not match feat; got {sig['feat_signals']}"
    )
    assert sig["fix_signals"] == 0, (
        f"'prefix' should not match fix; got {sig['fix_signals']}"
    )
    # "new" dropped — new_feature no longer counts as feat signal
    r2 = infer_change_type(files, "+def new_feature():")
    assert r2["signals"]["feat_signals"] == 0, (
        f"'new_feature' should not match feat (new dropped); "
        f"got {r2['signals']['feat_signals']}"
    )
    # Real signals still match after tightening
    r3 = infer_change_type(files, "+add feature\n+fix bug")
    sig3 = r3["signals"]
    assert sig3["feat_signals"] == 1, (
        f"'add feature' should match feat; got {sig3['feat_signals']}"
    )
    assert sig3["fix_signals"] == 1, (
        f"'fix bug' should match fix; got {sig3['fix_signals']}"
    )


def _run(test_fns):
    passed, failed = 0, []
    for fn in test_fns:
        try:
            fn()
            print(f"  PASS {fn.__name__}")
            passed += 1
        except AssertionError as e:
            failed.append((fn.__name__, str(e)))
            print(f"  FAIL {fn.__name__}: {e}")
    return passed, failed


if __name__ == "__main__":
    print("Running analyze_staged tests...\n")
    tests = [
        test_branch_coverage,
        test_rename_with_signals_not_refactor,
        test_note_only_present_when_low_confidence,
        test_signal_counts,
        test_signal_file_counts,
        test_word_boundary_filters_substring_matches,
    ]
    passed, failed = _run(tests)
    total = len(tests)
    print(f"\n{passed}/{total} test functions passed")
    if failed:
        for name, err in failed:
            print(f"  FAIL {name}: {err}")
        sys.exit(1)
    print("All tests passed")
