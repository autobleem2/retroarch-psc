#!/bin/bash
# Generate GitHub-ready release notes for a packaged core bundle.
set -euo pipefail

if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <release-name> <release-root> <version-file> <commits-file> <output-file>" >&2
    exit 1
fi

RELEASE_NAME="$1"
RELEASE_ROOT="$2"
VERSION_FILE="$3"
COMMITS_FILE="$4"
OUTPUT_FILE="$5"

if [ ! -d "$RELEASE_ROOT" ]; then
    echo "Error: release root not found: $RELEASE_ROOT" >&2
    exit 1
fi

if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: version file not found: $VERSION_FILE" >&2
    exit 1
fi

if [ ! -f "$COMMITS_FILE" ]; then
    echo "Error: commits file not found: $COMMITS_FILE" >&2
    exit 1
fi

# shellcheck disable=SC1090
. "$VERSION_FILE"

{
    printf '# libretro-cores-psc Release Notes\n\n'
    printf -- '- Release artifact: %s.tar.gz\n' "$RELEASE_NAME"
    printf -- '- libretro-super commit: %s\n' "${libretro_super_commit_full:-${libretro_super_commit:-unknown}}"
    printf -- '- libretro-super commit date: %s\n' "${libretro_super_date:-unknown}"
    printf -- '- Build date (UTC): %s\n' "${build_date:-unknown}"
    printf -- '- Toolchain: %s\n' "${toolchain:-unknown}"
    printf -- '- Target: %s\n' "${target:-unknown}"
    printf '\n## Included Files\n'
    printf '```\n'
    (
        cd "$RELEASE_ROOT"
        find dist/cores -maxdepth 1 -type f -name '*.so' | LC_ALL=C sort | sed 's|^dist/cores/||'
    )
    printf '```\n\n'
    printf '## Core Source Commits\n'
    printf '```\n'
    cat "$COMMITS_FILE"
    printf '```\n'
} > "$OUTPUT_FILE"
