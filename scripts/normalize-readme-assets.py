#!/usr/bin/env python3
"""把 README 功能截图渲染成官网风格的卡片图。

为什么需要这一步：`features/` 下 11 张截图的原始宽高比从 0.63（竖版菜单栏面板）
到 2.10（横版横幅）不等，直接塞进等宽表格会让竖版图被压成 126px 宽的细条。
统一到同一块画布后，网格里每一格形状一致，图片能拿到完整列宽。

为什么用 Chrome 而不是 PIL 合成：卡片要放彩色 emoji 图标，PIL 只能加载
Apple Color Emoji 却无法渲染彩色字形（会画成空白）。Chrome 直接复用系统 emoji 字体
与官网那套卡片 CSS，一次拿到渐变、圆角、描边、投影与 CJK 字体。

约定：
- `features/` 是原始截图（源），本脚本只读不改；重新截图后覆盖 `features/` 里的文件再跑一次即可。
- `cards/` 是生成物，README 只引用 `cards/`。生成物入库是因为 GitHub 直接从仓库渲染 README。
- 脚本必须可重复执行：每次从 `features/` 重新生成，不在自己的输出上再加工。
"""

import html
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / ".github" / "assets" / "features"
OUT_DIR = ROOT / ".github" / "assets" / "cards"

CHROME = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

# 卡片按 CSS 像素排版，再用 2 倍设备像素比截屏，得到 Retina 下不放大即可铺满的图。
CARD_W, CARD_H = 480, 620
SCALE = 2
COLUMNS = 4

# 每张图的处理方式与圆角半径（半径按源图自身的像素尺度给）：
#   alpha —— 已带透明通道与烘焙投影，裁到不透明边界即可，不再补投影
#   white —— 纯白底，先裁掉白边再自己补圆角与投影
#   none  —— 不透明且底色就是窗口自身，只能整张圆角 + 补投影
# alpha 模式的图圆角已烘焙在图里，半径填 0 即可，重复施加反而会切进窗口本体。
MODES = {
    "2fa": ("alpha", 0),
    "cleaning-mode": ("white", 14),
    "clipboard": ("none", 18),
    "dropzone": ("alpha", 0),
    "funds": ("none", 10),
    "keep-awake": ("alpha", 0),
    "launcher": ("alpha", 0),
    "memos": ("alpha", 0),
    "mindfulness": ("alpha", 0),
    "pet-companion": ("alpha", 0),
    "system-monitor": ("alpha", 0),
}

# 图标与主题色。色值取自官网 `index.html` 的 accent 调色板，每张卡一个色，
# 与卡片左上角的图标徽章共用（徽章底色 12%、描边 30%，即官网 `--badge-bg` / `--badge-border` 的比例）。
FEATURES = [
    ("clipboard", "📋", "#0284c7"),
    ("memos", "📝", "#6366f1"),
    ("launcher", "🚀", "#ea580c"),
    ("dropzone", "📁", "#0ea5e9"),
    ("2fa", "🔐", "#7c3aed"),
    ("system-monitor", "📊", "#14b8a6"),
    ("keep-awake", "☕", "#10b981"),
    ("cleaning-mode", "⌨️", "#06b6d4"),
    ("funds", "📈", "#f43f5e"),
    ("pet-companion", "🐱", "#f59e0b"),
    ("mindfulness", "🧘", "#d946ef"),
]

SHADOW_BLUR = 22
SHADOW_ALPHA = 90


def trim_to_alpha(im: Image.Image) -> Image.Image:
    """裁到不透明边界。投影本身有 alpha，所以裁出来的是含投影的视觉范围。"""
    mask = im.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    box = mask.getbbox()
    return im.crop(box) if box else im


def trim_white(im: Image.Image, threshold: int = 246) -> Image.Image:
    mask = im.convert("RGB").point(lambda v: 0 if v >= threshold else 255).convert("L")
    box = mask.getbbox()
    return im.crop(box) if box else im


def round_corners(im: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, im.size[0] - 1, im.size[1] - 1], radius=radius, fill=255
    )
    out = im.copy()
    out.putalpha(mask)
    return out


def preprocess(name: str, dest: Path) -> None:
    """裁掉源图多余的透明/白色边距，让它在卡片里占满可用区域。"""
    im = Image.open(SRC_DIR / f"{name}.png").convert("RGBA")
    mode, radius = MODES[name]

    if mode == "alpha":
        im = trim_to_alpha(im)
    elif mode == "white":
        im = round_corners(trim_white(im), radius)
    else:
        im = round_corners(im, radius)

    im.save(dest / f"{name}.png")


def card_html(name: str, emoji: str, accent: str, src: Path) -> str:
    return f"""
<div class="card" style="--accent:{accent}">
  <div class="badge">{emoji}</div>
  <div class="shot"><img src="{src.as_uri()}" alt=""></div>
</div>"""


def page_html(prepared: Path) -> str:
    cards = "".join(
        card_html(name, emoji, accent, prepared / f"{name}.png")
        for name, emoji, accent in FEATURES
    )
    return f"""<!doctype html><meta charset="utf-8">
<style>
  /* 卡片配方取自官网 `index.html` 的 .feature-card / .feature-icon-badge（浅色主题）。 */
  * {{ box-sizing: border-box; }}
  html, body {{ margin: 0; padding: 0; background: transparent; }}
  .grid {{
    display: grid;
    grid-template-columns: repeat({COLUMNS}, {CARD_W}px);
    width: {CARD_W * COLUMNS}px;
    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
  }}
  .card {{
    width: {CARD_W}px; height: {CARD_H}px;
    padding: 24px;
    display: flex; flex-direction: column; gap: 16px;
    background: #ffffff;
    border: 1px solid rgba(15, 23, 42, 0.08);
    border-radius: 20px;
    box-shadow: 0 10px 30px rgba(15, 23, 42, 0.05);
    overflow: hidden;
  }}
  .badge {{
    flex: none;
    width: 48px; height: 48px; border-radius: 14px;
    display: flex; align-items: center; justify-content: center;
    font-size: 24px; line-height: 1;
    background: color-mix(in srgb, var(--accent) 12%, transparent);
    border: 1px solid color-mix(in srgb, var(--accent) 30%, transparent);
  }}
  /* 截图垫一层极淡的主题色，让浅色界面（剪贴板、中转站）不至于糊在白卡上。 */
  .shot {{
    flex: 1; min-height: 0;
    padding: 14px;
    display: flex; align-items: center; justify-content: center;
    border-radius: 14px;
    background: color-mix(in srgb, var(--accent) 5%, transparent);
  }}
  .shot img {{ max-width: 100%; max-height: 100%; }}
</style>
<div class="grid">{cards}
</div>"""


def render(page: Path, out: Path) -> None:
    rows = -(-len(FEATURES) // COLUMNS)
    subprocess.run(
        [
            str(CHROME),
            "--headless",
            "--disable-gpu",
            "--hide-scrollbars",
            # 透明底：卡片圆角外留空，嵌进 README 后由表格单元格的底色透出来。
            "--default-background-color=00000000",
            f"--force-device-scale-factor={SCALE}",
            f"--window-size={CARD_W * COLUMNS},{CARD_H * rows}",
            f"--screenshot={out}",
            "--virtual-time-budget=5000",
            page.as_uri(),
        ],
        check=True,
        capture_output=True,
    )


def main() -> None:
    if not CHROME.exists():
        raise SystemExit(f"找不到 Chrome：{CHROME}")

    missing = [n for n, _, _ in FEATURES if not (SRC_DIR / f"{n}.png").exists()]
    if missing:
        raise SystemExit(f"features/ 缺少源图：{', '.join(missing)}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        for name, _, _ in FEATURES:
            preprocess(name, tmp_dir)

        page = tmp_dir / "cards.html"
        page.write_text(page_html(tmp_dir), encoding="utf-8")

        sheet = tmp_dir / "sheet.png"
        render(page, sheet)

        # 一页排下所有卡片再按格子裁切，比逐张起 Chrome 快一个数量级。
        board = Image.open(sheet).convert("RGBA")
        for index, (name, _, _) in enumerate(FEATURES):
            col, row = index % COLUMNS, index // COLUMNS
            tile = board.crop(
                (
                    col * CARD_W * SCALE,
                    row * CARD_H * SCALE,
                    (col + 1) * CARD_W * SCALE,
                    (row + 1) * CARD_H * SCALE,
                )
            )
            tile.save(OUT_DIR / f"{name}.png", optimize=True)
            print(f"{name:18} {tile.size[0]}x{tile.size[1]}")


if __name__ == "__main__":
    main()
