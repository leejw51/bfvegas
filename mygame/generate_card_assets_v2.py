"""Generate card art elements via Grok API - V2 with better prompts."""

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

ASSETS = [
    {
        "name": "card_back",
        "file": "card_back.png",
        "size": (800, 1120),
        "prompt": (
            "Ornate playing card back design, deep royal navy blue with intricate gold "
            "geometric mandala pattern, symmetrical scrollwork and filigree, "
            "premium casino luxury aesthetic, rich detailed texture, "
            "thin gold border frame, portrait orientation, isolated on dark background"
        ),
    },
    {
        "name": "suit_heart",
        "file": "suit_heart.png",
        "size": (400, 400),
        "prompt": (
            "A single red heart suit symbol from playing cards, rich crimson red, "
            "glossy 3D look with subtle shading and highlight, elegant classic design, "
            "isolated on pure white background, vector art quality, sharp clean edges, "
            "centered in frame, no other elements"
        ),
    },
    {
        "name": "suit_diamond",
        "file": "suit_diamond.png",
        "size": (400, 400),
        "prompt": (
            "A single red diamond suit symbol from playing cards, rich crimson red, "
            "glossy 3D look with subtle shading and highlight, elegant rotated square shape, "
            "isolated on pure white background, vector art quality, sharp clean edges, "
            "centered in frame, no other elements"
        ),
    },
    {
        "name": "suit_club",
        "file": "suit_club.png",
        "size": (400, 400),
        "prompt": (
            "A single black club trefoil suit symbol from playing cards, deep black, "
            "glossy 3D look with subtle shading and highlight, three-lobed clover shape, "
            "isolated on pure white background, vector art quality, sharp clean edges, "
            "centered in frame, no other elements"
        ),
    },
    {
        "name": "suit_spade",
        "file": "suit_spade.png",
        "size": (400, 400),
        "prompt": (
            "A single black spade suit symbol from playing cards, deep black, "
            "glossy 3D look with subtle shading and highlight, pointed top with curved sides, "
            "isolated on pure white background, vector art quality, sharp clean edges, "
            "centered in frame, no other elements"
        ),
    },
    {
        "name": "face_jack",
        "file": "face_jack.png",
        "size": (500, 600),
        "prompt": (
            "Portrait illustration of a Jack playing card character, young nobleman "
            "in colorful medieval attire holding a sword, ornate clothing with gold details, "
            "classic playing card art style, NO TEXT NO LETTERS NO WORDS, "
            "just the character illustration, white background, "
            "traditional European card game artwork, upper body portrait"
        ),
    },
    {
        "name": "face_queen",
        "file": "face_queen.png",
        "size": (500, 600),
        "prompt": (
            "Portrait illustration of a Queen playing card character, regal woman "
            "wearing ornate crown, holding a scepter, elegant royal dress with gold details, "
            "classic playing card art style, NO TEXT NO LETTERS NO WORDS, "
            "just the character illustration, white background, "
            "traditional European card game artwork, upper body portrait"
        ),
    },
    {
        "name": "face_king",
        "file": "face_king.png",
        "size": (500, 600),
        "prompt": (
            "Portrait illustration of a King playing card character, majestic bearded king "
            "wearing ornate crown, holding a sword, royal robes with gold details, "
            "classic playing card art style, NO TEXT NO LETTERS NO WORDS, "
            "just the character illustration, white background, "
            "traditional European card game artwork, upper body portrait"
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


def main():
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    total = len(ASSETS)
    cost = total * 0.01

    print("=" * 56)
    print(f"  Grok Card Asset Generator V2 ({total} images)")
    print(f"  Cost: ${cost:.2f}")
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

    print(f"\n  Generated {generated}/{total} in {RAW_DIR}/")
    print(f"  Next: python3 compose_cards_v2.py")


if __name__ == "__main__":
    main()
