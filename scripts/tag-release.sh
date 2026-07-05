#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Create and push a git release tag, then build and push matching image tag
#
# Usage:
#   ./scripts/tag-release.sh 0.1.0
#   ./scripts/tag-release.sh v0.1.0
#
# Behavior:
#   - Requires clean git working tree
#   - Creates annotated git tag if it does not already exist
#   - Pushes the git tag
#   - Builds image with matching normalized tag
#   - Pushes image tag and latest
# -----------------------------------------------------------------------------

IMAGE_REPO="${IMAGE_REPO:-forgejo.xcloud/homelab/comfyui-a1111-proxy}"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  echo "Example: $0 0.1.0" >&2
  exit 1
fi

VERSION="$1"
GIT_TAG="$VERSION"
IMAGE_TAG="${VERSION#v}"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: git working tree is not clean." >&2
  exit 1
fi

if git rev-parse "$GIT_TAG" >/dev/null 2>&1; then
  echo "Git tag already exists: ${GIT_TAG}"
else
  echo "Creating git tag: ${GIT_TAG}"
  git tag -a "$GIT_TAG" -m "Release ${GIT_TAG}"
fi

echo "Pushing git tag: ${GIT_TAG}"
git push origin "$GIT_TAG"

echo "Building release image: ${IMAGE_REPO}:${IMAGE_TAG}"
./scripts/build-image.sh --repo "$IMAGE_REPO" --tag "$IMAGE_TAG"

echo "Pushing release image tags"
./scripts/push-image.sh --repo "$IMAGE_REPO" --tag "$IMAGE_TAG"
./scripts/push-image.sh --repo "$IMAGE_REPO" --tag latest

echo
echo "Release complete:"
echo "  git tag: ${GIT_TAG}"
echo "  image:   ${IMAGE_REPO}:${IMAGE_TAG}"
echo "  image:   ${IMAGE_REPO}:latest"