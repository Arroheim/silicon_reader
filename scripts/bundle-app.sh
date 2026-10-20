#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
    cat <<'EOF'
Usage: scripts/bundle-app.sh <binary> <output.app>

Wraps a built executable into a macOS .app bundle using Resources/Info.plist,
builds AppIcon.icns from Resources/AppIcon.png and signs the bundle ad hoc so
it launches locally without Gatekeeper prompts.
EOF
}

# Renders every size an .icns needs from a 1024x1024 PNG.
make_icns() {
    local png="$1"
    local icns="$2"
    local iconset
    iconset="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$iconset"
    local size
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
        sips -z "$((size * 2))" "$((size * 2))" "$png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$iconset" -o "$icns"
    rm -rf "$(dirname "$iconset")"
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
    make_icns "$root/Resources/AppIcon.png" "$app/Contents/Resources/AppIcon.icns"
    codesign --force --sign - "$app"
    echo "built $app"
}

main "$@"
