"""Generate AI player avatars using Grok Imagine API, then create sprite sheets."""

import os
import sys
import httpx
from pathlib import Path
from PIL import Image

API_KEY = os.environ.get("GROK_API_KEY")
if not API_KEY:
    print("Error: GROK_API_KEY environment variable not set")
    sys.exit(1)

HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}
IMAGE_URL = "https://api.x.ai/v1/images/generations"
MODEL = "grok-imagine-image"

ASSETS_DIR = Path(__file__).parent / "assets" / "avatars"
ASSETS_DIR.mkdir(parents=True, exist_ok=True)

# Avatar definitions: name -> prompt
AVATARS = {
    "alice": (
        "Portrait of a confident young woman poker player, red hair, wearing sunglasses "
        "and a black leather jacket, casino background, stylized cartoon art style, "
        "bust shot, facing forward, vibrant colors, game character portrait"
    ),
    "bob": (
        "Portrait of a cool middle-aged man poker player, short beard, wearing a fedora hat "
        "and suit with tie, casino background, stylized cartoon art style, "
        "bust shot, facing forward, vibrant colors, game character portrait"
    ),
    "charlie": (
        "Portrait of a mysterious young man poker player, dark hair slicked back, "
        "wearing a hoodie with headphones around neck, casino background, stylized cartoon art style, "
        "bust shot, facing forward, vibrant colors, game character portrait"
    ),
    "you": (
        "Portrait of a friendly poker player, short brown hair, casual polo shirt, "
        "warm smile, casino background, stylized cartoon art style, "
        "bust shot, facing forward, vibrant colors, game character portrait"
    ),
}

# Animation frames: we generate slight variations for idle animation
ANIM_PROMPTS_SUFFIX = [
    ", neutral expression, eyes looking straight ahead",
    ", slight smile, eyes looking slightly to the left",
    ", thinking expression, eyes looking slightly up",
    ", confident smirk, eyes looking slightly to the right",
]


def generate_image(prompt):
    """Generate an image and return URL."""
    resp = httpx.post(
        IMAGE_URL,
        headers=HEADERS,
        json={"model": MODEL, "prompt": prompt, "n": 1, "response_format": "url"},
        timeout=120,
    )
    resp.raise_for_status()
    data = resp.json()
    images = data.get("data", [])
    if not images:
        raise RuntimeError("No image returned")
    return images[0].get("url", "")


def download_image(url, filepath):
    """Download image from URL."""
    resp = httpx.get(url, timeout=60, follow_redirects=True)
    resp.raise_for_status()
    filepath.write_bytes(resp.content)
    return filepath


def create_sprite_sheet(name, frame_paths, output_path, frame_size=128):
    """Combine individual frames into a horizontal sprite sheet."""
    frames = []
    for fp in frame_paths:
        img = Image.open(fp).convert("RGBA")
        # Crop to square (center crop)
        w, h = img.size
        side = min(w, h)
        left = (w - side) // 2
        top = (h - side) // 2
        img = img.crop((left, top, left + side, top + side))
        # Resize to frame_size
        img = img.resize((frame_size, frame_size), Image.LANCZOS)
        frames.append(img)

    # Create horizontal sprite sheet
    sheet_w = frame_size * len(frames)
    sheet_h = frame_size
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        sheet.paste(frame, (i * frame_size, 0))

    sheet.save(output_path)
    print(f"  Sprite sheet: {output_path} ({len(frames)} frames, {sheet_w}x{sheet_h})")
    return output_path


def create_static_avatar(name, frame_path, output_path, size=128):
    """Create a single static avatar image (circular crop with transparency)."""
    img = Image.open(frame_path).convert("RGBA")
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    img = img.crop((left, top, left + side, top + side))
    img = img.resize((size, size), Image.LANCZOS)

    # Create circular mask
    from PIL import ImageDraw
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size - 1, size - 1), fill=255)

    # Apply circular mask
    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    result.paste(img, mask=mask)
    result.save(output_path)
    print(f"  Avatar: {output_path} ({size}x{size}, circular)")


def main():
    print("=" * 50)
    print("  Avatar Generator for Poker Game")
    print("=" * 50)

    for name, base_prompt in AVATARS.items():
        print(f"\nGenerating avatar for: {name}")
        raw_dir = ASSETS_DIR / "raw"
        raw_dir.mkdir(exist_ok=True)

        frame_paths = []
        for i, suffix in enumerate(ANIM_PROMPTS_SUFFIX):
            frame_file = raw_dir / f"{name}_frame{i}.png"

            if frame_file.exists():
                print(f"  Frame {i}: already exists, skipping")
                frame_paths.append(frame_file)
                continue

            prompt = base_prompt + suffix
            print(f"  Frame {i}: generating...")
            try:
                url = generate_image(prompt)
                download_image(url, frame_file)
                print(f"  Frame {i}: saved to {frame_file}")
                frame_paths.append(frame_file)
            except Exception as e:
                print(f"  Frame {i}: ERROR - {e}")
                # If we fail on animation frames, just duplicate frame 0
                if i > 0 and len(frame_paths) > 0:
                    frame_paths.append(frame_paths[0])

        if not frame_paths:
            print(f"  SKIPPED {name}: no frames generated")
            continue

        # Create sprite sheet (for animation)
        sprite_path = ASSETS_DIR / f"{name}_sprite.png"
        create_sprite_sheet(name, frame_paths, sprite_path)

        # Create static avatar (circular, for display)
        avatar_path = ASSETS_DIR / f"{name}.png"
        create_static_avatar(name, frame_paths[0], avatar_path)

    print("\n" + "=" * 50)
    print("  Done! Avatars saved to:", ASSETS_DIR)
    print("=" * 50)
    print("\nFiles generated:")
    for f in sorted(ASSETS_DIR.glob("*.png")):
        print(f"  {f.name}")


if __name__ == "__main__":
    main()
