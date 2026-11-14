"""从同一份几何原稿生成应用内标识与多尺寸 Windows 图标。"""

from pathlib import Path

from PIL import Image, ImageDraw


# 项目根目录按脚本路径解析，不依赖调用方当前目录。
ROOT = Path(__file__).resolve().parents[1]
# 超采样倍率，先高分辨率绘制再缩小，以减少小图锯齿。
SCALE = 4
# 最终应用内 PNG 的边长，单位像素。
SIDE = 512


# 把基准几何坐标乘以超采样倍率，所有图形尺寸统一换算。
def box(*values: int) -> tuple[int, ...]:
    return tuple(value * SCALE for value in values)


# 在透明高分辨率画布绘制独立图标原稿，再用 Lanczos 缩成最终 PNG 图。
def draw_icon() -> Image.Image:
    canvas = Image.new("RGBA", (SIDE * SCALE, SIDE * SCALE), (0, 0, 0, 0))
    background = Image.new("RGBA", canvas.size)
    background_pixels = background.load()
    for y in range(background.height):
        ratio = y / (background.height - 1)
        for x in range(background.width):
            sideways = x / (background.width - 1)
            blend = min(1.0, 0.65 * ratio + 0.35 * sideways)
            background_pixels[x, y] = (
                round(44 + 52 * blend),
                round(54 + 62 * blend),
                round(122 + 90 * blend),
                255,
            )
    mask = Image.new("L", canvas.size)
    ImageDraw.Draw(mask).rounded_rectangle(box(8, 8, 504, 504), radius=112 * SCALE, fill=255)
    canvas.paste(background, (0, 0), mask)

    art = ImageDraw.Draw(canvas)
    # 纸张和背景间留一层浅阴影，小尺寸图标也能看清轮廓。
    art.rounded_rectangle(box(151, 111, 372, 426), radius=32 * SCALE, fill=(24, 34, 91, 58))
    art.rounded_rectangle(box(141, 99, 362, 414), radius=32 * SCALE, fill=(248, 249, 255, 255))
    art.polygon([box(301, 99), box(362, 160), box(301, 160)], fill=(215, 223, 255, 255))
    art.line([box(301, 99), box(301, 160), box(362, 160)], fill=(181, 195, 245, 255), width=3 * SCALE)

    for y, right in ((207, 316), (241, 294), (275, 275)):
        art.rounded_rectangle(box(177, y, right, y + 7), radius=4 * SCALE, fill=(211, 217, 240, 255))

    # 墨迹两端画圆，缩到 16px 时仍保持连续。
    stroke = [(180, 322), (208, 347), (231, 365), (258, 331), (291, 289), (328, 253)]
    scaled = [box(x, y) for x, y in stroke]
    art.line(scaled, fill=(21, 167, 157, 255), width=37 * SCALE, joint="curve")
    for x, y in (stroke[0], stroke[-1]):
        art.ellipse(box(x - 18, y - 18, x + 18, y + 18), fill=(21, 167, 157, 255))
    art.line(scaled, fill=(45, 215, 183, 255), width=26 * SCALE, joint="curve")
    for x, y in (stroke[0], stroke[-1]):
        art.ellipse(box(x - 13, y - 13, x + 13, y + 13), fill=(45, 215, 183, 255))

    return canvas.resize((SIDE, SIDE), Image.Resampling.LANCZOS)


# 生成应用内 PNG 和多尺寸 Windows ICO；只运行脚本时才写入目标资源，注释整理不会重生成。
def main() -> None:
    icon = draw_icon()
    assets = ROOT / "assets"
    assets.mkdir(exist_ok=True)
    icon.save(assets / "fastink_icon.png", optimize=True)
    icon.save(
        ROOT / "windows" / "runner" / "resources" / "app_icon.ico",
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


if __name__ == "__main__":
    main()
