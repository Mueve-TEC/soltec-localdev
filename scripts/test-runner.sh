#!/usr/bin/env bash
# test-runner.sh — Run Odoo tests with filtered output and a summary at the end.
#
# Usage: bash scripts/test-runner.sh <odoo-cli-command...>
#   The command should include all flags (--addons-path, -d, -u, --test-enable, etc.)
#
# Example:
#   bash scripts/test-runner.sh docker compose exec web odoo \
#     --addons-path=/mnt/custom-addons,/usr/lib/python3/dist-packages/odoo/addons \
#     --db_host=db --db_user=odoo --db_password=odoo \
#     -d sindicato -u union_affiliation --test-enable --stop-after-init \
#     --http-port=8099 --log-level=info

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <odoo-cli-command...>" >&2
    exit 1
fi

LOGFILE=$(mktemp /tmp/odoo-test-XXXXXX.log)
trap 'rm -f "$LOGFILE"' EXIT

echo "Running: $*"
echo "Log: $LOGFILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Run the command, tee to both stdout (for live view) and the log file.
# Filter the live view to show only test-relevant lines (skip ORM noise).
"$@" 2>&1 | tee "$LOGFILE" | grep -E \
    '(Starting test_|test_.*\.\.\.|PASS|FAIL|odoo\.tests\.(result|stats)|Modules loaded|Loading module|Traceback|Error:|assert)' \
    | grep -v 'result = loader' \
    || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Parse Odoo's own result line:
#   odoo.tests.result: X failed, Y error(s) of Z tests when loading database '...'
RESULT_LINE=$(grep 'odoo.tests.result:' "$LOGFILE" 2>/dev/null || true)

if [ -n "$RESULT_LINE" ]; then
    FAILED=$(echo "$RESULT_LINE" | sed -n 's/.*\([0-9]\+\) failed.*/\1/p')
    ERRORS=$(echo "$RESULT_LINE" | sed -n 's/.*\([0-9]\+\) error(s).*/\1/p')
    TOTAL=$(echo "$RESULT_LINE" | sed -n 's/.*of \([0-9]\+\) tests.*/\1/p')
    PASSED=$((TOTAL - FAILED - ERRORS))

    echo "  Total:  $TOTAL tests"
    echo "  Passed: $PASSED"
    echo "  Failed: $FAILED"
    echo "  Errors: $ERRORS"

    # Show per-module stats if available
    MODULE_STATS=$(grep 'odoo.tests.stats:' "$LOGFILE" 2>/dev/null || true)
    if [ -n "$MODULE_STATS" ]; then
        echo ""
        echo "  Per module:"
        echo "$MODULE_STATS" | sed 's/.*odoo\.tests\.stats: /    /' | sort
    fi

    if [ "$FAILED" -gt 0 ] || [ "$ERRORS" -gt 0 ]; then
        echo ""
        echo "  Failed/Error details:"
        grep -B1 -A3 'FAIL\|Error' "$LOGFILE" 2>/dev/null | grep -v 'result = loader' | head -60
        echo ""
        exit 1
    else
        echo ""
        echo "  All tests passed."
        exit 0
    fi
else
    echo "  (Could not find odoo.tests.result line in log)"
    echo "  Check the log: $LOGFILE"
    exit 1
fi
