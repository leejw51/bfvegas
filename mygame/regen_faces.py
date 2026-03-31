"""Regenerate face card portraits with white/cream background to match card."""

import os
import sys
import httpx
from pathlib import Path
from PIL import Image
from io import BytesIO
import time

API_KEY = os.environ.get("GROK_API_KEY")
if not API_KEY:
    print("Error: GROK_API_KEY environment variable not set")
    sys.exit(1)

HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}
IMAGE_URL = "https://api.x.ai/v1/images/generations"
MODEL = "grok-imagine-image"
RAW_DIR = Path("poker/assets/raw")

FACES = [
    {
        "file": "face_jack.png",
        "prompt": (
            "A young Jack prince character illustration for a playing card, "
            "medieval nobleman in colorful ornate clothing holding a sword, "
            "classic European playing card art style, painted illustration, "
            "on a plain cream white parchment background, "
            "NO text NO letters NO words NO border, just the character, "
            "upper body portrait, warm colors, detailed gold embroidery"
        ),
    },
    {
        "file": "face_queen.png",
        "prompt": (
            "A regal Queen character illustration for a playing card, "
            "beautiful queen wearing ornate golden crown and elegant royal dress, "
            "holding a scepter, classic European playing card art style, painted illustration, "
            "on a plain cream white parchment background, "
            "NO text NO letters NO words NO border, just the character, "
            "upper body portrait, warm colors, detailed gold embroidery"
        ),
    },
    {
        "file": "face_king.png",
        "prompt": (
            "A majestic King character illustration for a playing card, "
            "bearded king wearing ornate golden crown and rich royal robes, "
            "holding a sword, classic European playing card art style, painted illustration, "
            "on a plain cream white parchment background, "
            "NO text NO letters NO words NO border, just the character, "
            "upper body portrait, warm colors, detailed gold embroidery"
        ),
    },
]


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
    print("Regenerating face cards with white background...")
    for i, face in enumerate(FACES):
        print(f"  [{i+1}/3] {face['file']:20s} ", end="", flush=True)
        try:
            url = generate_image(face["prompt"])
            download_and_resize(url, RAW_DIR / face["file"], (500, 600))
            print("OK")
        except Exception as e:
            print(f"FAIL: {e}")
        if i < 2:
            time.sleep(0.3)
    print("  Cost: $0.03")
    print("  Next: python3 compose_cards_v2.py --preview")


if __name__ == "__main__":
    main()
