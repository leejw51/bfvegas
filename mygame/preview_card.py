"""Generate a single preview card (Ace of Spades) to check quality."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

RAW_DIR = Path("poker/assets/raw")
PREVIEW_DIR = Path("poker/assets")
WORK_W, WORK_H = 400, 560


def load_font(size):
    font_paths = [
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    ]
    for fp in font_paths:
        try:
            return ImageFont.truetype(fp, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()


def add_rounded_corners(img, radius=20):
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (w - 1, h - 1)], radius=radius, fill=255)
    result = img.copy()
    result.putalpha(mask)
    return result


def tint_symbol(symbol_img, color):
    img = symbol_img.copy().convert("RGBA")
    r, g, b = color
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            pr, pg, pb, pa = pixels[x, y]
            lum = (pr * 0.299 + pg * 0.587 + pb * 0.114) / 255.0
            intensity = 1.0 - lum
            if pa > 20:
                nr = int(r * intensity + 255 * (1 - intensity))
                ng = int(g * intensity + 255 * (1 - intensity))
                nb = int(b * intensity + 255 * (1 - intensity))
                if lum > 0.92:
                    pa = int(pa * (1.0 - lum) * 8)
                pixels[x, y] = (nr, ng, nb, pa)
            else:
                pixels[x, y] = (0, 0, 0, 0)
    return img


def paste_centered(base, overlay, cx, cy):
    ox, oy = overlay.size
    x = int(cx - ox / 2)
    y = int(cy - oy / 2)
    base.paste(overlay, (x, y), overlay)


def draw_text_centered(draw, text, cx, cy, font, color):
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    draw.text((cx - tw / 2, cy - th / 2), text, fill=color, font=font)


def main():
    # Load assets
    bg = Image.open(RAW_DIR / "card_face_bg.png").convert("RGBA").resize((WORK_W, WORK_H), Image.LANCZOS)
    spade_raw = Image.open(RAW_DIR / "suit_spade.png").convert("RGBA")
    spade = tint_symbol(spade_raw, (30, 30, 30))

    font_large = load_font(52)

    # === Ace of Spades (full size 400x560) ===
    card = bg.copy()
    draw = ImageDraw.Draw(card)
    color = (30, 30, 30, 255)

    # Large centered spade
    big_pip = spade.resize((120, 120), Image.LANCZOS)
    paste_centered(card, big_pip, WORK_W // 2, WORK_H // 2)

    # Corner rank + small suit
    draw_text_centered(draw, "A", 40, 50, font_large, color)
    small_pip = spade.resize((30, 30), Image.LANCZOS)
    paste_centered(card, small_pip, 40, 90)
    draw_text_centered(draw, "A", WORK_W - 40, WORK_H - 50, font_large, color)
    paste_centered(card, small_pip, WORK_W - 40, WORK_H - 90)

    card = add_rounded_corners(card, radius=20)

    # Save full-size preview
    card.save(PREVIEW_DIR / "preview_ace_spades_400x560.png", "PNG")
    print(f"  Saved: {PREVIEW_DIR / 'preview_ace_spades_400x560.png'} (400x560)")

    # Save game-size preview
    final = card.resize((100, 140), Image.LANCZOS)
    final.save(PREVIEW_DIR / "preview_ace_spades_100x140.png", "PNG")
    print(f"  Saved: {PREVIEW_DIR / 'preview_ace_spades_100x140.png'} (100x140)")

    # === King of Hearts (with face portrait) ===
    card2 = bg.copy()
    draw2 = ImageDraw.Draw(card2)
    heart_raw = Image.open(RAW_DIR / "suit_heart.png").convert("RGBA")
    heart = tint_symbol(heart_raw, (180, 20, 20))
    king_portrait = Image.open(RAW_DIR / "face_king.png").convert("RGBA")
    red = (180, 20, 20, 255)

    # Place portrait in center
    portrait = king_portrait.resize((240, 320), Image.LANCZOS)
    paste_centered(card2, portrait, WORK_W // 2, WORK_H // 2)

    # Corner rank + suit
    draw_text_centered(draw2, "K", 40, 50, font_large, red)
    small_heart = heart.resize((30, 30), Image.LANCZOS)
    paste_centered(card2, small_heart, 40, 90)
    draw_text_centered(draw2, "K", WORK_W - 40, WORK_H - 50, font_large, red)
    paste_centered(card2, small_heart, WORK_W - 40, WORK_H - 90)

    card2 = add_rounded_corners(card2, radius=20)
    card2.save(PREVIEW_DIR / "preview_king_hearts_400x560.png", "PNG")
    print(f"  Saved: {PREVIEW_DIR / 'preview_king_hearts_400x560.png'} (400x560)")

    final2 = card2.resize((100, 140), Image.LANCZOS)
    final2.save(PREVIEW_DIR / "preview_king_hearts_100x140.png", "PNG")
    print(f"  Saved: {PREVIEW_DIR / 'preview_king_hearts_100x140.png'} (100x140)")

    # === Card back preview ===
    back = Image.open(RAW_DIR / "card_back.png").convert("RGBA").resize((WORK_W, WORK_H), Image.LANCZOS)
    back = add_rounded_corners(back, radius=20)
    back.save(PREVIEW_DIR / "preview_back_400x560.png", "PNG")
    print(f"  Saved: {PREVIEW_DIR / 'preview_back_400x560.png'} (400x560)")


if __name__ == "__main__":
    main()
