#!/bin/bash
# Copy libretro .info metadata for the enabled PSC core set.
set -e

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <cores.txt> <libretro-super-dir> <output-info-dir>" >&2
    exit 1
fi

CORES_FILE="$1"
LIBRETRO_SUPER_DIR="$2"
OUTPUT_INFO_DIR="$3"
SOURCE_INFO_DIR="$LIBRETRO_SUPER_DIR/dist/info"

if [ ! -f "$CORES_FILE" ]; then
    echo "Error: cores file not found: $CORES_FILE" >&2
    exit 1
fi

if [ ! -d "$SOURCE_INFO_DIR" ]; then
    echo "Error: libretro-super info directory not found: $SOURCE_INFO_DIR" >&2
    exit 1
fi

info_source_name() {
    case "$1" in
        bsnes_performance)
            echo "bsnes2014_performance"
            ;;
        doublecherrygb)
            echo "DoubleCherryGB"
            ;;
        parallext)
            echo "parallel_n64"
            ;;
        *)
            echo "$1"
            ;;
    esac
}

mkdir -p "$OUTPUT_INFO_DIR"
rm -f "$OUTPUT_INFO_DIR"/*.info

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

sed 's/#.*//' "$CORES_FILE" | tr -d ' \t' | grep -v '^$' > "$tmp_dir/cores"

missing=0
copied=0

while IFS= read -r core; do
    source_name="$(info_source_name "$core")"
    source_file="$SOURCE_INFO_DIR/${source_name}_libretro.info"
    output_file="$OUTPUT_INFO_DIR/${core}_libretro.info"

    if [ ! -f "$source_file" ]; then
        echo "Missing info for $core (looked for ${source_name}_libretro.info)" >&2
        missing=1
        continue
    fi

    cp "$source_file" "$output_file"
    copied=$((copied + 1))
done < "$tmp_dir/cores"

if [ "$missing" -ne 0 ]; then
    exit 1
fi

expected="$(wc -l < "$tmp_dir/cores" | tr -d ' ')"
echo "Wrote $copied/$expected core info files to $OUTPUT_INFO_DIR"
