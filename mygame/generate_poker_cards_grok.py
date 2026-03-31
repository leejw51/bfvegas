"""Generate all 52 playing cards + card back using Grok Imagine API, then polish with PIL."""

import os
import sys
import httpx
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from io import BytesIO
import time

API_KEY = os.environ.get("GROK_API_KEY")
if not API_KEY:
    print("Error: GROK_API_KEY environment variable not set")
    sys.exit(1)

HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}
IMAGE_URL = "https://api.x.ai/v1/images/generations"
MODEL = "grok-imagine-image"

OUTPUT_DIR = Path("poker/assets/cards")
CARD_SIZE = (100, 140)

RANKS = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
SUITS = {
    "s": ("Spades", "black"),
    "h": ("Hearts", "red"),
    "d": ("Diamonds", "red"),
    "c": ("Clubs", "black"),
}

RANK_FILENAMES = {
    "2": "2", "3": "3", "4": "4", "5": "5", "6": "6",
    "7": "7", "8": "8", "9": "9", "10": "t",
    "J": "j", "Q": "q", "K": "k", "A": "a",
}

USD_TO_KRW = 1450
USD_TO_HKD = 7.82


def generate_image(prompt):
    """Call Grok API to generate an image, return image URL."""
    resp = httpx.post(
        IMAGE_URL,
        headers=HEADERS,
        json={"model": MODEL, "prompt": prompt, "n": 1, "response_format": "url"},
        timeout=120,
    )
    resp.raise_for_status()
    data = resp.json()
    return data["data"][0]["url"]


def download_and_resize(url, filepath, size=CARD_SIZE):
    """Download image, resize to card dimensions, save as PNG."""
    resp = httpx.get(url, timeout=60, follow_redirects=True)
    resp.raise_for_status()
    img = Image.open(BytesIO(resp.content)).convert("RGBA")
    img = img.resize(size, Image.LANCZOS)
    # Add rounded corners
    img = add_rounded_corners(img, radius=8)
    img.save(filepath, "PNG")


def add_rounded_corners(img, radius=8):
    """Add rounded corners with transparency."""
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (w - 1, h - 1)], radius=radius, fill=255)
    result = img.copy()
    result.putalpha(mask)
    return result


def get_card_prompt(rank, suit_name, color):
    """Generate a detailed prompt for a specific card."""
    if rank in ("J", "Q", "K"):
        face_name = {"J": "Jack", "Q": "Queen", "K": "King"}[rank]
        return (
            f"A beautifully illustrated {face_name} of {suit_name} playing card, "
            f"classic royal portrait style, ornate {color} and gold design, "
            f"white card background, sharp clean illustration, "
            f"professional casino card art, detailed character portrait, "
            f"traditional playing card layout with mirrored top and bottom halves"
        )
    elif rank == "A":
        return (
            f"An elegant Ace of {suit_name} playing card, "
            f"large ornate {suit_name.lower()} symbol centered on white card, "
            f"decorative flourishes, {color} ink on white, "
            f"professional casino quality, clean crisp design, "
            f"classic premium playing card style"
        )
    else:
        return (
            f"A clean {rank} of {suit_name} playing card, "
            f"white background, {rank} {suit_name.lower()} pips arranged in standard layout, "
            f"{color} suit symbols, professional casino card design, "
            f"sharp minimalist style, rank number in corners"
        )


def get_back_prompt():
    """Prompt for card back design."""
    return (
        "Ornate playing card back design, deep navy blue with intricate gold "
        "geometric patterns, symmetrical mandala-like design, premium casino quality, "
        "rich royal aesthetic, detailed scrollwork and filigree border, "
        "luxurious elegant card back pattern"
    )


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Build list of all cards to generate
    cards = []
    for suit_code, (suit_name, color) in SUITS.items():
        for rank in RANKS:
            filename = f"{RANK_FILENAMES[rank]}{suit_code}.png"
            prompt = get_card_prompt(rank, suit_name, color)
            cards.append((filename, prompt, f"{rank} of {suit_name}"))

    # Add card back
    cards.append(("back.png", get_back_prompt(), "Card Back"))

    total = len(cards)
    cost_per = 0.01
    total_cost = total * cost_per

    print("=" * 56)
    print(f"  Grok Card Generator ({total} cards)")
    print(f"  Estimated cost: ${total_cost:.2f} / "
          f"{total_cost * USD_TO_KRW:.0f} KRW / "
          f"HK${total_cost * USD_TO_HKD:.2f}")
    print("=" * 56)

    generated = 0
    errors = []

    for i, (filename, prompt, label) in enumerate(cards):
        filepath = OUTPUT_DIR / filename
        print(f"  [{i+1:2d}/{total}] {label:20s} -> {filename:10s} ", end="", flush=True)

        try:
            url = generate_image(prompt)
            download_and_resize(url, filepath)
            generated += 1
            print("OK")
        except Exception as e:
            errors.append((filename, str(e)))
            print(f"FAIL: {e}")

        # Small delay to be nice to rate limits
        if i < total - 1:
            time.sleep(0.3)

    print()
    print("=" * 56)
    print(f"  Generated: {generated}/{total}")
    if errors:
        print(f"  Errors: {len(errors)}")
        for fn, err in errors:
            print(f"    {fn}: {err}")
    print(f"  Total cost: ${generated * cost_per:.2f} / "
          f"{generated * cost_per * USD_TO_KRW:.0f} KRW / "
          f"HK${generated * cost_per * USD_TO_HKD:.2f}")
    print("=" * 56)


if __name__ == "__main__":
    main()
