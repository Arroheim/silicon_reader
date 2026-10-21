#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
    cat <<'EOF'
Usage: scripts/release-notes.sh <version> [CHANGELOG.md]

Prints the release notes for <version> (e.g. 1.0.0): its section of the
changelog followed by install instructions. Exits 1 if the changelog has no
"## [<version>]" section, so a release can't go out without notes.
EOF
}

# The lines between "## [<version>]" and the next "## [" heading.
changelog_section() {
    local version="$1"
    local changelog="$2"
    awk -v heading="## [${version}]" '
        index($0, heading) == 1 { inside = 1; next }
        inside && /^## \[/       { exit }
        inside                   { print }
    ' "$changelog"
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi
    if [[ $# -lt 1 ]]; then
        usage >&2
        exit 64
    fi

    local version="$1"
    local changelog="${2:-CHANGELOG.md}"
    local section
    section="$(changelog_section "$version" "$changelog")"
    if [[ -z "${section//[[:space:]]/}" ]]; then
        echo "error: no \"## [$version]\" section in $changelog" >&2
        exit 1
    fi

    printf '%s\n' "$section"
    cat <<EOF

## 📥 Install

1. Download \`SiliconReader-${version}.dmg\` below, open it and drag **SiliconReader** onto **Applications**.
2. The app is not notarized by Apple yet, so the first launch is blocked. Either open
   **System Settings → Privacy & Security** and click **Open Anyway**, or run:
   \`\`\`bash
   xattr -dr com.apple.quarantine /Applications/SiliconReader.app
   \`\`\`

Requires macOS 14 or later on Apple Silicon. Check the download with the \`.sha256\` file:
\`shasum -a 256 -c SiliconReader-${version}.dmg.sha256\`.
EOF
}

main "$@"
