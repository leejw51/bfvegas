"""Generate polished MyWiki assets via Grok image generation.

Usage:
    GROK_API_KEY=... python scripts/generate_assets.py [bot|bg|logo|card|particle|all]

Reuses ../mygame/generate_image.py for the API call, then post-processes
with PIL via wiki_utils.
"""

import sys
import importlib.util
from pathlib import Path
from PIL import Image, ImageEnhance, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
ASSETS = ROOT / "assets"
MYGAME_GEN = ROOT.parent / "mygame" / "generate_image.py"

spec = importlib.util.spec_from_file_location("grok_gen", MYGAME_GEN)
grok_gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grok_gen)
# redirect raw downloads into our assets folder
grok_gen.OUTPUT_DIR = ASSETS / "raw"

sys.path.insert(0, str(HERE))
from wiki_utils import (
    round_corners,
    add_drop_shadow,
    remove_solid_bg,
    fit_square,
    save_png,
)


def fetch(prompt: str, slug: str) -> Path:
    print(f"\n→ generating {slug}")
    print(f"  prompt: {prompt[:110]}…")
    result, _ = grok_gen.generate_image(prompt)
    images = result.get("data", [])
    if not images:
        raise RuntimeError("no image returned")
    url = images[0]["url"]
    ext = url.rsplit(".", 1)[-1].split("?")[0] if "." in url else "jpeg"
    return grok_gen.download_image(url, f"{slug}.{ext}")


# ---------- prompts ----------

BOT_PROMPT = (
    "Adorable chibi robot mascot named Wiki, fresh redesign, sleek rounded "
    "helmet-shaped head with a glossy dark navy visor screen face showing "
    "two large sparkling cyan star-shaped eyes and a cheerful curved smile, "
    "two tiny antennas on top each tipped with a glowing magenta and cyan "
    "orb, soft pearlescent white and pastel lavender body with subtle holographic "
    "sheen, small rounded arms raised in a friendly wave, tiny floating base "
    "instead of legs with a soft cyan glow underneath, surrounded by a few "
    "tiny sparkle particles, big happy expression, centered, plain pure solid "
    "white background, studio lighting, high detail, premium vector-style "
    "clean lines, flat mascot character art, no text, no shadow"
)

BG_PROMPT = (
    "Ultra wide cinematic dark cosmic background, deep midnight navy and "
    "indigo gradient sky, swirling soft nebula clouds in cyan, magenta, and "
    "violet, faint distant stars, drifting glowing dust particles, subtle "
    "hexagonal energy grid lines barely visible, dreamy ethereal atmosphere, "
    "no characters, no text, no UI, no foreground objects, painterly, "
    "tileable seamless texture, very high detail, premium game background art, "
    "16:9 cinematic"
)

LOGO_PROMPT = (
    "Logo emblem for an app called 'MyWiki', a cute chibi robot mascot "
    "character, rounded helmet head with a glossy dark visor showing two big "
    "glowing cyan eyes and a happy smile, small antenna on top with a glowing "
    "magenta bulb, soft pastel white and lavender body, hugging a small "
    "glowing knowledge book with a cyan spark, surrounded by a soft circular "
    "neon cyan and magenta glow halo and tiny orbiting sparkle stars, premium "
    "game studio mascot logo, centered, isolated on pure solid white "
    "background, no text, no letters, highly polished vector style with "
    "subtle 3D depth, ultra crisp"
)

CARD_PROMPT = (
    "A single rounded rectangle UI card element for a game, glassmorphism style, "
    "deep navy translucent fill, bright neon cyan inner border with magenta "
    "outer glow, subtle holographic sheen across the surface, top edge has a "
    "thin glowing accent bar, viewed perfectly head-on, centered on pure solid "
    "white background, no text, no icons, no shadow on background, premium "
    "game UI element, ultra clean vector edges, high resolution"
)

PARTICLE_PROMPT = (
    "A single glowing soft round light orb particle, bright cyan core fading "
    "to magenta halo, sharp center, soft outer falloff, isolated on pure solid "
    "black background, no text, photographic bokeh light, centered, perfectly "
    "circular, premium game VFX particle"
)

GEAR_PROMPT = (
    "A single settings gear cog icon, glowing neon cyan with magenta inner "
    "highlights, premium game UI icon, clean vector silhouette, perfectly "
    "centered, isolated on pure solid white background, no text, no shadow, "
    "subtle 3D bevel, ultra crisp edges, high resolution"
)

SPARKLE_PROMPT = (
    "A single magical AI sparkle starburst icon, four-pointed star with "
    "smaller orbiting sparkles, glowing bright cyan core fading to magenta "
    "outer rays, premium game UI icon for an 'AI generate' button, "
    "centered, isolated on pure solid white background, no text, no shadow, "
    "ultra crisp vector style, high resolution"
)

INPUT_FIELD_PROMPT = (
    "A single horizontal rounded rectangle text input field UI element, "
    "glassmorphism style, deep navy translucent fill, glowing cyan inner "
    "border with subtle magenta outer glow, soft holographic sheen, "
    "premium game UI element, viewed perfectly head-on, centered on pure "
    "solid white background, no text, no icons, no cursor, clean vector "
    "edges, very wide aspect ratio, high resolution"
)

LOADER_PROMPT = (
    "A single circular loading spinner ring, glowing cyan and magenta neon "
    "gradient arc on a faint dark ring, soft outer glow, premium game UI "
    "loader element, centered, isolated on pure solid white background, "
    "no text, no shadow, perfectly circular, ultra crisp, high resolution"
)

SEND_BUTTON_PROMPT = (
    "A single circular send button icon with a paper plane silhouette inside, "
    "glowing neon cyan plane on a dark navy circular button with magenta rim "
    "glow, premium game UI element, centered, isolated on pure solid white "
    "background, no text, no shadow, ultra crisp vector style, high resolution"
)

TOOLBAR_PROMPT = (
    "A long horizontal glassmorphism toolbar bar UI element for a sci-fi game, "
    "deep navy translucent fill, glowing thin cyan top edge accent line, soft "
    "magenta outer glow, subtle holographic noise sheen, rounded corners, "
    "viewed perfectly head-on, centered on pure solid white background, no "
    "text, no icons, ultra wide aspect ratio, premium polished UI, high "
    "resolution, ultra crisp vector edges"
)

BUTTON_PROMPT = (
    "A single rounded rectangle game UI button, glassmorphism style, deep navy "
    "translucent fill, glowing cyan inner border, soft magenta outer glow, "
    "subtle holographic sheen, viewed perfectly head-on, centered on pure "
    "solid white background, no text, no icons, premium polished game UI, "
    "ultra crisp vector edges, high resolution"
)

DIVIDER_PROMPT = (
    "A single thin vertical glowing divider line, neon cyan core fading to "
    "magenta halo, soft outer falloff at top and bottom, isolated on pure "
    "solid white background, no text, premium game UI separator, perfectly "
    "vertical, ultra crisp, high resolution"
)

BADGE_PROMPT = (
    "A single small circular notification badge, glowing neon magenta gradient "
    "fill with cyan rim glow, subtle 3D bevel, centered, isolated on pure "
    "solid white background, no text, no shadow, premium game UI element, "
    "ultra crisp, high resolution"
)


# ---------- post-processing ----------


def make_bot():
    p = fetch(BOT_PROMPT, "bot")
    img = Image.open(p)
    img = remove_solid_bg(img, tolerance=32)
    img = fit_square(img, 720)
    img = ImageEnhance.Color(img).enhance(1.15)
    img = ImageEnhance.Contrast(img).enhance(1.10)
    save_png(img, ASSETS / "bot.png")


def make_bg():
    p = fetch(BG_PROMPT, "bg")
    img = Image.open(p).convert("RGBA")
    # gentle darken + saturation boost so UI stays readable but feels rich
    overlay = Image.new("RGBA", img.size, (4, 6, 14, 90))
    img = Image.alpha_composite(img, overlay)
    img = ImageEnhance.Color(img).enhance(1.20)
    img = ImageEnhance.Contrast(img).enhance(1.05)
    img = img.resize((1920, 1080), Image.LANCZOS)
    save_png(img, ASSETS / "bg.png")


def make_logo():
    p = fetch(LOGO_PROMPT, "logo")
    img = Image.open(p)
    img = remove_solid_bg(img, tolerance=30)
    img = fit_square(img, 512)
    img = ImageEnhance.Color(img).enhance(1.20)
    save_png(img, ASSETS / "logo.png")


def make_card():
    p = fetch(CARD_PROMPT, "card")
    img = Image.open(p)
    img = remove_solid_bg(img, tolerance=28)
    save_png(img, ASSETS / "node_card.png")


def make_particle():
    p = fetch(PARTICLE_PROMPT, "particle")
    img = Image.open(p).convert("RGBA")
    # treat the black bg as transparent: make alpha = brightness
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            a = max(r, g, b)
            px[x, y] = (r, g, b, a)
    img = fit_square(img, 256)
    save_png(img, ASSETS / "particle.png")


def _icon(prompt, slug, out_name, size=256, tolerance=30, saturate=1.15):
    p = fetch(prompt, slug)
    img = Image.open(p)
    img = remove_solid_bg(img, tolerance=tolerance)
    img = fit_square(img, size)
    img = ImageEnhance.Color(img).enhance(saturate)
    save_png(img, ASSETS / out_name)


def make_gear():
    _icon(GEAR_PROMPT, "gear", "gear.png")


def make_sparkle():
    _icon(SPARKLE_PROMPT, "sparkle", "sparkle.png", saturate=1.25)


def make_loader():
    _icon(LOADER_PROMPT, "loader", "loader.png", saturate=1.20)


def make_send():
    _icon(SEND_BUTTON_PROMPT, "send", "send.png")


def make_toolbar():
    p = fetch(TOOLBAR_PROMPT, "toolbar")
    img = Image.open(p)
    img = remove_solid_bg(img, tolerance=28)
    save_png(img, ASSETS / "toolbar.png")


def make_button():
    p = fetch(BUTTON_PROMPT, "button")
    img = Image.open(p)
    img = remove_solid_bg(img, tolerance=28)
    save_png(img, ASSETS / "button.png")


def make_divider():
    _icon(DIVIDER_PROMPT, "divider", "divider.png", size=128, saturate=1.20)


def make_badge():
    _icon(BADGE_PROMPT, "badge", "badge.png", size=128, saturate=1.20)


def make_input_field():
    p = fetch(INPUT_FIELD_PROMPT, "input_field")
    img = Image.open(p)
    img = remove_solid_bg(img, tolerance=28)
    save_png(img, ASSETS / "input_field.png")


TASKS = {
    "bot": make_bot,
    "bg": make_bg,
    "logo": make_logo,
    "card": make_card,
    "particle": make_particle,
    "gear": make_gear,
    "sparkle": make_sparkle,
    "loader": make_loader,
    "send": make_send,
    "input_field": make_input_field,
    "toolbar": make_toolbar,
    "button": make_button,
    "divider": make_divider,
    "badge": make_badge,
}


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "all"
    ASSETS.mkdir(parents=True, exist_ok=True)
    targets = list(TASKS.keys()) if target == "all" else [target]
    for name in targets:
        if name not in TASKS:
            print(f"unknown target: {name}. options: {', '.join(TASKS)} | all")
            continue
        try:
            TASKS[name]()
        except Exception as e:
            print(f"  ! failed {name}: {e}")
    print("\nDone.")


if __name__ == "__main__":
    main()
