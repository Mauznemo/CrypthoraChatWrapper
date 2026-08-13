#!/usr/bin/env bash
# Shared release helpers, sourced by scripts/release.sh and by .github/workflows/release.yml
# so the local preview and the published release are always derived the same way.
#
# Kept compatible with bash 3.2, which is what macOS ships as /bin/bash.

VERSION_REGEX='^([0-9]+)\.([0-9]+)\.([0-9]+)(-(alpha|beta|rc)\.([0-9]+))?$'

# pubspec_version <path-to-pubspec.yaml>
# Prints the version without the `+build` suffix, e.g. `0.0.1-alpha.13`.
pubspec_version() {
    sed -n 's/^version:[[:space:]]*\([^[:space:]+]*\).*/\1/p' "$1" | head -n1
}

# version_code <version>
# Maps a version onto a monotonically increasing Android versionCode:
#
#   major * 10000000 + minor * 100000 + patch * 1000 + tier + n
#
# where tier is alpha=0, beta=250, rc=500 and a version without a suffix is 999. So
# 0.0.1-alpha.13 -> 1013, 0.0.1-beta.1 -> 1251, 0.0.1 -> 1999, 0.0.2-alpha.1 -> 2001.
# Every upgrade path stays strictly increasing, which is what Android requires.
version_code() {
    local version=$1
    if ! [[ $version =~ $VERSION_REGEX ]]; then
        echo "version_code: '$version' is not MAJOR.MINOR.PATCH[-alpha|beta|rc.N]" >&2
        return 1
    fi

    local major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}
    local channel=${BASH_REMATCH[5]:-} n=${BASH_REMATCH[6]:-0}
    local tier

    case $channel in
    alpha) tier=0 ;;
    beta) tier=250 ;;
    rc) tier=500 ;;
    *) tier=999 n=0 ;;
    esac

    # Guard the digit budget each component was given, so the result can never collide
    # with the next version up.
    if [ "$minor" -gt 99 ] || [ "$patch" -gt 99 ] || [ "$n" -gt 249 ]; then
        echo "version_code: '$version' overflows the versionCode scheme (minor/patch max 99, prerelease max 249)" >&2
        return 1
    fi

    echo $((major * 10000000 + minor * 100000 + patch * 1000 + tier + n))
}

# previous_tag <ref>
# Prints the most recent v* tag reachable from before <ref>, or nothing if there is none.
previous_tag() {
    git describe --tags --abbrev=0 --match 'v*' "$1^" 2>/dev/null || true
}

# generate_changelog <from-tag-or-empty> <to-ref>
# Prints markdown release notes built from the feat/fix/refactor commits in the range.
# Anything else (docs, chore, merge commits, ...) is left out on purpose.
generate_changelog() {
    local from=$1 to=$2
    local range=$to
    [ -n "$from" ] && range="$from..$to"

    local subject sha type text head rest
    local conventional='^(feat|fix|refactor)(\([^)]*\))?!?:[[:space:]]*(.+)$'
    local feats='' fixes='' refactors=''

    while IFS='|' read -r subject sha; do
        [ -z "$subject" ] && continue
        [[ $subject =~ $conventional ]] || continue

        type=${BASH_REMATCH[1]}
        text=${BASH_REMATCH[3]}

        # Capitalize the first letter; `${text^}` would be bash 4 only.
        head=$(printf '%s' "${text:0:1}" | tr '[:lower:]' '[:upper:]')
        rest=${text:1}

        case $type in
        feat) feats="${feats}- ${head}${rest} (${sha})"$'\n' ;;
        fix) fixes="${fixes}- ${head}${rest} (${sha})"$'\n' ;;
        refactor) refactors="${refactors}- ${head}${rest} (${sha})"$'\n' ;;
        esac
    done < <(git log --no-merges --pretty=format:'%s|%h' "$range")

    local out=''
    [ -n "$feats" ] && out="${out}### Features"$'\n'"${feats}"$'\n'
    [ -n "$fixes" ] && out="${out}### Fixes"$'\n'"${fixes}"$'\n'
    [ -n "$refactors" ] && out="${out}### Refactors"$'\n'"${refactors}"$'\n'

    if [ -z "$out" ]; then
        printf 'No user-facing changes.\n'
    else
        printf '%s' "$out"
    fi
}
