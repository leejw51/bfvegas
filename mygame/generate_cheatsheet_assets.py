"""Generate background artwork for the in-game poker Cheatsheet screen.

Reuses the Grok image API helpers from ``generate_image.py`` and writes the
result directly into ``poker/assets/cheatsheet_bg.png`` so the LOVE2D game
picks it up at runtime. If the file already exists it is left alone unless
``--force`` is passed.

Usage:
    export GROK_API_KEY=...
    python generate_cheatsheet_assets.py          # skip if already generated
    python generate_cheatsheet_assets.py --force  # overwrite existing image
"""

import sys
from pathlib import Path

import httpx

# Reuse the API helpers already defined in generate_image.py.
from generate_image import generate_image, print_cost

ASSET_DIR = Path(__file__).parent / "poker" / "assets"
OUTPUT_FILE = ASSET_DIR / "cheatsheet_bg.png"

PROMPT = (
    "Luxurious casino poker cheatsheet background, ornate gold border, "
    "rich dark green felt table, playing card motifs (club, diamond, heart, "
    "spade) as faint decorative watermarks, subtle bokeh lights, cinematic "
    "lighting, 16:9 widescreen, highly detailed, empty center area suitable "
    "for text overlay, no text, no letters"
)


def download_to(url: str, dest: Path) -> Path:
    resp = httpx.get(url, timeout=60, follow_redirects=True)
    resp.raise_for_status()
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(resp.content)
    return dest


def main() -> int:
    force = "--force" in sys.argv
    if OUTPUT_FILE.exists() and not force:
        print(f"Already exists: {OUTPUT_FILE}  (use --force to regenerate)")
        return 0

    print("Generating cheatsheet background via Grok Imagine...")
    try:
        result, _headers = generate_image(PROMPT)
    except httpx.HTTPStatusError as e:
        print(f"Error: {e.response.status_code} - {e.response.text}")
        return 1

    images = result.get("data", [])
    if not images:
        print("No images returned from API.")
        return 1

    url = images[0].get("url", "")
    if not url:
        print("No image URL in response.")
        return 1

    saved = download_to(url, OUTPUT_FILE)
    print(f"Saved: {saved.resolve()}")
    print_cost(0.01, len(images))
    return 0


if __name__ == "__main__":
    sys.exit(main())
