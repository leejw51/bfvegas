"""
Compose final playing cards from Grok raw assets + PIL text.
V2: High-res (800x1120 -> 200x280), Grok backgrounds, bigger text/symbols.

Preview mode: python3 compose_cards_v2.py --preview
Full mode:    python3 compose_cards_v2.py
"""

import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

RAW_DIR = Path("poker/assets/raw")
OUT_DIR = Path("poker/assets/cards")
PREVIEW_DIR = Path("poker/assets")

# High-res working size (4x final)
W, H = 800, 1120
# Final game size
FW, FH = 200, 280

RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
SUITS = {
    "s": {"name": "Spades", "color": (30, 30, 30), "file": "suit_spade.png"},
    "h": {"name": "Hearts", "color": (190, 20, 20), "file": "suit_heart.png"},
    "d": {"name": "Diamonds", "color": (190, 20, 20), "file": "suit_diamond.png"},
    "c": {"name": "Clubs", "color": (30, 30, 30), "file": "suit_club.png"},
}

RANK_FILE = {
    "A": "a", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6",
    "7": "7", "8": "8", "9": "9", "10": "t", "J": "j", "Q": "q", "K": "k",
}

FACE_FILES = {"J": "face_jack.png", "Q": "face_queen.png", "K": "face_king.png"}

# Standard pip positions (normalized within pip area)
PIPS = {
    "A":  [(0.5, 0.5)],
    "2":  [(0.5, 0.22), (0.5, 0.78)],
    "3":  [(0.5, 0.18), (0.5, 0.5), (0.5, 0.82)],
    "4":  [(0.3, 0.22), (0.7, 0.22), (0.3, 0.78), (0.7, 0.78)],
    "5":  [(0.3, 0.22), (0.7, 0.22), (0.5, 0.5), (0.3, 0.78), (0.7, 0.78)],
    "6":  [(0.3, 0.2), (0.7, 0.2), (0.3, 0.5), (0.7, 0.5), (0.3, 0.8), (0.7, 0.8)],
    "7":  [(0.3, 0.18), (0.7, 0.18), (0.5, 0.34), (0.3, 0.5), (0.7, 0.5),
           (0.3, 0.82), (0.7, 0.82)],
    "8":  [(0.3, 0.18), (0.7, 0.18), (0.5, 0.34), (0.3, 0.5), (0.7, 0.5),
           (0.5, 0.66), (0.3, 0.82), (0.7, 0.82)],
    "9":  [(0.3, 0.15), (0.7, 0.15), (0.3, 0.37), (0.7, 0.37), (0.5, 0.5),
           (0.3, 0.63), (0.7, 0.63), (0.3, 0.85), (0.7, 0.85)],
    "10": [(0.3, 0.13), (0.7, 0.13), (0.5, 0.27), (0.3, 0.37), (0.7, 0.37),
           (0.3, 0.63), (0.7, 0.63), (0.5, 0.73), (0.3, 0.87), (0.7, 0.87)],
}


def load_font(size):
    paths = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()


def rounded_rect_mask(w, h, r):
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (w - 1, h - 1)], radius=r, fill=255)
    return mask


def extract_symbol(raw_img):
    """Extract the suit symbol, removing white background."""
    img = raw_img.copy().convert("RGBA")
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            brightness = (r + g + b) / 3.0
            if brightness > 230 and a > 0:
                pixels[x, y] = (r, g, b, 0)
            elif brightness > 200:
                new_a = int((1.0 - (brightness - 200) / 55.0) * a)
                pixels[x, y] = (r, g, b, max(0, new_a))
    return img


def paste_c(base, overlay, cx, cy):
    """Paste overlay centered at (cx, cy)."""
    ox, oy = overlay.size
    base.paste(overlay, (int(cx - ox / 2), int(cy - oy / 2)), overlay)


def text_c(draw, text, cx, cy, font, color):
    """Draw text centered at (cx, cy)."""
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text((cx - tw / 2, cy - th / 2), text, fill=color, font=font)


def make_card_base(bg_img):
    """Use Grok-generated background as card base."""
    return bg_img.copy()


def draw_corner_tl(draw, card, rank, symbol_img, font_rank, color):
    """Draw rank + suit in top-left corner."""
    cx = 100
    text_c(draw, rank, cx, 95, font_rank, color)
    corner_sym = symbol_img.resize((150, 150), Image.LANCZOS)
    bbox = draw.textbbox((0, 0), rank, font=font_rank)
    text_h = bbox[3] - bbox[1]
    paste_c(card, corner_sym, cx, 95 + text_h // 2 + 85)


def draw_corner_br(draw, card, rank, symbol_img, font_rank, color):
    """Draw rank + suit in bottom-right corner (symbol above rank)."""
    cx = W - 100
    corner_sym = symbol_img.resize((150, 150), Image.LANCZOS)
    bbox = draw.textbbox((0, 0), rank, font=font_rank)
    text_h = bbox[3] - bbox[1]
    paste_c(card, corner_sym, cx, H - 95 - text_h // 2 - 85)
    text_c(draw, rank, cx, H - 95, font_rank, color)


def compose_pip_card(bg_img, symbol_img, rank, color, font_rank):
    """Compose a number/ace card with pip layout on Grok background."""
    card = make_card_base(bg_img)
    draw = ImageDraw.Draw(card)

    # Pip area bounds (centered, with room for corners)
    px0, py0 = 160, 250
    px1, py1 = W - 160, H - 250

    # Pip size - MUCH BIGGER
    if rank == "A":
        pip_sz = 300
    else:
        pip_sz = 150

    pip = symbol_img.resize((pip_sz, pip_sz), Image.LANCZOS)

    for (nx, ny) in PIPS[rank]:
        x = int(px0 + nx * (px1 - px0))
        y = int(py0 + ny * (py1 - py0))
        paste_c(card, pip, x, y)

    # Corners: rank + symbol stacked
    draw_corner_tl(draw, card, rank, symbol_img, font_rank, color)
    draw_corner_br(draw, card, rank, symbol_img, font_rank, color)

    return card


def compose_face_card(bg_img, symbol_img, face_img, rank, color, font_rank):
    """Compose a face card (J/Q/K) with portrait on Grok background."""
    card = make_card_base(bg_img)
    draw = ImageDraw.Draw(card)

    # Place face portrait in center - fill the inner area nicely
    portrait_w, portrait_h = 500, 620
    portrait = face_img.resize((portrait_w, portrait_h), Image.LANCZOS)

    # Replace dark background pixels with card bg color (cream ~240,235,225)
    from PIL import ImageFilter
    pp = portrait.load()
    for y in range(portrait_h):
        for x in range(portrait_w):
            r, g, b, a = pp[x, y]
            brightness = (r * 0.299 + g * 0.587 + b * 0.114)
            if brightness < 50 and a > 0:
                # Dark pixel -> make transparent
                pp[x, y] = (r, g, b, 0)
            elif brightness < 90 and a > 0:
                # Semi-dark -> fade out
                factor = (brightness - 50) / 40.0
                pp[x, y] = (r, g, b, int(a * factor))

    # Create soft rounded mask to blend edges
    pmask = Image.new("L", (portrait_w, portrait_h), 0)
    pmask_draw = ImageDraw.Draw(pmask)
    pmask_draw.rounded_rectangle([(0, 0), (portrait_w - 1, portrait_h - 1)],
                                  radius=50, fill=255)
    pmask = pmask.filter(ImageFilter.GaussianBlur(radius=15))

    # Combine portrait alpha with edge mask
    pa = portrait.split()[3]
    from PIL import ImageChops
    combined_mask = ImageChops.multiply(pa, pmask)

    px = int(W / 2 - portrait_w / 2)
    py = int(H / 2 - portrait_h / 2)
    card.paste(portrait, (px, py), combined_mask)

    # Semi-transparent backing behind corners for readability
    for (cx, cy) in [(100, 155), (W - 100, H - 155)]:
        overlay = Image.new("RGBA", (210, 310), (255, 255, 255, 220))
        paste_c(card, overlay, cx, cy)

    # Corners: rank + symbol stacked
    draw_corner_tl(draw, card, rank, symbol_img, font_rank, color)
    draw_corner_br(draw, card, rank, symbol_img, font_rank, color)

    return card


def finalize(card, radius=36):
    """Add rounded corners and downscale."""
    mask = rounded_rect_mask(W, H, radius)
    card.putalpha(mask)
    return card.resize((FW, FH), Image.LANCZOS)


def main():
    preview_only = "--preview" in sys.argv

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    # Check assets
    needed = ["card_face_bg.png", "card_back.png", "suit_heart.png",
              "suit_diamond.png", "suit_club.png", "suit_spade.png",
              "face_jack.png", "face_queen.png", "face_king.png"]
    missing = [f for f in needed if not (RAW_DIR / f).exists()]
    if missing:
        print("Missing raw assets:")
        for m in missing:
            print(f"  - {m}")
        print("Run: python3 generate_card_assets_v2.py  and  python3 generate_card_bg.py")
        sys.exit(1)

    # Load assets
    print("Loading raw assets...")

    # Grok-generated card face background
    face_bg = Image.open(RAW_DIR / "card_face_bg.png").convert("RGBA")
    face_bg = face_bg.resize((W, H), Image.LANCZOS)

    # Grok-generated card back
    back_img = Image.open(RAW_DIR / "card_back.png").convert("RGBA")
    back_img = back_img.resize((W, H), Image.LANCZOS)

    symbols = {}
    for code, info in SUITS.items():
        raw = Image.open(RAW_DIR / info["file"]).convert("RGBA")
        symbols[code] = extract_symbol(raw)

    faces = {}
    for rank, fname in FACE_FILES.items():
        raw = Image.open(RAW_DIR / fname).convert("RGBA")
        faces[rank] = extract_symbol(raw)

    # Fonts - HUGE: 180px for rank (readable at small card sizes)
    font_rank = load_font(180)

    if preview_only:
        print("=== Preview Mode ===")
        mask = rounded_rect_mask(W, H, 36)

        # Ace of Spades
        card = compose_pip_card(face_bg, symbols["s"], "A", SUITS["s"]["color"] + (255,), font_rank)
        card_hi = card.copy(); card_hi.putalpha(mask)
        card_hi.save(PREVIEW_DIR / "preview_as_hires.png", "PNG")
        finalize(card).save(PREVIEW_DIR / "preview_as_final.png", "PNG")
        print("  Saved preview_as_hires.png (800x1120)")

        # King of Hearts
        card2 = compose_face_card(face_bg, symbols["h"], faces["K"], "K", SUITS["h"]["color"] + (255,), font_rank)
        card2_hi = card2.copy(); card2_hi.putalpha(mask)
        card2_hi.save(PREVIEW_DIR / "preview_kh_hires.png", "PNG")
        finalize(card2).save(PREVIEW_DIR / "preview_kh_final.png", "PNG")
        print("  Saved preview_kh_hires.png (800x1120)")

        # 7 of Diamonds
        card3 = compose_pip_card(face_bg, symbols["d"], "7", SUITS["d"]["color"] + (255,), font_rank)
        card3_hi = card3.copy(); card3_hi.putalpha(mask)
        card3_hi.save(PREVIEW_DIR / "preview_7d_hires.png", "PNG")
        finalize(card3).save(PREVIEW_DIR / "preview_7d_final.png", "PNG")
        print("  Saved preview_7d_hires.png (800x1120)")

        # Card back
        back_hi = back_img.copy(); back_hi.putalpha(mask)
        back_hi.save(PREVIEW_DIR / "preview_back_hires.png", "PNG")
        print("  Saved preview_back_hires.png (800x1120)")
        return

    # Full generation
    print("=" * 50)
    print(f"  Composing 52 cards + back ({W}x{H} -> {FW}x{FH})")
    print("=" * 50)

    count = 0
    for suit_code, info in SUITS.items():
        sym = symbols[suit_code]
        color = info["color"] + (255,)

        for rank in RANKS:
            fname = f"{RANK_FILE[rank]}{suit_code}.png"

            if rank in ("J", "Q", "K"):
                card = compose_face_card(face_bg, sym, faces[rank], rank, color, font_rank)
            else:
                card = compose_pip_card(face_bg, sym, rank, color, font_rank)

            final = finalize(card)
            final.save(OUT_DIR / fname, "PNG")
            count += 1
            print(f"  [{count:2d}/53] {rank:>2s} of {info['name']:8s} -> {fname}")

    # Card back
    back_final = finalize(back_img)
    back_final.save(OUT_DIR / "back.png", "PNG")
    count += 1
    print(f"  [{count:2d}/53] Card back       -> back.png")

    print(f"\nDone! {count} cards at {FW}x{FH} in {OUT_DIR}/")


if __name__ == "__main__":
    main()
