#!/bin/bash
# Build a single libretro core for PSC.
set -e

CORE_NAME="${1:-}"
if [ -z "$CORE_NAME" ]; then
    echo "Usage: $0 <core_name>"
    echo "Example: $0 snes9x"
    exit 1
fi

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CORE_FIXES_DIR="${CORE_FIXES_DIR:-$SCRIPT_DIR/core-fixes}"
CORE_REFS_FILE="${CORE_REFS_FILE:-$SCRIPT_DIR/core-refs.txt}"

# Use JOBS from environment or default to 4.
export JOBS="${JOBS:-4}"
CORE_REF_POLICY="branch"
CORE_REF_VALUE=""
CORE_REF_FALLBACK="fail"
CORE_TAG_REF_USED=""
CORE_TAG_SOURCE="branch"

load_core_ref_config() {
    local line
    local core
    local policy
    local ref
    local fallback

    [ -f "$CORE_REFS_FILE" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        read -r core policy ref fallback _ <<< "$line"
        [ -n "${core:-}" ] && [ -n "${policy:-}" ] || continue
        ref="${ref:--}"
        fallback="${fallback:-branch}"

        if [ "$core" = "*" ] || [ "$core" = "$CORE_NAME" ]; then
            CORE_REF_POLICY="$policy"
            CORE_REF_VALUE="$ref"
            [ "$CORE_REF_VALUE" = "-" ] && CORE_REF_VALUE=""
            CORE_REF_FALLBACK="$fallback"
        fi
    done < "$CORE_REFS_FILE"

    # Backward-compatible escape hatches for existing command lines.
    if [ -n "${CORE_TAG_POLICY:-}" ]; then
        case "$CORE_TAG_POLICY" in
            latest) CORE_REF_POLICY="latest-tag" ;;
            branch) CORE_REF_POLICY="branch" ;;
            *) CORE_REF_POLICY="$CORE_TAG_POLICY" ;;
        esac
    fi
    if [ -n "${CORE_TAG_FALLBACK:-}" ]; then
        if [ "$CORE_TAG_FALLBACK" = "1" ]; then
            CORE_REF_FALLBACK="branch"
        else
            CORE_REF_FALLBACK="fail"
        fi
    fi
}

load_core_ref_config

cd /build/libretro-super

SO_OUT="/build/output/${CORE_NAME}_libretro.so"
METADATA_OUT="${BUILD_METADATA_DIR:-/build/metadata}"
if [ ! -d "$METADATA_OUT" ]; then
    METADATA_OUT="/build/output/.metadata"
fi
COMMIT_OUT="${METADATA_OUT}/commits/${CORE_NAME}_libretro.so.commit"
mkdir -p "$METADATA_OUT"
mkdir -p "$(dirname "$COMMIT_OUT")"
rm -f "$SO_OUT" "$COMMIT_OUT" "${SO_OUT}.commit"

core_source_dir() {
    RESOLVED_DIR=$(
        cd /build/libretro-super 2>/dev/null || exit
        # shellcheck disable=SC1091
        . rules.d/core-rules.sh 2>/dev/null
        eval "echo \${libretro_${CORE_NAME}_dir:-libretro-${CORE_NAME}}"
    )
    echo "/build/libretro-super/$RESOLVED_DIR"
}

latest_version_tag_for_url() {
    git ls-remote --tags --refs "$1" 'refs/tags/*' \
        | awk -F/ '{print $NF}' \
        | grep -E '[0-9]' \
        | sort -V \
        | tail -1 || true
}

latest_version_tag() {
    latest_version_tag_for_url origin
}

core_ref_override() {
    local env_prefix
    local env_name

    if [ -n "${CORE_REF:-}" ]; then
        printf '%s' "$CORE_REF"
        return 0
    fi

    env_prefix=$(printf '%s' "$CORE_NAME" | tr '[:lower:]-' '[:upper:]_')
    env_name="${env_prefix}_REF"
    if printf '%s' "$env_name" | grep -Eq '^[A-Z_][A-Z0-9_]*$'; then
        printf '%s' "${!env_name:-}"
    fi
}

checkout_core_ref() {
    local src_dir
    local ref

    CORE_TAG_REF_USED=""
    CORE_TAG_SOURCE="branch"
    [ "$CORE_REF_POLICY" != "branch" ] || return 0

    src_dir="$(core_source_dir)"
    [ -d "$src_dir/.git" ] || return 0

    ref="$(core_ref_override)"
    if [ -n "$ref" ]; then
        echo "=== Using ${CORE_NAME} ref override: $ref ==="
        CORE_TAG_SOURCE="override"
    elif [ "$CORE_REF_POLICY" = "pinned" ]; then
        ref="$CORE_REF_VALUE"
        if [ -z "$ref" ]; then
            echo "Error: $CORE_NAME has pinned policy but no ref in $CORE_REFS_FILE" >&2
            exit 1
        fi
        echo "=== Using pinned ${CORE_NAME} ref: $ref ==="
        CORE_TAG_SOURCE="pinned"
    elif [ "$CORE_REF_POLICY" = "latest-tag" ]; then
        ref="$(cd "$src_dir" && latest_version_tag)"
        if [ -z "$ref" ]; then
            echo "=== No version tag found for $CORE_NAME; keeping fetched branch ==="
            return 0
        fi
        echo "=== Using latest ${CORE_NAME} tag: $ref ==="
        CORE_TAG_SOURCE="latest-tag"
    else
        echo "Error: unsupported policy for $CORE_NAME in $CORE_REFS_FILE: $CORE_REF_POLICY" >&2
        exit 1
    fi

    cd "$src_dir"
    git fetch --depth=1 origin "refs/tags/$ref:refs/tags/$ref" 2>/dev/null || true
    git checkout -q "$ref"
    git submodule update --init --recursive 2>/dev/null || true
    CORE_TAG_REF_USED="$ref"
    cd /build/libretro-super
}

fetch_core() {
    ./libretro-fetch.sh "$CORE_NAME"
    checkout_core_ref

    # Initialize submodules recursively (fixes tic80, scummvm, etc.).
    CORE_DIR=$(find libretro-* -maxdepth 0 -type d -name "*${CORE_NAME}*" 2>/dev/null | head -1)
    if [ -d "$CORE_DIR" ]; then
        echo "=== Initializing submodules in $CORE_DIR ==="
        cd "$CORE_DIR"
        git submodule update --init --recursive 2>/dev/null || true
        cd /build/libretro-super
    fi
}

patch_core() {
    :
}

configure_core_flags() {
    :
}

build_core() {
    ./libretro-build.sh "$CORE_NAME" || true

    # Fix case-mismatched output filenames (e.g. FreeIntv_libretro.so -> freeintv_libretro.so).
    EXPECTED_FILE="dist/unix/${CORE_NAME}_libretro.so"
    if [ ! -f "$EXPECTED_FILE" ]; then
        ACTUAL_FILE=$(find dist/unix -maxdepth 1 -iname "${CORE_NAME}_libretro.so" 2>/dev/null | head -1)

        if [ -z "$ACTUAL_FILE" ] || [ ! -f "$ACTUAL_FILE" ]; then
            ACTUAL_FILE=$(find libretro-* -name "*_libretro.so" -iname "${CORE_NAME}_libretro.so" 2>/dev/null | head -1)
        fi

        if [ -n "$ACTUAL_FILE" ] && [ -f "$ACTUAL_FILE" ]; then
            echo "=== Fixing filename case: $(basename "$ACTUAL_FILE") -> ${CORE_NAME}_libretro.so ==="
            cp "$ACTUAL_FILE" "$EXPECTED_FILE"
        fi
    fi

    if [ -f "$EXPECTED_FILE" ]; then
        cp "$EXPECTED_FILE" /build/output/
    fi
}

if [ -f "$CORE_FIXES_DIR/$CORE_NAME.sh" ]; then
    # shellcheck disable=SC1090
    . "$CORE_FIXES_DIR/$CORE_NAME.sh"
fi

# Fix broken Bitbucket submodule URLs for ecwolf (all three deps moved to github.com/ECWolfEngine).
if [ "$CORE_NAME" = "ecwolf" ]; then
    git config --global url."https://github.com/ECWolfEngine/sdl".insteadOf "https://bitbucket.org/ecwolf/sdl"
    git config --global url."https://github.com/ECWolfEngine/sdl_mixer-for-ecwolf".insteadOf "https://bitbucket.org/ecwolf/sdl_mixer-for-ecwolf"
    git config --global url."https://github.com/ECWolfEngine/sdl_net".insteadOf "https://bitbucket.org/ecwolf/sdl_net"
fi

echo "=== Fetching $CORE_NAME ==="
fetch_core

patch_core

echo "=== Building $CORE_NAME (JOBS=$JOBS) ==="
export CFLAGS="$PSC_CFLAGS"
export CXXFLAGS="$PSC_CFLAGS"
export LDFLAGS="$PSC_LDFLAGS"
configure_core_flags

build_core

if [ ! -f "$SO_OUT" ] && [ -n "${CORE_TAG_REF_USED:-}" ] && [ "$CORE_REF_FALLBACK" = "branch" ]; then
    echo "=== Tagged build did not produce ${CORE_NAME}_libretro.so; retrying fetched branch ==="
    rm -rf "$(core_source_dir)"
    rm -f "$SO_OUT"
    CORE_REF_POLICY=branch
    CORE_TAG_REF_USED=""
    CORE_TAG_SOURCE="branch-fallback"
    fetch_core
    CORE_TAG_SOURCE="branch-fallback"
    patch_core
    configure_core_flags
    build_core
fi

echo "=== Copying output ==="

if [ ! -f "$SO_OUT" ]; then
    echo "Error: ${CORE_NAME}_libretro.so was not produced" >&2
    exit 1
fi

echo "=== Stripping binary ==="
arm-linux-gnueabihf-strip -v "$SO_OUT"

SRC_DIR="$(core_source_dir)"
if [ -d "$SRC_DIR/.git" ]; then
    COMMIT=$(cd "$SRC_DIR" && git rev-parse HEAD 2>/dev/null)
    URL=$(cd "$SRC_DIR" && git config --get remote.origin.url 2>/dev/null)
    LIBRETRO_SUPER_COMMIT=$(cd /build/libretro-super && git rev-parse HEAD 2>/dev/null)
    if [ -n "$COMMIT" ]; then
        echo "=== Recording source commit: $COMMIT ==="
        {
            echo "core=$CORE_NAME"
            echo "commit=$COMMIT"
            echo "url=$URL"
            echo "libretro_super_commit=$LIBRETRO_SUPER_COMMIT"
            echo "ref=${CORE_TAG_REF_USED:-branch}"
            echo "ref_source=$CORE_TAG_SOURCE"
            echo "build_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } > "$COMMIT_OUT"
    else
        echo "Warning: could not determine commit for $CORE_NAME (src=$SRC_DIR)" >&2
    fi
else
    echo "Warning: source dir $SRC_DIR missing or not a git repo for $CORE_NAME" >&2
fi

echo "=== Done: $CORE_NAME ==="
ls -lh "$SO_OUT" "$COMMIT_OUT" 2>/dev/null || true
