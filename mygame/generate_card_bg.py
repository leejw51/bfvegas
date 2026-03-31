"""Generate card face background via Grok API."""

import os
import sys
import httpx
from pathlib import Path
from PIL import Image
from io import BytesIO

API_KEY = os.environ.get("GROK_API_KEY")
if not API_KEY:
    print("Error: GROK_API_KEY environment variable not set")
    sys.exit(1)

HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}
IMAGE_URL = "https://api.x.ai/v1/images/generations"
MODEL = "grok-imagine-image"
RAW_DIR = Path("poker/assets/raw")


def generate_image(prompt):
    resp = httpx.post(
        IMAGE_URL, headers=HEADERS,
        json={"model": MODEL, "prompt": prompt, "n": 1, "response_format": "url"},
        timeout=120,
    )
    resp.raise_for_status()
    return resp.json()["data"][0]["url"]


def download_and_resize(url, filepath, size):
    resp = httpx.get(url, timeout=60, follow_redirects=True)
    resp.raise_for_status()
    img = Image.open(BytesIO(resp.content)).convert("RGBA")
    img = img.resize(size, Image.LANCZOS)
    img.save(filepath, "PNG")


def main():
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    prompt = (
        "Elegant playing card face background template, cream white parchment with "
        "subtle ornate gold filigree border and corner decorations, delicate scrollwork "
        "frame pattern, luxury premium casino card texture, very subtle warm ivory "
        "center area, NO text NO numbers NO symbols NO suits, just decorative border "
        "and background texture, portrait orientation, classical European style"
    )

    print("Generating card face background via Grok...", flush=True)
    url = generate_image(prompt)
    download_and_resize(url, RAW_DIR / "card_face_bg.png", (800, 1120))
    print(f"  Saved: {RAW_DIR / 'card_face_bg.png'} (800x1120)")
    print("  Cost: $0.01")


if __name__ == "__main__":
    main()
