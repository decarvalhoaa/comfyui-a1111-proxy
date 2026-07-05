#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Build comfyui-a1111-proxy image
#
# Usage:
#   ./scripts/build-image.sh
#   ./scripts/build-image.sh --tag 0.1.0
#   ./scripts/build-image.sh --repo forgejo.xcloud/homelab/comfyui-a1111-proxy --tag 0.1.0
#   ./scripts/build-image.sh --platform linux/arm64
#
# Defaults:
#   repo:     forgejo.xcloud/homelab/comfyui-a1111-proxy
#   tag:      git short SHA, or "dev" if not in a git repo
#   platform: host default
# -----------------------------------------------------------------------------

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo docker "$@"
  else
    echo "ERROR: Docker is not accessible and sudo is not available." >&2
    exit 1
  fi
}

IMAGE_REPO="${IMAGE_REPO:-forgejo.xcloud/homelab/comfyui-a1111-proxy}"
IMAGE_TAG="${IMAGE_TAG:-}"
PLATFORM="${PLATFORM:-}"
BUILD_LATEST="${BUILD_LATEST:-true}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      IMAGE_REPO="$2"
      shift 2
      ;;
    --tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --platform)
      PLATFORM="$2"
      shift 2
      ;;
    --no-latest)
      BUILD_LATEST="false"
      shift
      ;;
    -h|--help)
      sed -n '1,35p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$IMAGE_TAG" ]]; then
  if git rev-parse --short HEAD >/dev/null 2>&1; then
    IMAGE_TAG="$(git rev-parse --short HEAD)"
  else
    IMAGE_TAG="dev"
  fi
fi

BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if VCS_REF="$(git rev-parse --short HEAD 2>/dev/null | tr -d '\r\n')"; then
  :
else
  VCS_REF="unknown"
fi
VERSION="$IMAGE_TAG"

TAGS=(-t "${IMAGE_REPO}:${IMAGE_TAG}")

if [[ "$BUILD_LATEST" == "true" ]]; then
  TAGS+=(-t "${IMAGE_REPO}:latest")
fi

PLATFORM_ARGS=()
if [[ -n "$PLATFORM" ]]; then
  PLATFORM_ARGS=(--platform "$PLATFORM")
fi

echo "Building image:"
echo "  repo:      ${IMAGE_REPO}"
echo "  tag:       ${IMAGE_TAG}"
echo "  latest:    ${BUILD_LATEST}"
echo "  platform:  ${PLATFORM:-default}"
echo

if docker_cmd buildx version >/dev/null 2>&1; then
  echo "Using docker buildx build"
  docker_cmd buildx build \
    --load \
    "${PLATFORM_ARGS[@]}" \
    "${TAGS[@]}" \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    --build-arg VCS_REF="$VCS_REF" \
    --build-arg VERSION="$VERSION" \
    .
else
  echo "WARNING: docker buildx is not available; falling back to docker build." >&2

  docker_cmd build \
    "${PLATFORM_ARGS[@]}" \
    "${TAGS[@]}" \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    --build-arg VCS_REF="$VCS_REF" \
    --build-arg VERSION="$VERSION" \
    .
fi

echo
echo "Built:"
echo "  ${IMAGE_REPO}:${IMAGE_TAG}"

if [[ "$BUILD_LATEST" == "true" ]]; then
  echo "  ${IMAGE_REPO}:latest"
fi