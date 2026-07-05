import base64
import copy
import json
import os
import random
import time
from io import BytesIO
from typing import Any, Dict

import requests
import yaml
from fastapi import FastAPI, HTTPException
from PIL import Image
from pydantic import BaseModel, Field


app = FastAPI(title="ComfyUI A1111 txt2img Proxy")


class Txt2ImgRequest(BaseModel):
    prompt: str = ""
    negative_prompt: str | None = None
    steps: int | None = None
    width: int | None = None
    height: int | None = None
    cfg_scale: float | None = None
    sampler_name: str | None = None
    scheduler: str | None = None
    seed: int | None = None
    enable_hr: bool | None = None
    hr_upscaler: str | None = None
    override_settings: Dict[str, Any] | None = Field(default_factory=dict)


def load_config() -> Dict[str, Any]:
    config_file = os.getenv("CONFIG_FILE", "/config/mapping.yaml")
    with open(config_file, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def load_workflow(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def set_by_path(obj: Dict[str, Any], dotted_path: str, value: Any) -> None:
    parts = dotted_path.split(".")
    current = obj

    for part in parts[:-1]:
        if part not in current:
            raise KeyError(f"Path does not exist: {dotted_path}")
        current = current[part]

    current[parts[-1]] = value


def normalize_sampler(value: str | None) -> str | None:
    if value is None:
        return None

    mapping = {
        "Euler a": "euler_ancestral",
        "Euler": "euler",
        "DPM++ 2M": "dpmpp_2m",
        "DPM++ 2M Karras": "dpmpp_2m",
    }

    return mapping.get(value, value)


def normalize_scheduler(value: str | None) -> str | None:
    if value is None:
        return None

    mapping = {
        "Karras": "karras",
        "Normal": "normal",
        "Simple": "simple",
        "Exponential": "exponential",
    }

    return mapping.get(value, value)


def value_from_request(req: Txt2ImgRequest, field_name: str, rule: Dict[str, Any]) -> Any:
    value = getattr(req, field_name, None)

    if value is None:
        value = rule.get("default")

    if field_name == "sampler_name":
        value = normalize_sampler(value)

    if field_name == "scheduler":
        value = normalize_scheduler(value)

    if field_name == "seed":
        if value is None:
            value = -1
        if rule.get("randomize_if_negative", False) and int(value) < 0:
            value = random.randint(0, 2**31 - 1)

    return value


def apply_mapping(workflow: Dict[str, Any], req: Txt2ImgRequest, mapping: Dict[str, Any]) -> Dict[str, Any]:
    patched = copy.deepcopy(workflow)

    for field_name, rule in mapping.items():
        node_id = str(rule["node"])
        path = rule["path"]

        if node_id not in patched:
            raise KeyError(f"Mapped node does not exist in workflow: {node_id}")

        value = value_from_request(req, field_name, rule)

        if value is None and "default" not in rule:
            continue

        set_by_path(patched[node_id], path, value)

    return patched


def submit_prompt(comfyui_url: str, workflow: Dict[str, Any], timeout: int) -> str:
    response = requests.post(
        f"{comfyui_url}/prompt",
        json={"prompt": workflow},
        timeout=timeout,
    )
    response.raise_for_status()

    data = response.json()
    prompt_id = data.get("prompt_id")

    if not prompt_id:
        raise RuntimeError(f"ComfyUI did not return prompt_id: {data}")

    return prompt_id


def wait_for_history(comfyui_url: str, prompt_id: str, timeout: int, poll_interval: float) -> Dict[str, Any]:
    deadline = time.time() + timeout

    while time.time() < deadline:
        response = requests.get(f"{comfyui_url}/history/{prompt_id}", timeout=30)
        response.raise_for_status()

        history = response.json()

        if prompt_id in history:
            return history[prompt_id]

        time.sleep(poll_interval)

    raise TimeoutError(f"Timed out waiting for ComfyUI prompt_id={prompt_id}")


def extract_first_image(history_item: Dict[str, Any]) -> Dict[str, str]:
    outputs = history_item.get("outputs", {})

    for output in outputs.values():
        images = output.get("images", [])
        if images:
            return images[0]

    raise RuntimeError("No image found in ComfyUI history output")


def fetch_image(comfyui_url: str, image_meta: Dict[str, str], timeout: int) -> bytes:
    params = {
        "filename": image_meta["filename"],
        "subfolder": image_meta.get("subfolder", ""),
        "type": image_meta.get("type", "output"),
    }

    response = requests.get(f"{comfyui_url}/view", params=params, timeout=timeout)
    response.raise_for_status()

    return response.content


def encode_image_base64(image_bytes: bytes, image_format: str) -> str:
    if image_format.lower() == "raw":
        return base64.b64encode(image_bytes).decode("utf-8")

    image = Image.open(BytesIO(image_bytes))
    buffer = BytesIO()
    image.save(buffer, format=image_format.upper())

    return base64.b64encode(buffer.getvalue()).decode("utf-8")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/sdapi/v1/txt2img")
def txt2img(req: Txt2ImgRequest):
    config = load_config()

    comfyui_url = config["comfyui"]["base_url"].rstrip("/")
    request_timeout = int(config["comfyui"].get("timeout_seconds", 180))
    output_timeout = int(config["comfyui"].get("output_timeout_seconds", 180))
    poll_interval = float(config["comfyui"].get("poll_interval_seconds", 1))

    workflow_file = config["workflow"]["file"]
    image_format = config.get("response", {}).get("image_format", "png")

    try:
        workflow = load_workflow(workflow_file)
        patched_workflow = apply_mapping(workflow, req, config["mappings"])

        prompt_id = submit_prompt(comfyui_url, patched_workflow, request_timeout)
        history_item = wait_for_history(comfyui_url, prompt_id, output_timeout, poll_interval)

        image_meta = extract_first_image(history_item)
        image_bytes = fetch_image(comfyui_url, image_meta, request_timeout)
        image_b64 = encode_image_base64(image_bytes, image_format)

        return {
            "images": [image_b64],
            "parameters": req.model_dump(),
            "info": json.dumps(
                {
                    "proxy": "comfyui-a1111-proxy",
                    "prompt_id": prompt_id,
                    "image": image_meta,
                }
            ),
        }

    except requests.exceptions.RequestException as e:
        raise HTTPException(status_code=502, detail=f"ComfyUI request failed: {e}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))