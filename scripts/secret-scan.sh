#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/.gitleaks.toml"

paths=("$@")
if [ "${#paths[@]}" -eq 0 ]; then
    paths=("$ROOT")
fi

scan_with_gitleaks() {
    local path="$1"
    if command -v gitleaks >/dev/null 2>&1; then
        gitleaks detect \
            --source "$path" \
            --no-git \
            --redact \
            --no-banner \
            --config "$CONFIG" \
            --verbose
        return
    fi
    if command -v docker >/dev/null 2>&1; then
        local abs_path
        abs_path="$(realpath "$path")"
        docker run --rm \
            -v "$abs_path:/repo:ro" \
            -v "$CONFIG:/config.toml:ro" \
            zricethezav/gitleaks:latest detect \
            --source /repo \
            --no-git \
            --redact \
            --no-banner \
            --config /config.toml \
            --verbose
        return
    fi
    return 1
}

scan_with_trufflehog() {
    local path="$1"
    trufflehog filesystem "$path" --no-verification --fail
}

status=0
for path in "${paths[@]}"; do
    if [ ! -e "$path" ]; then
        echo "Path not found: $path" >&2
        exit 2
    fi
    echo "Scanning $path"
    if command -v gitleaks >/dev/null 2>&1 || command -v docker >/dev/null 2>&1; then
        scan_with_gitleaks "$path" || status=1
    elif command -v trufflehog >/dev/null 2>&1; then
        scan_with_trufflehog "$path" || status=1
    else
        echo "Install gitleaks or trufflehog (or run Docker) to scan for secrets." >&2
        exit 2
    fi
done
exit "$status"
