#!/usr/bin/env bash
# Cuts a release: checks that the version in pubspec.yaml was bumped, then tags and pushes.
# GitHub Actions (.github/workflows/release.yml) does the rest -- build, changelog, upload.
#
# Usage: ./scripts/release.sh [--dry-run] [-y]
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/release-lib.sh
. "$REPO_ROOT/scripts/release-lib.sh"

MAIN_BRANCH=main
DRY_RUN=false
ASSUME_YES=false

for arg in "$@"; do
    case $arg in
    --dry-run) DRY_RUN=true ;;
    -y | --yes) ASSUME_YES=true ;;
    -h | --help)
        sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "unknown argument: $arg" >&2
        exit 2
        ;;
    esac
done

die() {
    echo "" >&2
    echo "  error: $1" >&2
    [ $# -gt 1 ] && echo "  $2" >&2
    echo "" >&2
    exit 1
}

cd "$REPO_ROOT"

# --- checks -----------------------------------------------------------------

branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = "$MAIN_BRANCH" ] ||
    die "on branch '$branch', releases are cut from '$MAIN_BRANCH'." "Run: git switch $MAIN_BRANCH"

[ -z "$(git status --porcelain)" ] ||
    die "working tree is dirty." "Commit or stash your changes first."

echo "Fetching origin..."
git fetch --quiet origin "$MAIN_BRANCH" --tags

local_head=$(git rev-parse HEAD)
remote_head=$(git rev-parse "origin/$MAIN_BRANCH")
if [ "$local_head" != "$remote_head" ]; then
    if git merge-base --is-ancestor "$remote_head" "$local_head"; then
        die "you have commits that are not pushed yet." "Run: git push"
    else
        die "your branch is behind origin/$MAIN_BRANCH." "Run: git pull"
    fi
fi

VERSION=$(pubspec_version pubspec.yaml)
[ -n "$VERSION" ] || die "could not read 'version:' from pubspec.yaml."

[[ $VERSION =~ $VERSION_REGEX ]] ||
    die "version '$VERSION' in pubspec.yaml is not MAJOR.MINOR.PATCH[-alpha|beta|rc.N]."

TAG="v$VERSION"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null ||
    [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
    die "version in pubspec.yaml is still $VERSION, which is already released." \
        "Bump 'version:' in pubspec.yaml, commit and push, then run this again."
fi

# --- preview ----------------------------------------------------------------

PREV_TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
CODE=$(version_code "$VERSION")
NOTES=$(generate_changelog "$PREV_TAG" HEAD)

echo ""
echo "  tag          $TAG"
echo "  versionCode  $CODE"
echo "  since        ${PREV_TAG:-<start of history>}"
echo "  commit       $(git log -1 --pretty='%h %s')"
echo ""
echo "----- release notes -----"
echo "$NOTES"
echo "-------------------------"
echo ""

if [ "$NOTES" = "No user-facing changes." ]; then
    echo "  note: no feat/fix/refactor commits since ${PREV_TAG:-the start}, the notes will be empty."
    echo ""
fi

if [ "$DRY_RUN" = true ]; then
    echo "Dry run, nothing was tagged or pushed."
    exit 0
fi

if [ "$ASSUME_YES" != true ]; then
    printf "Tag and push %s? [y/N] " "$TAG"
    read -r reply
    case $reply in
    y | Y | yes) ;;
    *)
        echo "Aborted."
        exit 1
        ;;
    esac
fi

# --- go ---------------------------------------------------------------------

git tag -a "$TAG" -m "$TAG"
git push origin "$TAG"

slug=$(git remote get-url origin | sed -E 's#(git@github\.com:|https://github\.com/)##; s#\.git$##')

echo ""
echo "Pushed $TAG. The build is running:"
echo "  https://github.com/$slug/actions/workflows/release.yml"
echo "It will publish here when done:"
echo "  https://github.com/$slug/releases/tag/$TAG"
