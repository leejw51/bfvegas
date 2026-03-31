"""
Step 1: Generate card art elements via Grok API.
- Card face background (ornate white card template)
- Card back design
- 4 suit symbols (heart, diamond, club, spade)
- 3 face card portraits (Jack, Queen, King)

Step 2 (compose_cards.py) composites these into final 52 cards.
"""

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
USD_TO_KRW = 1450
USD_TO_HKD = 7.82

ASSETS = [
    {
        "name": "card_face_bg",
        "file": "card_face_bg.png",
        "size": (400, 560),
        "prompt": (
            "A blank ornate playing card face template, white card with elegant thin gold "
            "filigree border pattern, subtle cream parchment texture, premium casino quality, "
            "no text no numbers no symbols, empty center, rounded corners, "
            "classic luxury card design, high detail, isolated on dark background"
        ),
    },
    {
        "name": "card_back",
        "file": "card_back.png",
        "size": (400, 560),
        "prompt": (
            "Ornate playing card back design, deep royal navy blue with intricate gold "
            "geometric mandala pattern, symmetrical scrollwork and filigree, "
            "premium casino luxury aesthetic, rich detailed texture, "
            "thin gold border frame, isolated on dark background"
        ),
    },
    {
        "name": "suit_heart",
        "file": "suit_heart.png",
        "size": (200, 200),
        "prompt": (
            "A single red heart suit symbol from playing cards, rich crimson red, "
            "glossy 3D look with subtle shading and highlight, elegant classic design, "
            "isolated on pure white background, vector art quality, sharp edges"
        ),
    },
    {
        "name": "suit_diamond",
        "file": "suit_diamond.png",
        "size": (200, 200),
        "prompt": (
            "A single red diamond suit symbol from playing cards, rich crimson red, "
            "glossy 3D look with subtle shading and highlight, elegant classic design, "
            "isolated on pure white background, vector art quality, sharp edges"
        ),
    },
    {
        "name": "suit_club",
        "file": "suit_club.png",
        "size": (200, 200),
        "prompt": (
            "A single black club suit symbol from playing cards, deep black, "
            "glossy 3D look with subtle shading and highlight, elegant classic design, "
            "isolated on pure white background, vector art quality, sharp edges"
        ),
    },
    {
        "name": "suit_spade",
        "file": "suit_spade.png",
        "size": (200, 200),
        "prompt": (
            "A single black spade suit symbol from playing cards, deep black, "
            "glossy 3D look with subtle shading and highlight, elegant classic design, "
            "isolated on pure white background, vector art quality, sharp edges"
        ),
    },
    {
        "name": "face_jack",
        "file": "face_jack.png",
        "size": (300, 400),
        "prompt": (
            "A Jack court card portrait illustration, young nobleman in medieval attire, "
            "holding a sword, ornate clothing with gold details, classic playing card art style, "
            "mirrored top-bottom composition, rich colors, "
            "isolated on white background, traditional card game illustration"
        ),
    },
    {
        "name": "face_queen",
        "file": "face_queen.png",
        "size": (300, 400),
        "prompt": (
            "A Queen court card portrait illustration, regal woman wearing crown, "
            "holding a scepter, ornate royal dress with gold details, classic playing card art style, "
            "mirrored top-bottom composition, rich colors, "
            "isolated on white background, traditional card game illustration"
        ),
    },
    {
        "name": "face_king",
        "file": "face_king.png",
        "size": (300, 400),
        "prompt": (
            "A King court card portrait illustration, majestic king wearing crown, "
            "holding a sword, ornate royal robes with gold details, classic playing card art style, "
            "mirrored top-bottom composition, rich colors, "
            "isolated on white background, traditional card game illustration"
        ),
    },
]


def generate_image(prompt):
    resp = httpx.post(
        IMAGE_URL,
        headers=HEADERS,
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
    return img


def main():
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    total = len(ASSETS)
    cost = total * 0.01

    print("=" * 56)
    print(f"  Grok Card Asset Generator ({total} images)")
    print(f"  Cost: ${cost:.2f} / {cost * USD_TO_KRW:.0f} KRW / HK${cost * USD_TO_HKD:.2f}")
    print("=" * 56)

    generated = 0
    for i, asset in enumerate(ASSETS):
        filepath = RAW_DIR / asset["file"]
        print(f"  [{i+1}/{total}] {asset['name']:20s} ", end="", flush=True)
        try:
            url = generate_image(asset["prompt"])
            download_and_resize(url, filepath, asset["size"])
            generated += 1
            print("OK")
        except Exception as e:
            print(f"FAIL: {e}")
        if i < total - 1:
            time.sleep(0.3)

    print(f"\n  Generated {generated}/{total} raw assets in {RAW_DIR}/")
    print(f"  Cost: ${generated * 0.01:.2f}")
    print(f"\n  Next: python3 compose_cards.py")


if __name__ == "__main__":
    main()
