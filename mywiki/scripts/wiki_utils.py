"""Image utilities for MyWiki - rounded corners, shadows, transparent bg, tiling."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops


def rounded_mask(size, radius):
    """Return an L-mode mask with rounded corners."""
    w, h = size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
    return mask


def round_corners(img: Image.Image, radius: int) -> Image.Image:
    img = img.convert("RGBA")
    mask = rounded_mask(img.size, radius)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def add_drop_shadow(img: Image.Image, offset=(0, 8), blur=18, opacity=140) -> Image.Image:
    img = img.convert("RGBA")
    w, h = img.size
    pad = blur * 2 + max(abs(offset[0]), abs(offset[1]))
    canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    alpha = img.split()[-1]
    shadow.paste((0, 0, 0, opacity), (pad + offset[0], pad + offset[1]), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(img, (pad, pad))
    return canvas


def remove_solid_bg(img: Image.Image, tolerance: int = 24) -> Image.Image:
    """Best-effort: remove a near-uniform background color (sampled from corners)."""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    samples = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    r = sum(s[0] for s in samples) // 4
    g = sum(s[1] for s in samples) // 4
    b = sum(s[2] for s in samples) // 4
    out = img.copy()
    op = out.load()
    for y in range(h):
        for x in range(w):
            cr, cg, cb, ca = op[x, y]
            if abs(cr - r) <= tolerance and abs(cg - g) <= tolerance and abs(cb - b) <= tolerance:
                op[x, y] = (cr, cg, cb, 0)
    return out


def fit_square(img: Image.Image, size: int) -> Image.Image:
    img = img.convert("RGBA")
    w, h = img.size
    s = max(w, h)
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    canvas.paste(img, ((s - w) // 2, (s - h) // 2), img)
    return canvas.resize((size, size), Image.LANCZOS)


def tint(img: Image.Image, color, strength: float = 0.35) -> Image.Image:
    img = img.convert("RGBA")
    overlay = Image.new("RGBA", img.size, color + (int(255 * strength),))
    return Image.alpha_composite(img, overlay)


def save_png(img: Image.Image, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")
    print(f"  saved: {path}")
