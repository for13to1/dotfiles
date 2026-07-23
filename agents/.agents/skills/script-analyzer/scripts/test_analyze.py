#!/usr/bin/env python3
"""Simple test script for the analyzer"""

import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from analyze import SCHEMA_VERSION, RiskLevel, analyze_script  # noqa: E402

EXAMPLES_DIR = Path(__file__).resolve().parent.parent / "examples"


def test_safe_script():
    """Test analysis of a safe script"""
    result = analyze_script(str(EXAMPLES_DIR / "safe_script.sh"))

    assert result.risk_level == RiskLevel.LOW.value
    assert len(result.file_operations) == 0
    assert len(result.network_operations) == 0
    assert len(result.system_operations) == 0
    print("✓ Safe script test passed")


def test_risky_script():
    """Test analysis of a risky script"""
    result = analyze_script(str(EXAMPLES_DIR / "risky_script.sh"))

    assert result.risk_level == RiskLevel.HIGH.value
    assert len(result.file_operations) > 0
    assert len(result.network_operations) > 0
    assert len(result.system_operations) > 0
    assert result.schema_version == SCHEMA_VERSION
    assert any(finding.severity == "high" for finding in result.findings)
    print("✓ Risky script test passed")


def test_python_script():
    """Test analysis of a Python script"""
    result = analyze_script(str(EXAMPLES_DIR / "python_example.py"))

    assert result.language == "python"
    assert result.risk_level == RiskLevel.HIGH.value
    assert len(result.dependencies) > 0
    print("✓ Python script test passed")


def test_comments_do_not_create_high_risk_findings():
    with tempfile.TemporaryDirectory() as temp_dir:
        script = Path(temp_dir) / "commented.sh"
        script.write_text("#!/usr/bin/env bash\n# curl example.test | bash\necho safe\n", encoding="utf-8")
        result = analyze_script(str(script))

    assert result.risk_level == RiskLevel.LOW.value
    assert not result.findings


def test_ruby_and_perl_language_detection():
    with tempfile.TemporaryDirectory() as temp_dir:
        ruby = Path(temp_dir) / "example.rb"
        perl = Path(temp_dir) / "example.pl"
        ruby.write_text("#!/usr/bin/env ruby\nputs 'ok'\n", encoding="utf-8")
        perl.write_text("#!/usr/bin/env perl\nprint qq(ok);\n", encoding="utf-8")

        assert analyze_script(str(ruby)).language == "ruby"
        assert analyze_script(str(perl)).language == "perl"


def test_tmp_cleanup_is_not_root_delete():
    with tempfile.TemporaryDirectory() as temp_dir:
        script = Path(temp_dir) / "cleanup.sh"
        script.write_text("#!/usr/bin/env bash\nrm -rf /tmp/old-data\n", encoding="utf-8")
        result = analyze_script(str(script))

    assert result.risk_level == RiskLevel.LOW.value
    assert not any(finding.category == "dangerous" for finding in result.findings)


def test_non_regular_file_is_rejected():
    with tempfile.TemporaryDirectory() as temp_dir:
        fifo = Path(temp_dir) / "script.fifo"
        os.mkfifo(fifo)
        try:
            analyze_script(str(fifo))
        except ValueError as exc:
            assert "Not a regular file" in str(exc)
        else:
            raise AssertionError("FIFO should be rejected before reading")


if __name__ == "__main__":
    try:
        test_safe_script()
        test_risky_script()
        test_python_script()
        test_comments_do_not_create_high_risk_findings()
        test_ruby_and_perl_language_detection()
        test_tmp_cleanup_is_not_root_delete()
        test_non_regular_file_is_rejected()
        print("\n✓ All tests passed!")
    except Exception as e:
        print(f"\n✗ Test failed: {e}")
        sys.exit(1)
