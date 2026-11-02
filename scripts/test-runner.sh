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
#
# Two server generations are supported:
#   * older images (19.0.6) log "odoo.tests.result: X failed, Y error(s) of Z
#     tests when loading database '...'";
#   * newer images (19.0.9) only log "<n> post-tests in <t>s" and report the
#     outcome through the process exit code.

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
# Note: no `|| true` on the pipeline, it would reset PIPESTATUS and lose the
# Odoo exit code, which is what reports the outcome on the newer images.
set +e
"$@" 2>&1 | tee "$LOGFILE" | grep -E \
    '(Starting test_|post-tests in|odoo\.tests\.(result|stats)|Modules loaded|Loading module|Traceback|FAIL:|ERROR:)' \
    | grep -v 'result = loader'
RC=${PIPESTATUS[0]}
set -e

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RESULT_LINE=$(grep 'odoo.tests.result:' "$LOGFILE" 2>/dev/null || true)
MODULE_STATS=$(grep 'odoo.tests.stats:' "$LOGFILE" 2>/dev/null || true)
POST_LINE=$(grep 'post-tests in ' "$LOGFILE" 2>/dev/null | tail -n1 || true)
# Real test failures only; skip the ORM noise ("bad query", "Access Denied").
DETAILS=$(grep -E 'odoo\.addons\..*\.tests\..*: (FAIL|ERROR): ' "$LOGFILE" 2>/dev/null || true)

print_module_stats() {
    if [ -n "$MODULE_STATS" ]; then
        echo ""
        echo "  Per module:"
        printf '%s\n' "$MODULE_STATS" | sed 's/.*odoo\.tests\.stats: /    /' | sort
    fi
}

print_details_and_fail() {
    echo ""
    if [ -n "$DETAILS" ]; then
        echo "  Failed/Error details:"
        printf '%s\n' "$DETAILS" | head -40
    else
        echo "  No per-test failure line found: Odoo exited with code $RC."
    fi
    echo ""
    # Keep the log on failure so it can be inspected.
    trap - EXIT
    echo "  Full log: $LOGFILE"
    exit 1
}

if [ -n "$RESULT_LINE" ]; then
    # Older images: the result line carries the counts.
    FAILED=$(printf '%s\n' "$RESULT_LINE" | sed -n 's/.*\([0-9]\+\) failed.*/\1/p')
    ERRORS=$(printf '%s\n' "$RESULT_LINE" | sed -n 's/.*\([0-9]\+\) error(s).*/\1/p')
    TOTAL=$(printf '%s\n' "$RESULT_LINE" | sed -n 's/.*of \([0-9]\+\) tests.*/\1/p')
    PASSED=$((TOTAL - FAILED - ERRORS))

    echo "  Total:  $TOTAL tests"
    echo "  Passed: $PASSED"
    echo "  Failed: $FAILED"
    echo "  Errors: $ERRORS"
    print_module_stats

    if [ "$FAILED" -gt 0 ] || [ "$ERRORS" -gt 0 ] || [ "$RC" -ne 0 ]; then
        print_details_and_fail
    fi

    echo ""
    echo "  All tests passed."
    exit 0
fi

# Newer images: no result line, the exit code is the source of truth.
FAILED=$(printf '%s\n' "$DETAILS" | grep -c ': FAIL: ' || true)
ERRORS=$(printf '%s\n' "$DETAILS" | grep -c ': ERROR: ' || true)

if [ -n "$POST_LINE" ]; then
    echo "  Post-tests: $(printf '%s' "$POST_LINE" | sed 's/.*odoo\.service\.server: //')"
fi
print_module_stats

if [ "$RC" -eq 0 ] && [ "$FAILED" -eq 0 ] && [ "$ERRORS" -eq 0 ]; then
    echo ""
    echo "  All tests passed."
    exit 0
fi

echo "  Failed: $FAILED"
echo "  Errors: $ERRORS"
echo "  Odoo exit code: $RC"
print_details_and_fail
