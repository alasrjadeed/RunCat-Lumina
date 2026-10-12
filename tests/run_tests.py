#!/usr/bin/env python3
"""
Test runner for RunCat Lumina
"""
import subprocess
import sys
import os
from pathlib import Path


def run_test_file(test_file):
    """Run a single test file and return success status"""
    print(f"\n{'='*50}")
    print(f"Running {test_file.name}")
    print('='*50)

    try:
        result = subprocess.run(
            [sys.executable, str(test_file)],
            cwd=test_file.parent.parent,
            capture_output=True,
            text=True,
            timeout=30
        )

        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)

        return result.returncode == 0
    except subprocess.TimeoutExpired:
        print(f"ERROR: {test_file.name} timed out")
        return False
    except Exception as e:
        print(f"ERROR running {test_file.name}: {e}")
        return False


def main():
    """Run all test files"""
    tests_dir = Path(__file__).parent
    test_files = list(tests_dir.glob("test_*.py"))

    if not test_files:
        print("No test files found!")
        return 1

    print(f"Found {len(test_files)} test file(s)")

    passed = 0
    failed = 0

    for test_file in sorted(test_files):
        if run_test_file(test_file):
            passed += 1
            print(f"✓ {test_file.name} PASSED")
        else:
            failed += 1
            print(f"✗ {test_file.name} FAILED")

    print(f"\n{'='*50}")
    print(f"TEST RESULTS: {passed} passed, {failed} failed")
    print('='*50)

    return 1 if failed > 0 else 0


if __name__ == "__main__":
    sys.exit(main())