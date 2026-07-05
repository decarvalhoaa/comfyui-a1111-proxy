#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Inspect comfyui-a1111-proxy image
#
# Usage:
#   ./scripts/inspect-image.sh
#   ./scripts/inspect-image.sh --tag 0.1.0
#   ./scripts/inspect-image.sh --image forgejo.xcloud/homelab/comfyui-a1111-proxy:0.1.0
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
IMAGE=""

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
    --image)
      IMAGE="$2"
      shift 2
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

if [[ -z "$IMAGE" ]]; then
  IMAGE="${IMAGE_REPO}:${IMAGE_TAG}"
fi

echo "Inspecting image: ${IMAGE}"
echo

docker_cmd image inspect "$IMAGE" \
  --format 'ID:           {{.Id}}
RepoTags:     {{json .RepoTags}}
Created:      {{.Created}}
Architecture: {{.Architecture}}
OS:           {{.Os}}
Size:         {{.Size}}
Labels:       {{json .Config.Labels}}
Entrypoint:   {{json .Config.Entrypoint}}
Cmd:          {{json .Config.Cmd}}
ExposedPorts: {{json .Config.ExposedPorts}}'

echo
echo "Package smoke test:"
docker_cmd run --rm -i "$IMAGE" python - <<'PY'
import fastapi
import requests
import yaml
import PIL
print("ok: python imports passed")
PY