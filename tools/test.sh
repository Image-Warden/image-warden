#!/usr/bin/env bash
# Run Image-Warden's Bash test suite.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT"

if [[ $# -gt 0 ]]; then
    tests=("$@")
else
    mapfile -t tests < <(find tests -maxdepth 1 -name 'test_*.sh' -print | sort)
fi

if [[ ${#tests[@]} -eq 0 ]]; then
    echo "ERROR: no tests found" >&2
    exit 1
fi

chmod +x bin/iw-* tests/helpers/fakebin/* 2>/dev/null || true

failed=0
for test_file in "${tests[@]}"; do
    if [[ ! -f "$test_file" ]]; then
        echo "not ok - $test_file (not found)"
        failed=$(( failed + 1 ))
        continue
    fi

    echo "==> $test_file"
    if bash "$test_file"; then
        echo "ok - $test_file"
    else
        echo "not ok - $test_file"
        failed=$(( failed + 1 ))
    fi
done

if [[ $failed -gt 0 ]]; then
    echo "ERROR: ${failed} test file(s) failed" >&2
    exit 1
fi

echo "All test files passed."
