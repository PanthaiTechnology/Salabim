"""Gera os assets obrigatórios da ficha da loja (Play Console) a partir dos
assets de marca já existentes em mobile/assets/icons/ — ver STORE_PUBLISHING.md.

- Ícone do app: exatamente 512x512px (Play exige esse tamanho exato)
- Feature graphic: exatamente 1024x500px (banner do topo da ficha da loja)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ICONS_DIR = ROOT / "mobile" / "assets" / "icons"
OUT_DIR = ROOT / "devops" / "assets" / "store"
OUT_DIR.mkdir(parents=True, exist_ok=True)

BG = (11, 7, 20, 255)  # AppColors.background #0B0714
PRIMARY = (124, 77, 255, 255)  # AppColors.primary #7C4DFF


def make_icon() -> None:
    src = Image.open(ICONS_DIR / "salabim_icon.png").convert("RGBA")
    # Redimensiona mantendo proporção, depois centraliza num canvas 512x512
    # exato (o ícone original não é perfeitamente quadrado: 465x466).
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    src_resized = src.resize((512, int(512 * src.height / src.width)), Image.LANCZOS)
    if src_resized.height > 512:
        src_resized = src.resize((int(512 * src.width / src.height), 512), Image.LANCZOS)
    x = (512 - src_resized.width) // 2
    y = (512 - src_resized.height) // 2
    canvas.paste(src_resized, (x, y), src_resized)
    canvas.save(OUT_DIR / "icon_512.png")
    print("icon_512.png ok", canvas.size)


def _find_font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        "C:/Windows/Fonts/segoeuib.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def make_feature_graphic() -> None:
    W, H = 1024, 500
    canvas = Image.new("RGB", (W, H), BG[:3])
    draw = ImageDraw.Draw(canvas)

    # Gradiente radial sutil atrás do ícone, ecoando o gradiente da marca
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    cx, cy = 230, H // 2
    for r in range(320, 0, -4):
        alpha = int(70 * (1 - r / 320))
        glow_draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*PRIMARY[:3], alpha))
    canvas.paste(Image.alpha_composite(Image.new("RGBA", (W, H), (*BG[:3], 255)), glow).convert("RGB"), (0, 0))

    # Ícone à esquerda
    icon = Image.open(OUT_DIR / "icon_512.png").convert("RGBA")
    icon_size = 340
    icon_resized = icon.resize((icon_size, icon_size), Image.LANCZOS)
    icon_x, icon_y = 60, (H - icon_size) // 2
    canvas.paste(icon_resized, (icon_x, icon_y), icon_resized)

    # Wordmark + tagline à direita
    title_font = _find_font(96)
    tagline_font = _find_font(34)
    text_x = icon_x + icon_size + 50

    draw.text((text_x, H // 2 - 90), "Salabim", font=title_font, fill=(242, 238, 249, 255))
    draw.text(
        (text_x, H // 2 + 30),
        "Ouça, cante ou descreva.\nDescubra a música na hora.",
        font=tagline_font,
        fill=(184, 173, 201, 255),
        spacing=10,
    )

    canvas.save(OUT_DIR / "feature_graphic_1024x500.png")
    print("feature_graphic_1024x500.png ok", canvas.size)


if __name__ == "__main__":
    make_icon()
    make_feature_graphic()
