#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Push comfyui-a1111-proxy image to registry
#
# Usage:
#   ./scripts/push-image.sh
#   ./scripts/push-image.sh --tag 0.1.0
#   ./scripts/push-image.sh --all
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
IMAGE_TAG="${IMAGE_TAG:-latest}"
PUSH_ALL="false"

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
    --all)
      PUSH_ALL="true"
      shift
      ;;
    -h|--help)
      sed -n '1,25p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$PUSH_ALL" == "true" ]]; then
  echo "Pushing all tags for ${IMAGE_REPO}"
  docker_cmd push --all-tags "$IMAGE_REPO"
else
  echo "Pushing ${IMAGE_REPO}:${IMAGE_TAG}"
  docker_cmd push "${IMAGE_REPO}:${IMAGE_TAG}"
fi