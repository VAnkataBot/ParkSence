"""
Parking sign analysis with local-first inference and HF cloud fallback.

Primary:  mlx-vlm (Apple Silicon native, 4-bit quantized)
Fallback: HF Inference API (https://router.huggingface.co) — used when
          the local model fails OR is not loaded AND HF_TOKEN is set.

Environment variables:
  LLM_MODEL   mlx-community model ID  (default: mlx-community/Qwen2.5-VL-3B-Instruct-4bit)
  HF_TOKEN    HF access token         (enables cloud fallback, optional)
  HF_MODEL    Model for HF fallback   (default: Qwen/Qwen2.5-VL-72B-Instruct)
"""

import os
import json
import base64
import logging
import tempfile
from io import BytesIO

from PIL import Image

logger = logging.getLogger(__name__)

LOCAL_MODEL_ID  = os.getenv("LLM_MODEL", "mlx-community/Qwen3-VL-8B-Instruct-4bit")
MODEL_DIR       = os.path.join(os.path.dirname(os.path.abspath(__file__)), "model")
HF_TOKEN        = os.getenv("HF_TOKEN")
HF_ENDPOINT     = "https://router.huggingface.co/v1/chat/completions"

# Cloud fallback model options (set via HF_MODEL env var):
#   Qwen/Qwen2.5-VL-72B-Instruct      — best OCR scores (DocVQA 96.4), Hyperbolic
#   Qwen/Qwen3-VL-30B-A3B-Instruct    — newer gen, 3B active params, cheap, Novita
#   Qwen/Qwen3-VL-235B-A22B-Instruct  — most capable Qwen VL to date, Novita
#   meta-llama/Llama-4-Scout-17B-16E-Instruct — fastest (Groq)
HF_MODEL_ID = os.getenv("HF_MODEL", "Qwen/Qwen2.5-VL-72B-Instruct")

VEHICLE_LABELS = {
    "car":        "a regular passenger car",
    "motorcycle": "a motorcycle/moped",
    "ev":         "an electric vehicle (EV)",
    "truck":      "a truck/light goods vehicle",
    "bus":        "a bus/coach",
}

# ── Prompt ────────────────────────────────────────────────────────────────────

def build_prompt(day: str, time: str, date: str, vehicle_type: str,
                 is_disabled: bool, has_resident_permit: bool, resident_zone: str) -> str:
    vehicle_desc = VEHICLE_LABELS.get(vehicle_type, "a regular passenger car")
    driver_desc = f"a driver in {vehicle_desc}"
    if is_disabled:
        driver_desc += " WITH a disability parking permit (♿)"
    if has_resident_permit:
        zone = f" zone {resident_zone}" if resident_zone else ""
        driver_desc += f", WITH a resident parking permit{zone}"

    return f"""You are an expert on Swedish parking signs and traffic regulations (Trafikförordningen).
Analyze this parking sign image for: {driver_desc}

Current time: {day} {time}
Current date: {date}

PHASE 1 — LIST every sign, plate, symbol, and text visible on the pole. Include:
- Main signs (round blue/red, P sign blue square)
- Supplementary plates (time ranges, arrows, text, symbols)
- Vehicle symbols (♿, EV, motorcycle, truck, taxi, etc.)
- Text plates (Boende, Tillstånd, Nyttotrafik, Avgift, Taxa, Övrig tid, etc.)
- Distance plates (e.g. "0-13 m"), arrow plates (↑ ↓ ↕)
If you find fewer than 3 items, look again.

PHASE 2 — RULES (in order):

STEP 1 — HARD BLOCKS. Check if ANY sign reserves the spot for a group this driver does NOT belong to:
- ♿ → disabled only. Block UNLESS driver has disability permit.
- EV charging → EVs only. Block UNLESS driver has EV.
- Motorcycle symbol → motorcycles only. Block UNLESS driver is on motorcycle.
- Boende/Boendeparkering → residents only. Block UNLESS driver has resident permit for the zone.
  Exception: "Boende Sö" only applies on Sundays — check today first.
- Tillstånd → permit holders only. Always block.
- Nyttotrafik → commercial vehicles only. Block UNLESS driver is in truck.
- Taxi → always block.
If blocked → can_park = false. STOP.

STEP 2 — TIMED RESTRICTIONS. For every no-parking/no-stopping sign with a time plate:
  Step A: Does the day match today ({day})? If NO → restriction inactive, skip.
  Step B: Is {time} within the stated hour range numerically? If NO → restriction inactive, skip.
  Only if BOTH yes → restriction active → can_park = false.

Example: "Torsd 0-6", today Thursday, time 09:30.
  Step A: Thursday = today → YES. Step B: is 09:30 in 00:00-06:00? 9 > 6 → NO.
  Restriction NOT active. Continue.

Time plate conventions:
  7-19           = weekdays Mon-Fri only
  (7-19)         = Saturdays only
  ((7-19))       = Sundays/holidays only
  No time plate  = 24/7

STEP 3 — P SIGN. Blue square P = parking allowed. Note: Avgift = fee, P-skiva = parking disc.

PHASE 3 — OUTPUT
Write signs and notes FIRST to complete reasoning before verdict.

Final check: is there a restriction active for THIS driver at {day} {time}?
- YES → can_park = false
- NO  → can_park = true (add fees/conditions to notes)
- Uncertain → can_park = null
Notes and can_park MUST be consistent.

Reply with ONLY valid JSON, no other text:
{{"signs": ["one short phrase each"], "notes": ["max 10 words each"], "can_park": true/false/null, "message": "max 15 words"}}"""


# ── Local model (mlx-vlm, Apple Silicon native) ───────────────────────────────

_model     = None
_processor = None


def _load_local_model():
    global _model, _processor
    logger.info(f"Loading local mlx model: {LOCAL_MODEL_ID}")
    os.makedirs(MODEL_DIR, exist_ok=True)

    from huggingface_hub import snapshot_download
    from mlx_vlm import load

    local_path = os.path.join(MODEL_DIR, LOCAL_MODEL_ID.replace("/", "--"))
    if not os.path.isdir(local_path):
        logger.info(f"Downloading model to {local_path} ...")
        snapshot_download(LOCAL_MODEL_ID, local_dir=local_path)

    _model, _processor = load(local_path, trust_remote_code=True)
    logger.info("Local mlx model ready")


def _infer_local(image: Image.Image, prompt_text: str) -> str:
    global _model, _processor
    if _model is None:
        _load_local_model()

    from mlx_vlm import generate

    # Save image to a temp file — mlx_vlm works best with file paths
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        image.save(tmp, format="JPEG", quality=90)
        tmp_path = tmp.name

    try:
        # Apply the model's chat template if the processor supports it
        if hasattr(_processor, "apply_chat_template"):
            messages = [{"role": "user", "content": [
                {"type": "image"},
                {"type": "text", "text": prompt_text},
            ]}]
            formatted_prompt = _processor.apply_chat_template(
                messages, tokenize=False, add_generation_prompt=True
            )
        else:
            formatted_prompt = prompt_text

        result = generate(
            _model,
            _processor,
            prompt=formatted_prompt,
            image=tmp_path,
            max_tokens=1024,
            temperature=0.1,
            verbose=False,
        )
        return result.text if hasattr(result, "text") else str(result)
    finally:
        os.unlink(tmp_path)


# ── HF cloud fallback ─────────────────────────────────────────────────────────

def _infer_hf_cloud(image_b64: str, prompt_text: str) -> str:
    import urllib.request

    payload = json.dumps({
        "model": HF_MODEL_ID,
        "max_tokens": 1024,
        "temperature": 0.1,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "image_url",
                 "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}},
                {"type": "text", "text": prompt_text},
            ],
        }],
    }).encode()

    req = urllib.request.Request(
        HF_ENDPOINT,
        data=payload,
        headers={
            "Authorization": f"Bearer {HF_TOKEN}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read())

    return data["choices"][0]["message"]["content"].strip()


# ── Public entry point ────────────────────────────────────────────────────────

def analyze_image(
    image_b64: str,
    day: str,
    time: str,
    date: str,
    vehicle_type: str = "car",
    is_disabled: bool = False,
    has_resident_permit: bool = False,
    resident_zone: str = "",
) -> dict:
    image = Image.open(BytesIO(base64.b64decode(image_b64))).convert("RGB")
    prompt_text = build_prompt(day, time, date, vehicle_type,
                               is_disabled, has_resident_permit, resident_zone)

    raw: str | None = None

    # 1. Try local model
    try:
        raw = _infer_local(image, prompt_text)
        logger.info("Inference via local mlx model")
    except Exception as e:
        logger.warning(f"Local model failed: {e}")

    # 2. Fallback to HF cloud if local failed and token is available
    if raw is None:
        if not HF_TOKEN:
            raise RuntimeError(
                "Local model failed and HF_TOKEN is not set. "
                "Set HF_TOKEN to enable cloud fallback."
            )
        logger.info(f"Falling back to HF cloud: {HF_MODEL_ID}")
        raw = _infer_hf_cloud(image_b64, prompt_text)

    # Extract JSON block from response
    start = raw.index("{")
    end   = raw.rindex("}") + 1
    return json.loads(raw[start:end])
