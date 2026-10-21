#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
    cat <<'EOF'
Usage: scripts/make-dmg.sh <app bundle> <output.dmg>

Packs the app into a compressed disk image with an Applications shortcut, so
installing is "open the DMG, drag the app onto Applications". Also writes
<output.dmg>.sha256 for the release page.
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

    local app="$1"
    local dmg="$2"
    if [[ ! -d "$app" ]]; then
        echo "error: no app bundle at $app (run make app first)" >&2
        exit 1
    fi

    local staging
    staging="$(mktemp -d)"
    trap 'rm -rf "$staging"' EXIT
    cp -R "$app" "$staging/"
    ln -s /Applications "$staging/Applications"

    rm -f "$dmg"
    hdiutil create -volname "Silicon Reader" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
    (cd "$(dirname "$dmg")" && shasum -a 256 "$(basename "$dmg")" >"$(basename "$dmg").sha256")
    echo "built $dmg"
}

main "$@"
