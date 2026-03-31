"""Generate poker table and title screen assets using xAI Grok Imagine API."""

import os
import sys
from pathlib import Path

import httpx
from PIL import Image

# --- API config ---
API_KEY = os.environ.get("GROK_API_KEY")
if not API_KEY:
    print("Error: GROK_API_KEY environment variable not set")
    sys.exit(1)

HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}
IMAGE_URL = "https://api.x.ai/v1/images/generations"
MODEL = "grok-imagine-image"

OUTPUT_DIR = Path("poker/assets")

# Exchange rates (approximate)
USD_TO_KRW = 1450
USD_TO_HKD = 7.82

# Assets to generate: (filename, target_size, prompt)
ASSETS = [
    (
        "table_bg.png",
        (1280, 720),
        "Top-down view of a professional poker table with dark green felt surface, "
        "wooden rail border, clean elegant design, no cards or chips on table, "
        "photorealistic, 16:9 aspect ratio",
    ),
    (
        "title_bg.png",
        (1280, 720),
        "Luxurious casino poker room, dark moody lighting with golden accents, "
        "elegant typography space, cinematic atmosphere, no text",
    ),
]


def generate_image(prompt):
    """Generate an image via Grok Imagine API and return (data, headers)."""
    resp = httpx.post(
        IMAGE_URL,
        headers=HEADERS,
        json={
            "model": MODEL,
            "prompt": prompt,
            "n": 1,
            "response_format": "url",
        },
        timeout=120,
    )
    resp.raise_for_status()
    return resp.json(), dict(resp.headers)


def download_image(url, filepath):
    """Download image from URL and save to filepath."""
    resp = httpx.get(url, timeout=60, follow_redirects=True)
    resp.raise_for_status()
    filepath.write_bytes(resp.content)
    return filepath


def resize_image(filepath, target_size):
    """Resize image to exact target_size (width, height) using Lanczos resampling."""
    img = Image.open(filepath)
    img = img.resize(target_size, Image.LANCZOS)
    img.save(filepath)
    return img.size


def get_rate_limits(response_headers):
    """Extract rate limit info from response headers."""
    info = {}
    for key, val in response_headers.items():
        if "ratelimit" in key.lower() or "credit" in key.lower():
            info[key] = val
    return info


def main():
    print("=" * 55)
    print(f"  Poker Asset Generator  (model: {MODEL})")
    print("=" * 55)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    generated_count = 0
    all_limits = {}

    for i, (filename, target_size, prompt) in enumerate(ASSETS, 1):
        filepath = OUTPUT_DIR / filename
        print(f"\n[{i}/{len(ASSETS)}] Generating: {filename}")
        print(f"  Prompt: {prompt[:80]}...")
        print(f"  Target size: {target_size[0]}x{target_size[1]}")

        # Generate
        try:
            print("  Calling API...", end="", flush=True)
            result, headers = generate_image(prompt)
            print(" done.")
        except httpx.HTTPStatusError as e:
            print(f"\n  ERROR: {e.response.status_code} - {e.response.text}")
            continue
        except httpx.RequestError as e:
            print(f"\n  ERROR: Request failed - {e}")
            continue

        # Collect rate limits from last response
        all_limits.update(get_rate_limits(headers))

        images = result.get("data", [])
        if not images:
            print("  ERROR: No image data returned.")
            continue

        url = images[0].get("url", "")
        revised = images[0].get("revised_prompt", "")
        if revised:
            print(f"  Revised prompt: {revised[:80]}...")

        if not url:
            print("  ERROR: No URL in response.")
            continue

        # Download
        print(f"  Downloading...", end="", flush=True)
        try:
            download_image(url, filepath)
            print(" done.")
        except (httpx.HTTPStatusError, httpx.RequestError) as e:
            print(f"\n  ERROR: Download failed - {e}")
            continue

        # Resize
        print(f"  Resizing to {target_size[0]}x{target_size[1]}...", end="", flush=True)
        try:
            final_size = resize_image(filepath, target_size)
            print(" done.")
        except Exception as e:
            print(f"\n  ERROR: Resize failed - {e}")
            continue

        print(f"  Saved: {filepath.resolve()}")
        generated_count += 1

    # Summary
    print("\n" + "=" * 55)
    print(f"  Summary")
    print("=" * 55)
    print(f"  Assets generated: {generated_count}/{len(ASSETS)}")

    if all_limits:
        print(f"\n--- Rate Limits ---")
        for k, v in all_limits.items():
            label = k.replace("x-ratelimit-", "").replace("-", " ").title()
            print(f"  {label}: {v}")

    # Cost
    cost_per = 0.01  # $0.01 per image at 1k resolution
    total_usd = cost_per * generated_count
    total_krw = total_usd * USD_TO_KRW
    total_hkd = total_usd * USD_TO_HKD

    print(f"\n--- Cost Summary ---")
    print(f"  Model: {MODEL}")
    print(f"  Cost per image:  ${cost_per:.2f} / {cost_per * USD_TO_KRW:.0f} KRW / HK${cost_per * USD_TO_HKD:.2f}")
    print(f"  Images generated: {generated_count}")
    print(f"  Estimated total:  ${total_usd:.2f} / {total_krw:.0f} KRW / HK${total_hkd:.2f}")
    print()


if __name__ == "__main__":
    main()
