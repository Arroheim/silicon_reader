#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
    cat <<'EOF'
Usage: scripts/bundle-app.sh <binary> <output.app>

Wraps a built executable into a macOS .app bundle using Resources/Info.plist
and signs it ad hoc so it launches locally without Gatekeeper prompts.
EOF
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi
    if [[ $# -ne 2 ]]; then
        usage >&2
        exit 64
    fi

    local binary="$1"
    local app="$2"
    local root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    if [[ ! -x "$binary" ]]; then
        echo "error: binary not found or not executable: $binary" >&2
        exit 1
    fi

    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$binary" "$app/Contents/MacOS/"
    cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
    codesign --force --sign - "$app"
    echo "built $app"
}

main "$@"
