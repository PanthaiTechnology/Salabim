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
    # Fundo escuro sólido (não transparente) preenchendo o quadrado
    # inteiro 512x512 — a Play Store aplica a própria máscara (círculo,
    # squircle etc. conforme o launcher do aparelho) por cima, então o
    # ideal é entregar um quadrado cheio, não um ícone já arredondado.
    canvas = Image.new("RGBA", (512, 512), BG)
    # Uma margem em volta do círculo do bruxo, do jeito que aparece no
    # mockup de referência — não cola o círculo direto na borda.
    target = int(512 * 0.82)
    src_resized = src.resize((target, int(target * src.height / src.width)), Image.LANCZOS)
    if src_resized.height > target:
        src_resized = src.resize((int(target * src.width / src.height), target), Image.LANCZOS)
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
    """Pedido do usuário: usar o lockup (ícone + wordmark) já pronto,
    só redimensionado PROPORCIONALMENTE pra caber em 1024x500 — sem
    esticar/distorcer. A proporção do lockup original (1434x466, ~3.08:1)
    é mais larga que o canvas (1024x500, 2.05:1), então escala pela
    largura e centraliza verticalmente, preenchendo a sobra com o mesmo
    fundo escuro do próprio lockup (sem costura visível)."""
    W, H = 1024, 500
    MARGIN = 0.72  # a logo ocupa até 72% da largura/altura do canvas — sobra respiro nas bordas
    lockup = Image.open(ICONS_DIR / "salabim_logo_lockup.png").convert("RGBA")

    max_w, max_h = W * MARGIN, H * MARGIN
    scale = max_w / lockup.width
    new_size = (round(max_w), round(lockup.height * scale))
    if new_size[1] > max_h:
        scale = max_h / lockup.height
        new_size = (round(lockup.width * scale), round(max_h))
    resized = lockup.resize(new_size, Image.LANCZOS)

    canvas = Image.new("RGBA", (W, H), BG)
    x = (W - resized.width) // 2
    y = (H - resized.height) // 2
    canvas.paste(resized, (x, y), resized)

    canvas.convert("RGB").save(OUT_DIR / "feature_graphic_1024x500.png")
    print("feature_graphic_1024x500.png ok", canvas.size, "logo em", new_size)


if __name__ == "__main__":
    make_icon()
    make_feature_graphic()
