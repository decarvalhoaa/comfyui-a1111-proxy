#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Create and push a Git release tag.
#
# This script intentionally does NOT build or push Docker images.
# Image build/push is handled by:
#
#   ./scripts/build-image.sh
#   ./scripts/inspect-image.sh
#   ./scripts/push-image.sh
#
# Usage:
#   ./scripts/tag-release.sh 0.1.0
#   ./scripts/tag-release.sh v0.1.0
#
# Behavior:
#   - Requires a clean Git working tree
#   - Creates an annotated Git tag if it does not already exist
#   - Pushes the Git tag to origin
# -----------------------------------------------------------------------------

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  echo "Example: $0 0.1.0" >&2
  exit 1
fi

VERSION="$1"
GIT_TAG="$VERSION"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a Git repository." >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: Git working tree is not clean." >&2
  echo "Commit or stash changes before creating a release tag." >&2
  exit 1
fi

if git rev-parse "$GIT_TAG" >/dev/null 2>&1; then
  echo "Git tag already exists: ${GIT_TAG}"
else
  echo "Creating Git tag: ${GIT_TAG}"
  git tag -a "$GIT_TAG" -m "Release ${GIT_TAG}"
fi

echo "Pushing Git tag: ${GIT_TAG}"
git push origin "$GIT_TAG"

echo
echo "Release tag complete:"
echo "  git tag: ${GIT_TAG}"