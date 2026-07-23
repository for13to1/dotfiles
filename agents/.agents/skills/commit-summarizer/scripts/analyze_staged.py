#!/usr/bin/env python3
"""
analyze_staged: Structured analysis of git staged changes.

Outputs JSON with file stats, logical groupings, change-type inference,
and context hints (binary files, large diffs, config/test/doc detection).
Designed for LLM consumption — the agent reads this structured output
instead of parsing raw git diff.

Usage:
    python analyze_staged.py [--workdir PATH]

Exit codes:
    0  — analysis complete (JSON on stdout)
    1  — not a git repo, or no staged changes
"""

import argparse
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

# Thresholds for diff-size heuristics (lines added + deleted).
#   DIFF_PREVIEW_INLINE_LIMIT: diff is included in the JSON only when total
#       changes are at or below this — above it, the LLM should read from
#       `git diff` itself rather than from a bloated JSON payload.
#   DIFF_PREVIEW_TRUNCATE_LINES: line count at which get_staged_diff_preview
#       truncates its output (cap on raw lines, not modified lines).
#   LARGE_DIFF_LINES: total modified lines above which we flag the diff as
#       large (is_large_diff + the large_diff warning).
DIFF_PREVIEW_INLINE_LIMIT = 300
DIFF_PREVIEW_TRUNCATE_LINES = 500
LARGE_DIFF_LINES = 500
SCHEMA_VERSION = 1


def run(cmd: list[str], cwd: str | None = None) -> str:
    """Run a command and return stdout, stripped."""
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    return result.stdout.strip()


def is_git_repo(cwd: str | None = None) -> bool:
    return run(["git", "rev-parse", "--is-inside-work-tree"], cwd=cwd) == "true"


def get_staged_files(cwd: str | None = None) -> list[dict]:
    """Get staged file changes with status codes."""
    raw = run(["git", "diff", "--cached", "--name-status"], cwd=cwd)
    if not raw:
        return []
    files = []
    for line in raw.splitlines():
        parts = line.split("\t", 2)
        if len(parts) >= 2:
            status = parts[0][0]  # first char: A/M/D/R/C
            path = parts[-1]
            files.append({"status": status, "path": path, "raw_status": parts[0]})
    return files


def get_diff_stat(cwd: str | None = None) -> str:
    """Get --stat summary for overview."""
    return run(["git", "diff", "--cached", "--stat"], cwd=cwd)


def get_diff_numstat(cwd: str | None = None) -> list[dict]:
    """Get insertions/deletions per file."""
    raw = run(["git", "diff", "--cached", "--numstat"], cwd=cwd)
    if not raw:
        return []
    stats = []
    for line in raw.splitlines():
        parts = line.split("\t")
        if len(parts) >= 3:
            ins, dels, path = parts[0], parts[1], parts[2]
            stats.append(
                {
                    "path": path,
                    "insertions": int(ins) if ins != "-" else 0,
                    "deletions": int(dels) if dels != "-" else 0,
                    "binary": ins == "-" and dels == "-",
                }
            )
    return stats


def get_staged_diff_preview(cwd: str | None = None, max_lines: int = DIFF_PREVIEW_TRUNCATE_LINES) -> str:
    """Get a preview of the staged diff (truncated for large changes)."""
    raw = run(["git", "diff", "--cached", "--unified=2"], cwd=cwd)
    lines = raw.splitlines()
    if len(lines) > max_lines:
        return "\n".join(lines[:max_lines]) + f"\n... [truncated: {len(lines)} total lines]"
    return raw


def check_merge_commit(cwd: str | None = None) -> bool:
    """Check if HEAD is a merge commit."""
    parents = run(["git", "rev-list", "--parents", "-n", "1", "HEAD"], cwd=cwd)
    return len(parents.split()) > 2  # hash + 2+ parents


def detect_commitlint(cwd: str | None = None) -> dict:
    """Check for commitlint config and .gitmessage template."""
    result = {"commitlint": False, "gitmessage": None}
    base_path = Path(cwd or ".")

    # Check commitlint config files
    for name in [
        ".commitlintrc",
        ".commitlintrc.json",
        ".commitlintrc.js",
        ".commitlintrc.yml",
        ".commitlintrc.yaml",
        "commitlint.config.js",
        "commitlint.config.ts",
    ]:
        if (base_path / name).exists():
            result["commitlint"] = True
            result["commitlint_config"] = name
            break

    # Check package.json for commitlint
    pkg_path = base_path / "package.json"
    if pkg_path.exists():
        try:
            with pkg_path.open() as f:
                pkg = json.load(f)
            if "commitlint" in pkg.get("devDependencies", {}) or "commitlint" in pkg.get("dependencies", {}):
                result["commitlint"] = True
        except (json.JSONDecodeError, OSError):
            pass

    # Check .gitmessage template
    gitconfig = run(["git", "config", "--get", "commit.template"], cwd=cwd)
    if gitconfig:
        result["gitmessage"] = gitconfig

    return result


def detect_project_type(cwd: str | None = None) -> list[str]:
    """Detect project type from manifest files."""
    markers = {
        "package.json": "node",
        "Cargo.toml": "rust",
        "go.mod": "go",
        "pyproject.toml": "python",
        "setup.py": "python",
        "requirements.txt": "python",
        "Gemfile": "ruby",
        "pom.xml": "java",
        "build.gradle": "java",
        "CMakeLists.txt": "cpp",
        "Makefile": "make",
        "Dockerfile": "docker",
        "docker-compose.yml": "docker",
    }
    found = []
    base_path = Path(cwd or ".")
    for marker, lang in markers.items():
        if (base_path / marker).exists():
            found.append(lang)
    return found or ["unknown"]


def classify_files(files: list[dict]) -> dict:
    """Classify files into logical groups."""
    groups = defaultdict(list)
    categories = {
        "test": [],
        "config": [],
        "docs": [],
        "ci": [],
        "source": [],
        "assets": [],
    }

    test_patterns = re.compile(r"(test[_/]|_test\.|\.test\.|spec[/_]|_spec\.|\.spec\.|__tests__)", re.I)
    config_patterns = re.compile(r"(\.env|config[._]|settings[._]|\.rc$|\.ya?ml$|\.toml$|\.json$|\.ini$)", re.I)
    doc_patterns = re.compile(r"(\.md$|\.rst$|\.txt$|docs?/|README|CHANGELOG|LICENSE)", re.I)
    ci_patterns = re.compile(r"(\.github/|\.gitlab|\.circleci|\.travis|Jenkinsfile|\.ci)", re.I)
    asset_patterns = re.compile(r"(\.(png|jpg|jpeg|gif|svg|ico|woff|ttf|eot|mp[34]|wav)$)", re.I)

    for f in files:
        p = f["path"]
        if test_patterns.search(p):
            categories["test"].append(f)
        elif ci_patterns.search(p):
            categories["ci"].append(f)
        elif doc_patterns.search(p):
            categories["docs"].append(f)
        elif config_patterns.search(p):
            categories["config"].append(f)
        elif asset_patterns.search(p):
            categories["assets"].append(f)
        else:
            categories["source"].append(f)

        # Group by top-level directory
        parts = p.split("/")
        if len(parts) > 1:
            groups[parts[0]].append(f)
        else:
            groups["."].append(f)

    return {
        "categories": {k: v for k, v in categories.items() if v},
        "by_directory": {k: [f["path"] for f in v] for k, v in groups.items()},
    }


def infer_change_type(files: list[dict], diff_preview: str) -> dict:
    """Infer the primary change type from file patterns and diff content.

    Uses a scoring model: each candidate type accumulates points from
    structural signals (file statuses) and keyword signals (diff content).
    The highest-scoring type wins; ties fall back to a conservative chore.
    """
    has_new = any(f["status"] == "A" for f in files)
    has_delete = any(f["status"] == "D" for f in files)
    has_modify = any(f["status"] in ("M", "R") for f in files)
    has_rename = any(f["status"] == "R" for f in files)
    has_tests = bool(re.search(r"(test[_/]|_test\.|\.test\.)", "\n".join(f["path"] for f in files), re.I))
    has_docs = bool(re.search(r"(\.md$|docs?/)", "\n".join(f["path"] for f in files), re.I))
    only_tests = has_tests and all(
        re.search(r"(test[_/]|_test\.|\.test\.|spec[/_]|_spec\.|\.spec\.)", f["path"], re.I) for f in files
    )
    only_docs = has_docs and all(re.search(r"(\.md$|\.rst$|\.txt$|docs?/)", f["path"], re.I) for f in files)

    # Check for refactoring signals: new + delete of similar files
    new_paths = {f["path"] for f in files if f["status"] == "A"}
    del_paths = {f["path"] for f in files if f["status"] == "D"}
    is_rename_heavy = has_new and has_delete and len(new_paths) > 0 and len(del_paths) > 0

    # Check diff for feature/fix signals. Word boundaries avoid substring
    # false positives (e.g. "add" in "addition", "fix" in "prefix"). "new" is
    # intentionally dropped — too noisy (matches new_feature, renew, newest).
    feat_signals = len(re.findall(r"^\+.*\b(?:feat|feature|add|implement|create)\b", diff_preview, re.I | re.M))
    fix_signals = len(re.findall(r"^\+.*\b(?:fix|bug|patch|resolve|correct|repair)\b", diff_preview, re.I | re.M))
    refactor_signals = len(
        re.findall(
            r"^\+.*\b(?:refactor|rename|move|extract|reorganiz)\w*\b",
            diff_preview,
            re.I | re.M,
        )
    )

    # Primary inference. Exclusive strong signals (all-docs / all-tests) are
    # checked first; everything else goes through a scoring model where each
    # type accumulates points from structural and keyword signals.
    #   keyword: 2 pts per signal line (weak → low confidence)
    #   structural: 5 pts (medium confidence, e.g. rename / new file)
    # Ties fall back to a conservative chore so the LLM makes the call.
    if only_docs:
        primary, confidence = "docs", "high"
    elif only_tests:
        primary, confidence = "test", "high"
    else:
        scores = {
            "feat": feat_signals * 2 + (5 if has_new and not has_delete else 0),
            "fix": fix_signals * 2,
            "refactor": (
                refactor_signals * 2
                + (5 if has_rename and feat_signals == 0 and fix_signals == 0 else 0)
                + (5 if is_rename_heavy and refactor_signals > feat_signals else 0)
            ),
        }
        top_score = max(scores.values())
        if top_score == 0:
            # No signal of any kind — conservative default.
            primary, confidence = "chore", "low"
        else:
            leaders = [k for k, v in scores.items() if v == top_score]
            if len(leaders) == 1:
                primary = leaders[0]
                # Structural evidence is trustworthy enough for medium;
                # keyword-only evidence stays low.
                structural = (
                    (primary == "feat" and has_new and not has_delete)
                    or (primary == "refactor" and (
                        (has_rename and feat_signals == 0 and fix_signals == 0)
                        or (is_rename_heavy and refactor_signals > feat_signals)
                    ))
                )
                confidence = "medium" if structural else "low"
            else:
                # Tie (e.g. feat == fix) — ambiguous, let LLM decide.
                primary, confidence = "chore", "low"

    return {
        "primary_type": primary,
        "confidence": confidence,
        "note": (
            "Type is only a heuristic; inspect the diff before composing the message."
            if confidence == "low"
            else None
        ),
        "signals": {
            "new_files": len(new_paths),
            "deleted_files": len(del_paths),
            "modified_files": sum(1 for f in files if f["status"] in ("M", "R")),
            "feat_signals": feat_signals,
            "fix_signals": fix_signals,
            "refactor_signals": refactor_signals,
        },
    }


def build_output(cwd: str | None = None) -> dict:
    """Build the full analysis."""
    files = get_staged_files(cwd=cwd)
    if not files:
        return {"error": "No staged changes found. Stage files with 'git add' first."}

    numstat = get_diff_numstat(cwd=cwd)
    diff_preview = get_staged_diff_preview(cwd=cwd)

    # Merge numstat into files
    numstat_map = {s["path"]: s for s in numstat}
    for f in files:
        ns = numstat_map.get(f["path"], {})
        f["insertions"] = ns.get("insertions", 0)
        f["deletions"] = ns.get("deletions", 0)
        f["binary"] = ns.get("binary", False)

    classification = classify_files(files)
    change_type = infer_change_type(files, diff_preview)
    context = detect_commitlint(cwd=cwd)
    context["project_types"] = detect_project_type(cwd=cwd)
    context["is_merge"] = check_merge_commit(cwd=cwd)

    total_ins = sum(f.get("insertions", 0) for f in files)
    total_dels = sum(f.get("deletions", 0) for f in files)
    total_changes = total_ins + total_dels
    binary_files = [f["path"] for f in files if f.get("binary")]

    return {
        "schema_version": SCHEMA_VERSION,
        "summary": {
            "total_files": len(files),
            "total_insertions": total_ins,
            "total_deletions": total_dels,
            "is_large_diff": total_changes > LARGE_DIFF_LINES,
        },
        "diff_preview": diff_preview if total_changes <= DIFF_PREVIEW_INLINE_LIMIT else None,
        "files": [
            {
                "path": f["path"],
                "status": f["raw_status"],
                "insertions": f.get("insertions", 0),
                "deletions": f.get("deletions", 0),
                "binary": f.get("binary", False),
            }
            for f in files
        ],
        "classification": classification,
        "change_type_inference": change_type,
        "context": context,
        "warnings": {
            "binary_files": binary_files if binary_files else None,
            "large_diff": total_ins + total_dels > LARGE_DIFF_LINES,
            "merge_commit": context["is_merge"],
            "many_unrelated_changes": len(classification["by_directory"]) > 5 and len(files) > 15,
        },
    }


def main():
    parser = argparse.ArgumentParser(description="Analyze git staged changes.")
    parser.add_argument("--workdir", default=None, help="Git repo path (default: cwd)")
    args = parser.parse_args()

    cwd = args.workdir

    if not is_git_repo(cwd):
        print(json.dumps({"schema_version": SCHEMA_VERSION, "error": "Not inside a git repository."}))
        sys.exit(1)

    output = build_output(cwd)
    if "error" in output:
        print(json.dumps({"schema_version": SCHEMA_VERSION, **output}))
        sys.exit(1)

    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
