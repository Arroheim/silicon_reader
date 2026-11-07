#!/usr/bin/env bash
# Rebuilds the derived DjVu fixtures from djvu2spec.djvu. Needs DjVuLibre
# (`brew install djvulibre`); the results are committed, so tests don't need it.
#
#   long-incl-id.djvu  pages 1-2, sharing a JB2 dictionary named by a 90-byte INCL id
#   broken-page.djvu   pages 1-2, page 2's JB2 data overwritten with garbage
set -euo pipefail
IFS=$'\n\t'

usage() {
    echo "usage: scripts/make-djvu-fixtures.sh  (run from the repository root)"
}

# remake_page <source> <output> <INCL id>: the same page, with its dictionary under that id.
remake_page() {
    local size
    size=$(djvudump "$1" | grep -m1 'INFO' | sed -E 's/.*DjVu ([0-9]+)x([0-9]+).*/\1,\2/')
    djvuextract "$1" Sjbz="$1.sjbz" TXTz="$1.txtz" >/dev/null 2>&1
    djvumake "$2" INFO="$size,300" INCL="$3" Sjbz="$1.sjbz" TXTz="$1.txtz"
}

# corrupt_second_page <file>: overwrites the JB2 data of the second Sjbz chunk in
# place. Fixed bytes keep the fixture reproducible; the chunk structure stays
# intact, so the file opens and only decoding that page fails.
corrupt_second_page() {
    local offset
    offset=$(LC_ALL=C grep -abo 'Sjbz' "$1" | sed -n 2p | cut -d: -f1)
    head -c 256 /dev/zero | LC_ALL=C tr '\0' '\377' |
        dd of="$1" bs=1 seek=$((offset + 8)) conv=notrunc 2>/dev/null
}

main() {
    if [[ "${1:-}" == "--help" ]]; then
        usage
        return
    fi
    local fixtures work dictionary
    fixtures="$PWD/Tests/ReaderCoreTests/Fixtures"
    work=$(mktemp -d)
    # shellcheck disable=SC2064  # expand now: `work` is local to main
    trap "rm -rf '$work'" EXIT

    djvmcvt -i "$fixtures/djvu2spec.djvu" "$work" index.djvu
    cd "$work"

    # 90 bytes: djvudec used to cut INCL ids to 63.
    dictionary="$(printf 'd%.0s' {1..86}).iff"
    cp dict0039.iff "$dictionary"
    remake_page p0001.djvu long1.djvu "$dictionary"
    remake_page p0002.djvu long2.djvu "$dictionary"
    djvm -c long-incl-id.djvu long1.djvu long2.djvu

    djvm -c broken-page.djvu p0001.djvu p0002.djvu
    corrupt_second_page broken-page.djvu

    cp long-incl-id.djvu broken-page.djvu "$fixtures/"
    ls -l "$fixtures/long-incl-id.djvu" "$fixtures/broken-page.djvu"
}

main "$@"
