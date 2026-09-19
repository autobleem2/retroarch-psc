#!/bin/bash
# Compare cores.txt against the core rules available in the pinned libretro-super checkout.
set -euo pipefail

CORES_FILE="${1:-cores.txt}"
LIBRETRO_SUPER_DIR="${2:-/build/libretro-super}"

if [ ! -f "$CORES_FILE" ]; then
    echo "Error: $CORES_FILE not found" >&2
    exit 1
fi

if [ ! -f "$LIBRETRO_SUPER_DIR/rules.d/core-rules.sh" ]; then
    echo "Error: $LIBRETRO_SUPER_DIR/rules.d/core-rules.sh not found" >&2
    exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

enabled="$TMP_DIR/enabled"
disabled="$TMP_DIR/disabled"
listed="$TMP_DIR/listed"
core_rules="$TMP_DIR/core-rules"

sed 's/#.*//' "$CORES_FILE" | tr -d ' \t' | grep -v '^$' | LC_ALL=C sort -u > "$enabled"

awk '
  /^# [a-z0-9_]/ && /Disabled:/ {
    line=$0
    sub(/^# */, "", line)
    sub(/ .*/, "", line)
    print line
  }
' "$CORES_FILE" | LC_ALL=C sort -u > "$disabled"

cat "$enabled" "$disabled" | LC_ALL=C sort -u > "$listed"

grep -ho '^include_core_[A-Za-z0-9_]*()' "$LIBRETRO_SUPER_DIR/rules.d/core-rules.sh" \
    | sed 's/^include_core_//;s/()$//' \
    | LC_ALL=C sort -u > "$core_rules"

echo "=== Core List Audit ==="
printf 'Enabled in cores.txt: %s\n' "$(wc -l < "$enabled")"
printf 'Disabled/commented in cores.txt: %s\n' "$(wc -l < "$disabled")"
printf 'Listed total: %s\n' "$(wc -l < "$listed")"
printf 'Core rules in libretro-super: %s\n' "$(wc -l < "$core_rules")"
echo ""

show_section() {
    title="$1"
    file="$2"
    count=$(wc -l < "$file")
    echo "=== $title ($count) ==="
    if [ "$count" -gt 0 ]; then
        sed 's/^/  /' "$file"
    fi
    echo ""
}

comm -23 "$core_rules" "$listed" > "$TMP_DIR/rule-not-listed"
comm -13 "$core_rules" "$enabled" > "$TMP_DIR/enabled-without-rule"
comm -13 "$core_rules" "$listed" > "$TMP_DIR/listed-without-rule"

show_section "Enabled in cores.txt but missing a libretro-super core rule" "$TMP_DIR/enabled-without-rule"
show_section "Listed/commented in cores.txt but missing a libretro-super core rule" "$TMP_DIR/listed-without-rule"
show_section "libretro-super core rules not listed in cores.txt" "$TMP_DIR/rule-not-listed"
