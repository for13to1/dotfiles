#!/usr/bin/env python3
"""Simple test script for the analyzer"""

import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from analyze import RiskLevel, analyze_script  # noqa: E402

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
    print("✓ Risky script test passed")


def test_python_script():
    """Test analysis of a Python script"""
    result = analyze_script(str(EXAMPLES_DIR / "python_example.py"))

    assert result.language == "python"
    assert result.risk_level == RiskLevel.HIGH.value
    assert len(result.dependencies) > 0
    print("✓ Python script test passed")


if __name__ == "__main__":
    try:
        test_safe_script()
        test_risky_script()
        test_python_script()
        print("\n✓ All tests passed!")
    except Exception as e:
        print(f"\n✗ Test failed: {e}")
        sys.exit(1)
