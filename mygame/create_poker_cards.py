"""Generate polished playing card and chip images for a Texas Hold'em poker game."""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# --- Constants ---
CARD_W, CARD_H = 100, 140
CHIP_SIZE = 40
CORNER_R = 8
BORDER_COLOR = "#333333"
BORDER_W = 2

RED = "#CC0000"
DARK = "#222222"

SUITS = {"c": "clubs", "d": "diamonds", "h": "hearts", "s": "spades"}
SUIT_COLORS = {"c": DARK, "d": RED, "h": RED, "s": DARK}

# Unicode suit symbols
SUIT_SYMS = {"c": "\u2663", "d": "\u2666", "h": "\u2665", "s": "\u2660"}

RANKS = ["2", "3", "4", "5", "6", "7", "8", "9", "t", "j", "q", "k", "a"]
RANK_DISPLAY = {
    "2": "2", "3": "3", "4": "4", "5": "5", "6": "6",
    "7": "7", "8": "8", "9": "9", "t": "10",
    "j": "J", "q": "Q", "k": "K", "a": "A",
}

OUTPUT_DIR = Path("poker/assets/cards")
CHIP_DIR = Path("poker/assets")


# --- Font helpers ---
def _load_font(size):
    """Try to load a nice bold system font, fall back to default."""
    candidates = [
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFCompact.ttf",
        "/System/Library/Fonts/SFNSMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except (OSError, IOError):
            continue
    # Pillow built-in
    try:
        return ImageFont.truetype("DejaVuSans-Bold", size)
    except (OSError, IOError):
        return ImageFont.load_default()


def _load_bold_font(size):
    """Try to load a bold variant specifically."""
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/SFCompactText-Bold.otf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except (OSError, IOError):
            continue
    return _load_font(size)


# --- Drawing helpers ---
def _rounded_rect(draw, xy, radius, fill=None, outline=None, width=1):
    """Draw a rounded rectangle."""
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def _text_size(draw, text, font):
    """Get bounding box size for text."""
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def _draw_text_centered(draw, cx, cy, text, font, fill):
    """Draw text centered at (cx, cy)."""
    w, h = _text_size(draw, text, font)
    draw.text((cx - w / 2, cy - h / 2), text, font=font, fill=fill)


def _rotated_text(img, x, y, text, font, fill):
    """Draw 180-degree rotated text at position."""
    draw_tmp = ImageDraw.Draw(img)
    w, h = _text_size(draw_tmp, text, font)
    txt_img = Image.new("RGBA", (w + 4, h + 4), (0, 0, 0, 0))
    txt_draw = ImageDraw.Draw(txt_img)
    txt_draw.text((2, 2), text, font=font, fill=fill)
    txt_img = txt_img.rotate(180, expand=False)
    img.paste(txt_img, (int(x - w / 2), int(y - h / 2)), txt_img)


# --- Suit pip layout patterns (for number cards) ---
# Positions are fractions of the center area (0,0) to (1,1)
PIP_LAYOUTS = {
    2: [(0.5, 0.25), (0.5, 0.75)],
    3: [(0.5, 0.2), (0.5, 0.5), (0.5, 0.8)],
    4: [(0.35, 0.25), (0.65, 0.25), (0.35, 0.75), (0.65, 0.75)],
    5: [(0.35, 0.2), (0.65, 0.2), (0.5, 0.5), (0.35, 0.8), (0.65, 0.8)],
    6: [(0.35, 0.2), (0.65, 0.2), (0.35, 0.5), (0.65, 0.5), (0.35, 0.8), (0.65, 0.8)],
    7: [(0.35, 0.2), (0.65, 0.2), (0.5, 0.35), (0.35, 0.5), (0.65, 0.5), (0.35, 0.8), (0.65, 0.8)],
    8: [(0.35, 0.2), (0.65, 0.2), (0.5, 0.35), (0.35, 0.5), (0.65, 0.5), (0.5, 0.65), (0.35, 0.8), (0.65, 0.8)],
    9: [(0.35, 0.18), (0.65, 0.18), (0.35, 0.39), (0.65, 0.39), (0.5, 0.5),
        (0.35, 0.61), (0.65, 0.61), (0.35, 0.82), (0.65, 0.82)],
    10: [(0.35, 0.15), (0.65, 0.15), (0.5, 0.28), (0.35, 0.38), (0.65, 0.38),
         (0.35, 0.62), (0.65, 0.62), (0.5, 0.72), (0.35, 0.85), (0.65, 0.85)],
}


# --- Card generation ---
def create_card_face(rank, suit):
    """Create a single card face image."""
    img = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    color = SUIT_COLORS[suit]
    sym = SUIT_SYMS[suit]
    display = RANK_DISPLAY[rank]

    # Background with rounded corners
    _rounded_rect(draw, (0, 0, CARD_W - 1, CARD_H - 1), CORNER_R,
                   fill="white", outline=BORDER_COLOR, width=BORDER_W)

    # Fonts
    rank_font = _load_bold_font(16)
    small_suit_font = _load_font(11)
    pip_font = _load_font(16)
    big_sym_font = _load_font(36)
    face_letter_font = _load_bold_font(32)

    # --- Top-left corner: rank + suit ---
    rw, rh = _text_size(draw, display, rank_font)
    rx = 7
    ry = 6
    draw.text((rx, ry), display, font=rank_font, fill=color)
    sw, sh = _text_size(draw, sym, small_suit_font)
    draw.text((rx + (rw - sw) / 2, ry + rh + 0), sym, font=small_suit_font, fill=color)

    # --- Bottom-right corner: rank + suit (rotated 180) ---
    br_x = CARD_W - rx - rw / 2
    br_y = CARD_H - ry - rh / 2
    _rotated_text(img, br_x, br_y, display, rank_font, color)
    _rotated_text(img, br_x, br_y - rh - 1, sym, small_suit_font, color)

    # Re-acquire draw after pasting
    draw = ImageDraw.Draw(img)

    # --- Center area ---
    cx_left = 20
    cx_right = CARD_W - 20
    cy_top = 30
    cy_bottom = CARD_H - 30
    center_w = cx_right - cx_left
    center_h = cy_bottom - cy_top

    rank_num = {"2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9, "t": 10}.get(rank)

    if rank == "a":
        # Ace: one large suit symbol centered
        _draw_text_centered(draw, CARD_W / 2, CARD_H / 2, sym, big_sym_font, color)

    elif rank in ("j", "q", "k"):
        # Face cards: large letter with decorative suit symbols
        _draw_text_centered(draw, CARD_W / 2, CARD_H / 2 - 2, display, face_letter_font, color)
        # Small suit symbols as decoration
        deco_font = _load_font(13)
        _draw_text_centered(draw, CARD_W / 2, cy_top + 4, sym, deco_font, color)
        _draw_text_centered(draw, CARD_W / 2, cy_bottom - 4, sym, deco_font, color)
        _draw_text_centered(draw, cx_left + 4, CARD_H / 2, sym, deco_font, color)
        _draw_text_centered(draw, cx_right - 4, CARD_H / 2, sym, deco_font, color)

    elif rank_num is not None:
        # Number cards: arranged pip symbols
        positions = PIP_LAYOUTS.get(rank_num, [])
        for fx, fy in positions:
            px = cx_left + fx * center_w
            py = cy_top + fy * center_h
            _draw_text_centered(draw, px, py, sym, pip_font, color)

    return img


def create_card_back():
    """Create a card back image with decorative pattern."""
    img = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    bg_color = "#1B1B6F"
    gold = "#DAA520"

    # Background
    _rounded_rect(draw, (0, 0, CARD_W - 1, CARD_H - 1), CORNER_R,
                   fill=bg_color, outline=gold, width=2)

    # Inner border
    margin = 6
    _rounded_rect(draw, (margin, margin, CARD_W - 1 - margin, CARD_H - 1 - margin),
                   CORNER_R - 2, fill=None, outline=gold, width=1)

    # Diamond crosshatch pattern
    inner_l = margin + 4
    inner_t = margin + 4
    inner_r = CARD_W - 1 - margin - 4
    inner_b = CARD_H - 1 - margin - 4

    # Diagonal lines (top-left to bottom-right)
    step = 10
    for offset in range(-CARD_H, CARD_W + CARD_H, step):
        x0 = offset
        y0 = 0
        x1 = offset + CARD_H
        y1 = CARD_H
        # Clip to inner area
        pts = _clip_line_to_rect(x0, y0, x1, y1, inner_l, inner_t, inner_r, inner_b)
        if pts:
            draw.line(pts, fill=gold, width=1)

    # Diagonal lines (top-right to bottom-left)
    for offset in range(-CARD_H, CARD_W + CARD_H, step):
        x0 = offset + CARD_H
        y0 = 0
        x1 = offset
        y1 = CARD_H
        pts = _clip_line_to_rect(x0, y0, x1, y1, inner_l, inner_t, inner_r, inner_b)
        if pts:
            draw.line(pts, fill=gold, width=1)

    # Center diamond emblem
    cx, cy = CARD_W / 2, CARD_H / 2
    ds = 14
    diamond = [(cx, cy - ds), (cx + ds * 0.7, cy), (cx, cy + ds), (cx - ds * 0.7, cy)]
    draw.polygon(diamond, fill=bg_color, outline=gold)
    # Inner diamond
    ds2 = 8
    diamond2 = [(cx, cy - ds2), (cx + ds2 * 0.7, cy), (cx, cy + ds2), (cx - ds2 * 0.7, cy)]
    draw.polygon(diamond2, fill=gold, outline=gold)

    return img


def _clip_line_to_rect(x0, y0, x1, y1, rl, rt, rr, rb):
    """Simple line clipping to rectangle (Cohen-Sutherland style, simplified)."""
    # Just clamp endpoints for simplicity with diagonal lines
    if x1 == x0:
        return None
    dx = x1 - x0
    dy = y1 - y0

    t_min, t_max = 0.0, 1.0

    for edge_p, edge_q in [(-dx, x0 - rl), (dx, rr - x0), (-dy, y0 - rt), (dy, rb - y0)]:
        if edge_p == 0:
            if edge_q < 0:
                return None
        else:
            t = edge_q / edge_p
            if edge_p < 0:
                t_min = max(t_min, t)
            else:
                t_max = min(t_max, t)

    if t_min > t_max:
        return None

    cx0 = x0 + t_min * dx
    cy0 = y0 + t_min * dy
    cx1 = x0 + t_max * dx
    cy1 = y0 + t_max * dy
    return [(cx0, cy0), (cx1, cy1)]


# --- Chip generation ---
def create_chip(color_name, hex_color, value_text):
    """Create a poker chip image."""
    img = Image.new("RGBA", (CHIP_SIZE, CHIP_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx, cy = CHIP_SIZE / 2, CHIP_SIZE / 2
    r = CHIP_SIZE / 2 - 1

    # Outer circle
    draw.ellipse((1, 1, CHIP_SIZE - 2, CHIP_SIZE - 2), fill=hex_color, outline="#111111", width=1)

    # Inner ring
    inner_margin = 5
    draw.ellipse(
        (inner_margin, inner_margin, CHIP_SIZE - 1 - inner_margin, CHIP_SIZE - 1 - inner_margin),
        fill=None, outline="white", width=1,
    )

    # Edge notches / dashes
    num_notches = 16
    for i in range(num_notches):
        angle = 2 * math.pi * i / num_notches
        # Outer point
        ox = cx + (r - 0.5) * math.cos(angle)
        oy = cy + (r - 0.5) * math.sin(angle)
        # Inner point
        ix = cx + (r - 4) * math.cos(angle)
        iy = cy + (r - 4) * math.sin(angle)
        notch_color = "white" if i % 2 == 0 else hex_color
        draw.line([(ix, iy), (ox, oy)], fill=notch_color, width=2)

    # Re-draw center to cover notch overlap
    draw.ellipse(
        (inner_margin + 1, inner_margin + 1,
         CHIP_SIZE - 2 - inner_margin, CHIP_SIZE - 2 - inner_margin),
        fill=hex_color,
    )

    # Inner ring again
    draw.ellipse(
        (inner_margin, inner_margin, CHIP_SIZE - 1 - inner_margin, CHIP_SIZE - 1 - inner_margin),
        fill=None, outline="white", width=1,
    )

    # Value text
    font = _load_bold_font(10)
    text_color = "white" if color_name in ("blue", "black", "red") else "#333333"
    _draw_text_centered(draw, cx, cy, value_text, font, text_color)

    return img


# --- Main ---
def main():
    print("=" * 50)
    print("  Poker Card & Chip Generator")
    print("=" * 50)

    # Create output directories
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    CHIP_DIR.mkdir(parents=True, exist_ok=True)

    # Generate all 52 cards
    count = 0
    for suit in SUITS:
        for rank in RANKS:
            filename = f"{rank}{suit}.png"
            img = create_card_face(rank, suit)
            img.save(OUTPUT_DIR / filename)
            count += 1
            display = RANK_DISPLAY[rank]
            print(f"  [{count:2d}/53] {display} of {SUITS[suit]:8s} -> {filename}")

    # Card back
    img = create_card_back()
    img.save(OUTPUT_DIR / "back.png")
    count += 1
    print(f"  [{count:2d}/53] Card back          -> back.png")

    print(f"\nGenerated {count} card images in {OUTPUT_DIR}/")

    # Generate chips
    chips = [
        ("white", "#EEEEEE", "$10"),
        ("red", "#CC2222", "$50"),
        ("blue", "#2244AA", "$100"),
        ("black", "#222222", "$500"),
    ]

    print()
    for color_name, hex_color, value in chips:
        filename = f"chip_{color_name}.png"
        img = create_chip(color_name, hex_color, value)
        img.save(CHIP_DIR / filename)
        print(f"  Chip: {color_name:6s} ({value:>4s}) -> {filename}")

    print(f"\nGenerated {len(chips)} chip images in {CHIP_DIR}/")
    print("\nDone!")


if __name__ == "__main__":
    main()
