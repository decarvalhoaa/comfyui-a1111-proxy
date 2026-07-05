# ComfyUI A1111 Proxy

Minimal **Automatic1111-compatible `txt2img` proxy** for ComfyUI.

This service exposes:

```text
POST /sdapi/v1/txt2img
```

and translates the incoming Automatic1111-style payload into a native ComfyUI workflow execution.

It is intended for tools that only support the Automatic1111 Stable Diffusion WebUI API, but where the actual image backend is ComfyUI.

The initial use case is integration with:

```text
MCPO File Generation Tool / OWUI File Export Server
```

using:

```yaml
IMAGE_SOURCE: local_sd
LOCAL_SD_URL: http://comfyui-a1111-proxy:7860
```

---

## Why this exists

Some applications expect an Automatic1111-compatible API endpoint such as:

```text
/sdapi/v1/txt2img
```

ComfyUI does not expose that API by default. ComfyUI uses a workflow-based API where clients submit a workflow JSON to:

```text
/prompt
```

This proxy bridges that gap.

It accepts a small subset of the A1111 `txt2img` request format, maps values into a ComfyUI API workflow, waits for the generated image, and returns an A1111-style response:

```json
{
  "images": ["<base64-encoded-png>"],
  "parameters": {},
  "info": "{}"
}
```

---

## Design goals

- Keep the proxy generic.
- Keep the ComfyUI workflow outside the code.
- Keep node mappings outside the code.
- Allow workflow changes without touching Python code.
- Support GitOps-style deployment.
- Support local registry publishing, for example Forgejo.
- Be small enough to audit and maintain.

The proxy reads two external files:

```text
/config/workflow.json   # e.g. current workflow: imagegen_z_image_turbo.json
/config/mapping.yaml
```

Changing the workflow should only require updating the workflow file and mapping file.

---

## Repository layout

```text
.
├── app/
│   └── main.py
├── config/
│   ├── imagegen_z_image_turbo.json
│   └── mapping.yaml
├── scripts/
│   ├── build-image.sh
│   ├── inspect-image.sh
│   ├── push-image.sh
│   └── tag-release.sh
├── docker-compose.yml
├── Dockerfile
├── README.md
└── .gitignore
```

---

## Current workflow

The included mapping is intended for a Z-Image-Turbo ComfyUI API workflow using nodes similar to:

```text
57:27  CLIPTextEncode        prompt
57:13  EmptySD3LatentImage   width / height / batch size
57:3   KSampler              seed / steps / cfg / sampler / scheduler
9      SaveImage             output
```

The workflow file is mounted into the container at:

```text
/config/imagegen_z_image_turbo.json
```

The mapping file tells the proxy where to write incoming A1111 fields inside the ComfyUI workflow.

---

## Example mapping

```yaml
comfyui:
  base_url: "http://comfyui:8188"
  timeout_seconds: 180
  poll_interval_seconds: 1
  output_timeout_seconds: 180

workflow:
  file: "/config/imagegen_z_image_turbo.json"

response:
  image_format: "png"

mappings:
  prompt:
    node: "57:27"
    path: "inputs.text"
    default: ""

  width:
    node: "57:13"
    path: "inputs.width"
    default: 1024

  height:
    node: "57:13"
    path: "inputs.height"
    default: 1024

  steps:
    node: "57:3"
    path: "inputs.steps"
    default: 8

  cfg_scale:
    node: "57:3"
    path: "inputs.cfg"
    default: 1.0

  seed:
    node: "57:3"
    path: "inputs.seed"
    default: -1
    randomize_if_negative: true

  sampler_name:
    node: "57:3"
    path: "inputs.sampler_name"
    default: "res_multistep"

  scheduler:
    node: "57:3"
    path: "inputs.scheduler"
    default: "simple"
```

---

## Exporting a ComfyUI workflow

The proxy requires a **ComfyUI API-format workflow**, not the normal visual workflow JSON.

In ComfyUI:

```text
Settings → Enable Dev mode Options
Save → API Format
```

Save the exported file under `config/`, for example:

```text
config/imagegen_z_image_turbo.json
```

Then update `config/mapping.yaml` to point to the correct node IDs and input paths.

To inspect node IDs:

```bash
jq 'to_entries[] | {id: .key, class_type: .value.class_type, inputs: .value.inputs}' config/imagegen_z_image_turbo.json
```

---

## Docker Compose for local build/test

```yaml
services:
  comfyui-a1111-proxy:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: comfyui-a1111-proxy
    restart: unless-stopped
    networks:
      - ai_net
    ports:
      - "7860:7860"
    environment:
      CONFIG_FILE: /config/mapping.yaml
    volumes:
      - ./config:/config:ro

networks:
  ai_net:
    external: true
```

The proxy must be able to reach ComfyUI using the `base_url` configured in `mapping.yaml`.

For example, if ComfyUI is attached to the same Docker network with alias `comfyui`:

```yaml
comfyui:
  base_url: "http://comfyui:8188"
```

---

## Docker Compose using a published image

After building and pushing the image to a registry, use `image:` instead of `build:`.

Example with a local Forgejo registry:

```yaml
services:
  comfyui-a1111-proxy:
    image: forgejo.xcloud/homelab/comfyui-a1111-proxy:0.1.0
    container_name: comfyui-a1111-proxy
    restart: unless-stopped
    networks:
      - ai_net
    ports:
      - "7860:7860"
    environment:
      CONFIG_FILE: /config/mapping.yaml
    volumes:
      - ./config:/config:ro

networks:
  ai_net:
    external: true
```

---

## MCPO / OWUI File Export integration

For MCPO File Generation Tool, configure the local Stable Diffusion backend like this:

```yaml
environment:
  IMAGE_SOURCE: local_sd
  LOCAL_SD_URL: http://comfyui-a1111-proxy:7860
  LOCAL_SD_WIDTH: 1024
  LOCAL_SD_HEIGHT: 1024
  LOCAL_SD_STEPS: 8
  LOCAL_SD_CFG_SCALE: 1
  LOCAL_SD_SCHEDULER: simple
  LOCAL_SD_SAMPLE: res_multistep
```

The MCPO container and proxy container must share a Docker network.

MCPO calls:

```text
POST http://comfyui-a1111-proxy:7860/sdapi/v1/txt2img
```

---

## API

### Health check

```bash
curl -s http://localhost:7860/health
```

Expected response:

```json
{
  "status": "ok"
}
```

### Generate image

```bash
curl -s http://localhost:7860/sdapi/v1/txt2img \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "a small red cube on a wooden table",
    "steps": 8,
    "width": 512,
    "height": 512,
    "cfg_scale": 1,
    "sampler_name": "res_multistep",
    "scheduler": "simple",
    "seed": -1
  }' | jq 'keys'
```

Expected keys:

```json
[
  "images",
  "info",
  "parameters"
]
```

To write the generated image to a file:

```bash
curl -s http://localhost:7860/sdapi/v1/txt2img \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"test image","steps":8,"width":512,"height":512}' \
  | jq -r '.images[0]' | base64 -d > test.png
```

---

## Supported A1111 fields

The proxy currently supports the fields needed by the MCPO File Generation Tool:

```text
prompt
negative_prompt
steps
width
height
cfg_scale
sampler_name
scheduler
seed
enable_hr
hr_upscaler
override_settings
```

Not every field is necessarily mapped. Only fields defined in `mapping.yaml` are applied to the ComfyUI workflow.

For the current Z-Image-Turbo workflow, `negative_prompt` is not mapped because the workflow uses `ConditioningZeroOut` rather than a separate negative prompt text encoder.

---

## Build image

```bash
./scripts/build-image.sh
```

Build with an explicit tag:

```bash
./scripts/build-image.sh --tag 0.1.0
```

Build for a specific platform:

```bash
./scripts/build-image.sh --platform linux/arm64 --tag 0.1.0
```

Use a different image repository:

```bash
./scripts/build-image.sh \
  --repo forgejo.xcloud/homelab/comfyui-a1111-proxy \
  --tag 0.1.0
```

By default, the build script tags both:

```text
<repo>:<tag>
<repo>:latest
```

Use `--no-latest` to skip the `latest` tag.

---

## Inspect image

```bash
./scripts/inspect-image.sh
```

Inspect a specific tag:

```bash
./scripts/inspect-image.sh --tag 0.1.0
```

Inspect a full image reference:

```bash
./scripts/inspect-image.sh \
  --image forgejo.xcloud/homelab/comfyui-a1111-proxy:0.1.0
```

---

## Push image

Push the default `latest` tag:

```bash
./scripts/push-image.sh
```

Push a specific tag:

```bash
./scripts/push-image.sh --tag 0.1.0
```

Push all local tags for the repository:

```bash
./scripts/push-image.sh --all
```

If Docker requires sudo on your host, log in to the registry with sudo as well:

```bash
sudo docker login forgejo.xcloud
```

---

## Release flow

Create a Git tag, build the matching image tag, and push both:

```bash
./scripts/tag-release.sh 0.1.0
```

This creates or uses:

```text
git tag: 0.1.0
image:   forgejo.xcloud/homelab/comfyui-a1111-proxy:0.1.0
image:   forgejo.xcloud/homelab/comfyui-a1111-proxy:latest
```

A version prefixed with `v` is also accepted:

```bash
./scripts/tag-release.sh v0.1.0
```

The Docker image tag will be normalized to:

```text
0.1.0
```

---

## Registry and mirrors

This repository may be mirrored to multiple Git hosting providers, for example:

```text
Forgejo
GitHub
Codeberg
```

The image repository is configurable through the scripts:

```bash
IMAGE_REPO=forgejo.xcloud/homelab/comfyui-a1111-proxy ./scripts/build-image.sh --tag 0.1.0
```

or:

```bash
./scripts/build-image.sh \
  --repo forgejo.xcloud/homelab/comfyui-a1111-proxy \
  --tag 0.1.0
```

For public mirrors such as GitHub or Codeberg, review the workflow JSON before publishing.

ComfyUI workflow files can expose local model names, filenames, node choices, paths, or other environment-specific details. Do not publish secrets, internal hostnames, credentials, private registry URLs, or sensitive local infrastructure details.

---

## Security notes

This proxy is intended for trusted LAN or internal Docker network use.

Do not expose it directly to the public internet without adding proper authentication, TLS, rate limits, and request validation.

The proxy can trigger GPU-intensive image generation jobs. Treat access to this service as access to your ComfyUI backend.

Recommended deployment:

```text
MCPO container → internal Docker network → comfyui-a1111-proxy → ComfyUI
```

Avoid exposing port `7860` publicly unless required for testing.

---

## Operational notes

### MCPO timeout

Some clients hardcode short request timeouts. The MCPO File Generation Tool currently uses a 30-second timeout for local Stable Diffusion requests.

For reliable generation:

- start with small image sizes;
- use low step counts;
- prefer fast workflows;
- increase MCPO timeout if you control the MCPO code.

For Z-Image-Turbo, start with:

```yaml
LOCAL_SD_WIDTH: 512
LOCAL_SD_HEIGHT: 512
LOCAL_SD_STEPS: 8
LOCAL_SD_CFG_SCALE: 1
```

Then increase resolution after the full path is validated.

### Workflow changes

When changing the ComfyUI workflow:

1. Export a new API-format workflow JSON.
2. Replace or add the file under `config/`.
3. Update `mapping.yaml`.
4. Restart the proxy container.

No Python code change should be required.

### Node ID changes

ComfyUI node IDs may change when rebuilding or exporting workflows. If the proxy returns an error such as:

```text
Mapped node does not exist in workflow
```

then the node IDs in `mapping.yaml` no longer match the workflow JSON.

Inspect the workflow again with:

```bash
jq 'to_entries[] | {id: .key, class_type: .value.class_type, inputs: .value.inputs}' config/imagegen_z_image_turbo.json
```

and update the mapping.

---

## Limitations

This is not a full Automatic1111 API implementation.

Currently implemented:

```text
POST /sdapi/v1/txt2img
GET  /health
```

Not implemented:

```text
/sdapi/v1/img2img
/sdapi/v1/options
/sdapi/v1/samplers
/sdapi/v1/sd-models
/sdapi/v1/progress
```

Additional endpoints should only be added when an actual client requires them.

---

## Development

Run locally with Docker Compose:

```bash
docker compose up --build
```

If Docker requires sudo:

```bash
sudo docker compose up --build
```

Test health:

```bash
curl -s http://localhost:7860/health
```

Test generation:

```bash
curl -s http://localhost:7860/sdapi/v1/txt2img \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"test image","steps":8,"width":512,"height":512}' \
  | jq -r '.images[0]' | base64 -d > test.png
```

View logs:

```bash
docker logs -f comfyui-a1111-proxy
```

or:

```bash
sudo docker logs -f comfyui-a1111-proxy
```

---

## License

No license has been selected yet.

Before publishing this repository publicly on GitHub or Codeberg, choose and add a `LICENSE` file.

Common choices:

- MIT for permissive reuse.
- Apache-2.0 for permissive reuse with explicit patent language.
- GPL-3.0 if derivative works should remain open source.

---

## Status

Experimental but intentionally small.

The proxy is designed for one practical integration path:

```text
A1111-style txt2img client → ComfyUI workflow backend
```

For broader A1111 compatibility, use or evaluate a dedicated compatibility layer. This project intentionally keeps the API surface narrow.
