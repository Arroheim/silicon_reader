#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
    cat <<'EOF'
Usage: scripts/check-binary.sh <executable> <min macOS> <SDK version>

Checks what the linker recorded in the app binary:
  - the deployment target (minos) is <min macOS>, so the app still runs there;
  - the SDK is <SDK version>, so the build gets the same AppKit behavior as a
    release built with that SDK (a mismatch means the link lost the SDK);
  - it only links system libraries, which every supported macOS has;
  - the bundle's LSMinimumSystemVersion is <min macOS> too.
Exits 1 on the first mismatch.
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

# "minos 14.0" / "sdk 26.5" lines of the LC_BUILD_VERSION load command.
build_field() {
    local binary="$1"
    local field="$2"
    vtool -show-build "$binary" | awk -v field="$field" '$1 == field { print $2; exit }'
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi
    if [[ $# -ne 3 ]]; then
        usage >&2
        exit 64
    fi

    local binary="$1"
    local min_macos="$2"
    local sdk="$3"
    [[ -f "$binary" ]] || fail "no binary at $binary"

    local minos recorded_sdk
    minos="$(build_field "$binary" minos)"
    recorded_sdk="$(build_field "$binary" sdk)"
    [[ "$minos" == "$min_macos" ]] || fail "deployment target is $minos, expected $min_macos"
    [[ "$recorded_sdk" == "$sdk" ]] || fail "linked against SDK $recorded_sdk, expected $sdk"

    local foreign
    foreign="$(otool -L "$binary" | awk 'NR > 1 { print $1 }' | grep -Ev '^(/System/|/usr/lib/)' || true)"
    [[ -z "$foreign" ]] || fail "links non-system libraries: $foreign"

    local plist minimum
    plist="$(dirname "$(dirname "$binary")")/Info.plist"
    if [[ -f "$plist" ]]; then
        minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")"
        [[ "$minimum" == "$min_macos" ]] || fail "LSMinimumSystemVersion is $minimum, expected $min_macos"
    fi

    echo "ok $binary: macOS $minos+, SDK $recorded_sdk, system libraries only"
}

main "$@"
