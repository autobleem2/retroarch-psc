#!/bin/bash
# Report upstream release tags for enabled cores and local core-fix pins.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-libretro-cores-psc}"
CORES_FILE="${CORES_FILE:-cores.txt}"
CORE_REFS_FILE="${CORE_REFS_FILE:-}"
LIBRETRO_SUPER_DIR="${LIBRETRO_SUPER_DIR:-}"
FORMAT="table"
ONLY_CORES=()

usage() {
    cat <<'EOF'
Usage: scripts/check-core-updates.sh [options]

Options:
  --core NAME              Check one core. Can be used more than once.
  --cores-file PATH        Core list file. Default: cores.txt
  --core-refs PATH         Core ref policy file. Default: scripts/core-refs.txt
  --image NAME             Docker image with libretro-super. Default: libretro-cores-psc
  --libretro-super-dir DIR Use a local libretro-super checkout instead of Docker.
  --format table|tsv       Output format. Default: table
  -h, --help               Show this help.

Environment:
  IMAGE_NAME               Docker image name.
  CORES_FILE               Core list path.
  CORE_REFS_FILE           Core ref policy path.
  LIBRETRO_SUPER_DIR       Local libretro-super checkout.

Status:
  pinned-current           Core fix pins the latest upstream version tag.
  pinned-update            Core fix pins an older upstream version tag.
  pinned-unmatched         Core fix pin exists, but it is not comparable to the latest tag.
  built-tag-current        Built commit exactly matches the latest upstream version tag.
  built-tag-update         Built commit matches an older upstream version tag.
  unpinned-tags            Upstream has tags, but this build follows a branch/commit.
  no-version-tags          Upstream has tags, but none look version-like.
  no-tags                  Upstream repo has no tags.
  no-url                   No git URL found in libretro-super rules.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --core)
            [ "$#" -ge 2 ] || { echo "Error: --core needs a value" >&2; exit 1; }
            ONLY_CORES+=("$2")
            shift 2
            ;;
        --cores-file)
            [ "$#" -ge 2 ] || { echo "Error: --cores-file needs a value" >&2; exit 1; }
            CORES_FILE="$2"
            shift 2
            ;;
        --core-refs)
            [ "$#" -ge 2 ] || { echo "Error: --core-refs needs a value" >&2; exit 1; }
            CORE_REFS_FILE="$2"
            shift 2
            ;;
        --image)
            [ "$#" -ge 2 ] || { echo "Error: --image needs a value" >&2; exit 1; }
            IMAGE_NAME="$2"
            shift 2
            ;;
        --libretro-super-dir)
            [ "$#" -ge 2 ] || { echo "Error: --libretro-super-dir needs a value" >&2; exit 1; }
            LIBRETRO_SUPER_DIR="$2"
            shift 2
            ;;
        --format)
            [ "$#" -ge 2 ] || { echo "Error: --format needs a value" >&2; exit 1; }
            FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ "$FORMAT" != "table" ] && [ "$FORMAT" != "tsv" ]; then
    echo "Error: --format must be table or tsv" >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORES_FILE_ABS="$CORES_FILE"
if [[ "$CORES_FILE_ABS" != /* ]]; then
    CORES_FILE_ABS="$ROOT_DIR/$CORES_FILE_ABS"
fi
if [ -z "$CORE_REFS_FILE" ]; then
    CORE_REFS_FILE="$ROOT_DIR/scripts/core-refs.txt"
elif [[ "$CORE_REFS_FILE" != /* ]]; then
    CORE_REFS_FILE="$ROOT_DIR/$CORE_REFS_FILE"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CORE_LIST="$TMP_DIR/cores.list"
RULES_FILE="$TMP_DIR/rules.tsv"
RESULTS_FILE="$TMP_DIR/results.tsv"
TAG_CACHE_DIR="$TMP_DIR/tags"
mkdir -p "$TAG_CACHE_DIR"

if [ "${#ONLY_CORES[@]}" -gt 0 ]; then
    printf '%s\n' "${ONLY_CORES[@]}" | LC_ALL=C sort -u > "$CORE_LIST"
else
    if [ ! -f "$CORES_FILE_ABS" ]; then
        echo "Error: cores file not found: $CORES_FILE_ABS" >&2
        exit 1
    fi
    sed 's/#.*//' "$CORES_FILE_ABS" | tr -d ' \t' | grep -v '^$' | LC_ALL=C sort -u > "$CORE_LIST"
fi

resolve_rules_with_local_checkout() {
    local libretro_super_dir="$1"
    (
        cd "$libretro_super_dir"
        # shellcheck disable=SC1091
        . rules.d/core-rules.sh
        while IFS= read -r core; do
            eval "url=\${libretro_${core}_git_url:-}"
            eval "dir=\${libretro_${core}_dir:-libretro-${core}}"
            eval "fetch_rule=\${libretro_${core}_fetch_rule:-git}"
            printf '%s\t%s\t%s\t%s\n' "$core" "$url" "$dir" "$fetch_rule"
        done < "$CORE_LIST"
    )
}

resolve_rules_with_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Error: docker is required unless --libretro-super-dir is set" >&2
        exit 1
    fi

    local docker_err="$TMP_DIR/docker-rules.err"

    if ! docker run --rm \
        -v "$CORE_LIST":/tmp/cores.list:ro \
        "$IMAGE_NAME" bash -lc '
            cd /build/libretro-super
            . rules.d/core-rules.sh
            while IFS= read -r core; do
                eval "url=\${libretro_${core}_git_url:-}"
                eval "dir=\${libretro_${core}_dir:-libretro-${core}}"
                eval "fetch_rule=\${libretro_${core}_fetch_rule:-git}"
                printf "%s\t%s\t%s\t%s\n" "$core" "$url" "$dir" "$fetch_rule"
            done < /tmp/cores.list
        ' 2>"$docker_err"; then
        grep -v '^mesg: ttyname failed' "$docker_err" >&2 || true
        exit 1
    fi

    grep -v '^mesg: ttyname failed' "$docker_err" >&2 || true
}

if [ -n "$LIBRETRO_SUPER_DIR" ]; then
    if [ ! -f "$LIBRETRO_SUPER_DIR/rules.d/core-rules.sh" ]; then
        echo "Error: libretro-super rules not found in $LIBRETRO_SUPER_DIR" >&2
        exit 1
    fi
    resolve_rules_with_local_checkout "$LIBRETRO_SUPER_DIR" > "$RULES_FILE"
else
    resolve_rules_with_docker > "$RULES_FILE"
fi

ref_config_for_core() {
    local core="$1"
    local policy="latest-tag"
    local ref="-"
    local fallback="branch"
    local line

    if [ -f "$CORE_REFS_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%%#*}"
            read -r parsed_core parsed_policy parsed_ref parsed_fallback _ <<< "$line"
            [ -n "${parsed_core:-}" ] && [ -n "${parsed_policy:-}" ] || continue

            if [ "$parsed_core" = "*" ] || [ "$parsed_core" = "$core" ]; then
                policy="$parsed_policy"
                ref="${parsed_ref:--}"
                fallback="${parsed_fallback:-branch}"
            fi
        done < "$CORE_REFS_FILE"
    fi

    printf '%s\t%s\t%s\n' "$policy" "$ref" "$fallback"
}

manifest_pin_for_core() {
    local core="$1"
    local config
    local policy
    local ref

    config="$(ref_config_for_core "$core")"
    policy="$(printf '%s' "$config" | awk -F '\t' '{print $1}')"
    ref="$(printf '%s' "$config" | awk -F '\t' '{print $2}')"

    if [ "$policy" = "pinned" ] && [ "$ref" != "-" ]; then
        printf '%s\n' "$ref"
    fi
}

manifest_note_for_core() {
    local core="$1"
    local config
    local policy
    local ref
    local fallback

    config="$(ref_config_for_core "$core")"
    policy="$(printf '%s' "$config" | awk -F '\t' '{print $1}')"
    ref="$(printf '%s' "$config" | awk -F '\t' '{print $2}')"
    fallback="$(printf '%s' "$config" | awk -F '\t' '{print $3}')"

    if [ "$ref" = "-" ]; then
        printf 'policy=%s fallback=%s' "$policy" "$fallback"
    else
        printf 'policy=%s ref=%s fallback=%s' "$policy" "$ref" "$fallback"
    fi
}

metadata_value_for_core() {
    local core="$1"
    local key="$2"
    local commit_file="$ROOT_DIR/build_metadata/commits/${core}_libretro.so.commit"

    [ -f "$commit_file" ] || return 0
    awk -F= -v key="$key" '$1 == key {
            print $2
            exit
        }
    ' "$commit_file"
}

commit_for_core() {
    local core="$1"
    local commit_file="$ROOT_DIR/build_metadata/commits/${core}_libretro.so.commit"

    [ -f "$commit_file" ] || return 0
    metadata_value_for_core "$core" commit
}

cache_key_for_url() {
    printf '%s' "$1" | sed 's#[^A-Za-z0-9._-]#_#g'
}

tags_for_url() {
    local url="$1"
    local key="$TAG_CACHE_DIR/$(cache_key_for_url "$url").tags"

    if [ ! -f "$key" ]; then
        if ! git ls-remote --tags "$url" > "$key.raw" 2>"$key.err"; then
            : > "$key"
        else
            awk '
                /refs\/tags\// {
                    tag=$2
                    sub(/^refs\/tags\//, "", tag)
                    sub(/\^\{\}$/, "", tag)
                    print tag
                }
            ' "$key.raw" | LC_ALL=C sort -u > "$key"
        fi
    fi

    cat "$key"
}

latest_version_tag() {
    local tags="$1"

    printf '%s\n' "$tags" \
        | grep -E '[0-9]' \
        | sort -V \
        | tail -1 || true
}

tag_for_commit() {
    local url="$1"
    local commit="$2"
    local key="$TAG_CACHE_DIR/$(cache_key_for_url "$url").commit-tags"

    [ -n "$commit" ] || return 0

    if [ ! -f "$key" ]; then
        git ls-remote --tags "$url" 2>/dev/null \
            | awk '
                /refs\/tags\// {
                    tag=$2
                    sub(/^refs\/tags\//, "", tag)
                    sub(/\^\{\}$/, "", tag)
                    print $1 "\t" tag
                }
            ' \
            | LC_ALL=C sort -u > "$key" || : > "$key"
    fi

    awk -v commit="$commit" '$1 == commit { print $2 }' "$key" | sort -V | tail -1
}

compare_pin_to_latest() {
    local pin="$1"
    local latest="$2"

    if [ -z "$pin" ] || [ -z "$latest" ]; then
        return 2
    fi

    if [ "$pin" = "$latest" ]; then
        return 0
    fi

    local newest
    newest=$(printf '%s\n%s\n' "$pin" "$latest" | sort -V | tail -1)
    [ "$newest" = "$latest" ] && return 1
    return 2
}

{
    while IFS=$'\t' read -r core url source_dir fetch_rule; do
        pin="$(manifest_pin_for_core "$core")"
        commit="$(commit_for_core "$core")"
        metadata_ref="$(metadata_value_for_core "$core" ref)"
        metadata_ref_source="$(metadata_value_for_core "$core" ref_source)"
        latest=""
        current_tag=""
        status=""
        note="$(manifest_note_for_core "$core")"

        if [ -z "$url" ]; then
            status="no-url"
            note="$note fetch_rule=${fetch_rule:-unknown}"
        else
            tags="$(tags_for_url "$url")"
            if [ -z "$tags" ]; then
                status="no-tags"
                [ -n "$metadata_ref" ] && current_tag="$metadata_ref"
            else
                latest="$(latest_version_tag "$tags")"
                if [ -z "$latest" ]; then
                    status="no-version-tags"
                    if [ -n "$pin" ]; then
                        current_tag="$pin"
                    elif [ -n "$metadata_ref" ] && [ "$metadata_ref" != "branch" ]; then
                        current_tag="$metadata_ref"
                    fi
                elif [ -n "$pin" ]; then
                    pin_cmp=2
                    if compare_pin_to_latest "$pin" "$latest"; then
                        pin_cmp=0
                    else
                        pin_cmp=$?
                    fi
                    case "$pin_cmp" in
                        0) status="pinned-current" ;;
                        1) status="pinned-update" ;;
                        *) status="pinned-unmatched" ;;
                    esac
                    current_tag="$pin"
                else
                    if [ "$metadata_ref_source" = "latest-tag" ] && [ -n "$metadata_ref" ]; then
                        current_tag="$metadata_ref"
                    else
                        current_tag="$(tag_for_commit "$url" "$commit")"
                    fi
                    if [ -n "$current_tag" ]; then
                        if [ "$current_tag" = "$latest" ]; then
                            status="built-tag-current"
                        else
                            status="built-tag-update"
                        fi
                    else
                        status="unpinned-tags"
                    fi
                fi
            fi
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$status" "$core" "${current_tag:-}" "${latest:-}" "${commit:-}" "${url:-}" "$note"
    done < "$RULES_FILE"
} > "$RESULTS_FILE"

if [ "$FORMAT" = "tsv" ]; then
    printf 'status\tcore\tcurrent_tag\tlatest_tag\tbuilt_commit\turl\tnote\n'
    cat "$RESULTS_FILE"
else
    printf '%-18s %-28s %-18s %-18s %s\n' "STATUS" "CORE" "CURRENT" "LATEST" "URL"
    printf '%-18s %-28s %-18s %-18s %s\n' "------" "----" "-------" "------" "---"
    awk -F '\t' '{
        current = ($3 == "" ? "-" : $3)
        latest = ($4 == "" ? "-" : $4)
        printf "%-18s %-28s %-18s %-18s %s\n", $1, $2, current, latest, $6
    }' "$RESULTS_FILE"
fi
