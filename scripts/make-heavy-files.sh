#!/usr/bin/env bash
# Generates scan-like documents for manual tests of large files: a PDF and a DjVu
# whose every page is a full-page noisy color image. Needs DjVuLibre and ImageMagick
# (`brew install djvulibre imagemagick`). Takes minutes and about 1.5 GB.
set -euo pipefail
IFS=$'\n\t'

readonly BASE_PAGES=20
readonly WIDTH=2550
readonly HEIGHT=3300

usage() {
    echo "usage: scripts/make-heavy-files.sh <output folder> [pages]  (run from the repository root; default 1000 pages)"
}

main() {
    if [[ $# -lt 1 || "${1:-}" == "--help" ]]; then
        usage
        return 64
    fi
    local output="$1" pages="${2:-1000}" root work
    root="$PWD"
    mkdir -p "$output"
    output=$(cd "$output" && pwd)
    work=$(mktemp -d)
    # shellcheck disable=SC2064  # expand now: `work` is local to main
    trap "rm -rf '$work'" EXIT

    local page name
    local -a jpegs=() djvus=()
    for page in $(seq 1 "$BASE_PAGES"); do
        name=$(printf 'base%02d' "$page")
        ddjvu -format=ppm -page="$page" "$root/Tests/ReaderCoreTests/Fixtures/djvu2spec.djvu" "$work/$name.source.ppm"
        # Warm paper and sensor noise make the page hard to compress, as a real scan is.
        magick "$work/$name.source.ppm" -fill '#f4ecd8' -tint 100 -attenuate 0.6 +noise Gaussian \
            -quality 80 "$work/$name.jpg"
        magick "$work/$name.jpg" "$work/$name.ppm"
        c44 -dpi 300 "$work/$name.ppm" "$work/$name.djvu"
        rm "$work/$name.source.ppm" "$work/$name.ppm"
        jpegs+=("$work/$name.jpg")
        echo "page $page of $BASE_PAGES"
    done

    swift "$root/scripts/make-image-pdf.swift" "$output/heavy-scan.pdf" "$pages" "$WIDTH" "$HEIGHT" "${jpegs[@]}"

    for page in $(seq 1 "$pages"); do
        name=$(printf 'p%05d.djvu' "$page")
        cp "$work/base$(printf '%02d' $(((page - 1) % BASE_PAGES + 1))).djvu" "$work/$name"
        djvus+=("$name")
    done
    (cd "$work" && djvm -c "$output/heavy-scan.djvu" "${djvus[@]}")

    ls -lh "$output/heavy-scan.pdf" "$output/heavy-scan.djvu"
}

main "$@"
