"""
Step 2: Compose final 52 playing cards + back from Grok-generated raw assets.
Uses PIL to precisely place text, suit symbols, and portraits onto card backgrounds.

Raw assets expected in poker/assets/raw/:
  card_face_bg.png  - Card face background template (400x560)
  card_back.png     - Card back design (400x560)
  suit_heart.png    - Heart symbol (200x200)
  suit_diamond.png  - Diamond symbol (200x200)
  suit_club.png     - Club symbol (200x200)
  suit_spade.png    - Spade symbol (200x200)
  face_jack.png     - Jack portrait (300x400)
  face_queen.png    - Queen portrait (300x400)
  face_king.png     - King portrait (300x400)

Output: poker/assets/cards/ with 100x140 PNGs
"""

import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

RAW_DIR = Path("poker/assets/raw")
OUT_DIR = Path("poker/assets/cards")

# Work at 4x resolution (400x560) then downscale to 100x140 for crisp results
WORK_W, WORK_H = 400, 560
FINAL_W, FINAL_H = 100, 140

RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
SUITS = {
    "h": {"name": "Hearts", "color": (180, 20, 20), "symbol_file": "suit_heart.png"},
    "d": {"name": "Diamonds", "color": (180, 20, 20), "symbol_file": "suit_diamond.png"},
    "c": {"name": "Clubs", "color": (30, 30, 30), "symbol_file": "suit_club.png"},
    "s": {"name": "Spades", "color": (30, 30, 30), "symbol_file": "suit_spade.png"},
}

RANK_TO_FILE = {
    "A": "a", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6",
    "7": "7", "8": "8", "9": "9", "10": "t", "J": "j", "Q": "q", "K": "k",
}

FACE_FILES = {"J": "face_jack.png", "Q": "face_queen.png", "K": "face_king.png"}

# Pip layout positions (normalized 0-1 within card center area)
# Center area is roughly x: 0.15-0.85, y: 0.2-0.8
PIP_LAYOUTS = {
    "A":  [(0.5, 0.5)],
    "2":  [(0.5, 0.25), (0.5, 0.75)],
    "3":  [(0.5, 0.2), (0.5, 0.5), (0.5, 0.8)],
    "4":  [(0.3, 0.25), (0.7, 0.25), (0.3, 0.75), (0.7, 0.75)],
    "5":  [(0.3, 0.25), (0.7, 0.25), (0.5, 0.5), (0.3, 0.75), (0.7, 0.75)],
    "6":  [(0.3, 0.2), (0.7, 0.2), (0.3, 0.5), (0.7, 0.5), (0.3, 0.8), (0.7, 0.8)],
    "7":  [(0.3, 0.2), (0.7, 0.2), (0.5, 0.35), (0.3, 0.5), (0.7, 0.5), (0.3, 0.8), (0.7, 0.8)],
    "8":  [(0.3, 0.2), (0.7, 0.2), (0.5, 0.35), (0.3, 0.5), (0.7, 0.5), (0.5, 0.65), (0.3, 0.8), (0.7, 0.8)],
    "9":  [(0.3, 0.18), (0.7, 0.18), (0.3, 0.39), (0.7, 0.39), (0.5, 0.5),
            (0.3, 0.61), (0.7, 0.61), (0.3, 0.82), (0.7, 0.82)],
    "10": [(0.3, 0.15), (0.7, 0.15), (0.5, 0.28), (0.3, 0.38), (0.7, 0.38),
            (0.3, 0.62), (0.7, 0.62), (0.5, 0.72), (0.3, 0.85), (0.7, 0.85)],
}


def load_font(size):
    """Try to load a nice font, fallback to default."""
    font_paths = [
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    for fp in font_paths:
        try:
            return ImageFont.truetype(fp, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()


def add_rounded_corners(img, radius=20):
    """Apply rounded corner mask."""
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (w - 1, h - 1)], radius=radius, fill=255)
    result = img.copy()
    result.putalpha(mask)
    return result


def tint_symbol(symbol_img, color):
    """Tint a symbol image to the suit color."""
    img = symbol_img.copy().convert("RGBA")
    r, g, b = color
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            pr, pg, pb, pa = pixels[x, y]
            # Calculate luminance
            lum = (pr * 0.299 + pg * 0.587 + pb * 0.114) / 255.0
            # Invert: darker original pixels get more color
            intensity = 1.0 - lum
            if pa > 20:
                nr = int(r * intensity + 255 * (1 - intensity))
                ng = int(g * intensity + 255 * (1 - intensity))
                nb = int(b * intensity + 255 * (1 - intensity))
                # Make near-white pixels transparent
                if lum > 0.92:
                    pa = int(pa * (1.0 - lum) * 8)
                pixels[x, y] = (nr, ng, nb, pa)
            else:
                pixels[x, y] = (0, 0, 0, 0)
    return img


def paste_centered(base, overlay, cx, cy):
    """Paste overlay centered at (cx, cy) on base."""
    ox, oy = overlay.size
    x = int(cx - ox / 2)
    y = int(cy - oy / 2)
    base.paste(overlay, (x, y), overlay)


def draw_text_centered(draw, text, cx, cy, font, color):
    """Draw text centered at position."""
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    draw.text((cx - tw / 2, cy - th / 2), text, fill=color, font=font)


def compose_number_card(bg, suit_symbol, rank, color, font_large, font_small):
    """Compose a number card (A, 2-10)."""
    card = bg.copy()
    draw = ImageDraw.Draw(card)

    # Suit symbol resized for pips
    if rank == "A":
        pip_size = 100
    else:
        pip_size = 55

    pip = suit_symbol.resize((pip_size, pip_size), Image.LANCZOS)

    # Draw pips in standard layout
    # Card center area: x 60-340, y 120-440
    cx_min, cx_max = 80, 320
    cy_min, cy_max = 130, 430
    layout = PIP_LAYOUTS.get(rank, [(0.5, 0.5)])

    for (nx, ny) in layout:
        px = int(cx_min + nx * (cx_max - cx_min))
        py = int(cy_min + ny * (cy_max - cy_min))
        paste_centered(card, pip, px, py)

    # Draw rank text in corners
    # Top-left
    draw_text_centered(draw, rank, 40, 50, font_large, color)
    small_pip = suit_symbol.resize((30, 30), Image.LANCZOS)
    paste_centered(card, small_pip, 40, 90)

    # Bottom-right (rotated 180)
    draw_text_centered(draw, rank, WORK_W - 40, WORK_H - 50, font_large, color)
    paste_centered(card, small_pip, WORK_W - 40, WORK_H - 90)

    return card


def compose_face_card(bg, face_img, suit_symbol, rank, color, font_large):
    """Compose a face card (J, Q, K)."""
    card = bg.copy()
    draw = ImageDraw.Draw(card)

    # Place face portrait in center
    portrait = face_img.resize((240, 320), Image.LANCZOS)
    paste_centered(card, portrait, WORK_W // 2, WORK_H // 2)

    # Draw rank in corners
    draw_text_centered(draw, rank, 40, 50, font_large, color)
    small_pip = suit_symbol.resize((30, 30), Image.LANCZOS)
    paste_centered(card, small_pip, 40, 90)

    draw_text_centered(draw, rank, WORK_W - 40, WORK_H - 50, font_large, color)
    paste_centered(card, small_pip, WORK_W - 40, WORK_H - 90)

    return card


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Check raw assets exist
    missing = []
    needed = ["card_face_bg.png", "card_back.png",
              "suit_heart.png", "suit_diamond.png", "suit_club.png", "suit_spade.png",
              "face_jack.png", "face_queen.png", "face_king.png"]
    for f in needed:
        if not (RAW_DIR / f).exists():
            missing.append(f)
    if missing:
        print(f"Missing raw assets in {RAW_DIR}/:")
        for m in missing:
            print(f"  - {m}")
        print(f"\nRun: python3 generate_card_assets.py")
        sys.exit(1)

    # Load raw assets
    print("Loading raw assets...")
    bg = Image.open(RAW_DIR / "card_face_bg.png").convert("RGBA")
    bg = bg.resize((WORK_W, WORK_H), Image.LANCZOS)

    back = Image.open(RAW_DIR / "card_back.png").convert("RGBA")
    back = back.resize((WORK_W, WORK_H), Image.LANCZOS)

    suit_symbols = {}
    for code, info in SUITS.items():
        raw = Image.open(RAW_DIR / info["symbol_file"]).convert("RGBA")
        suit_symbols[code] = tint_symbol(raw, info["color"])

    face_imgs = {}
    for rank, fname in FACE_FILES.items():
        face_imgs[rank] = Image.open(RAW_DIR / fname).convert("RGBA")

    # Load fonts
    font_large = load_font(52)
    font_small = load_font(28)

    print("=" * 50)
    print("  Composing 52 cards + back")
    print("=" * 50)

    count = 0
    for suit_code, info in SUITS.items():
        symbol = suit_symbols[suit_code]
        color = info["color"] + (255,)  # RGBA

        for rank in RANKS:
            filename = f"{RANK_TO_FILE[rank]}{suit_code}.png"

            if rank in ("J", "Q", "K"):
                card = compose_face_card(bg, face_imgs[rank], symbol, rank, color, font_large)
            else:
                card = compose_number_card(bg, symbol, rank, color, font_large, font_small)

            # Add rounded corners
            card = add_rounded_corners(card, radius=20)
            # Downscale to final size
            final = card.resize((FINAL_W, FINAL_H), Image.LANCZOS)
            final.save(OUT_DIR / filename, "PNG")
            count += 1
            print(f"  [{count:2d}/53] {rank:>2s} of {info['name']:8s} -> {filename}")

    # Card back
    back = add_rounded_corners(back, radius=20)
    final_back = back.resize((FINAL_W, FINAL_H), Image.LANCZOS)
    final_back.save(OUT_DIR / "back.png", "PNG")
    count += 1
    print(f"  [{count:2d}/53] Card back       -> back.png")

    print(f"\nDone! {count} cards saved to {OUT_DIR}/")


if __name__ == "__main__":
    main()
