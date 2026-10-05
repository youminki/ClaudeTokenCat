#!/usr/bin/env python3
"""앱 아이콘(.icns)과 README 히어로 GIF 생성.

Swift PixelCat.runFrame과 동일한 18×11 도트 기하(무지개 트레일 포함)를 사용한다.
스프라이트 디자인을 바꾸면 이 스크립트도 함께 수정할 것.

사용: python3 scripts/generate-brand.py
산출: assets/AppIcon.icns, assets/tokencat-run.gif
"""
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets"

GRID_W, GRID_H = 18, 11
CAT = (235, 235, 240, 255)          # 다크 카드 위의 밝은 고양이
CARD = (23, 23, 26, 255)
RAINBOW = [(255, 70, 70, 255), (255, 160, 60, 255), (255, 225, 70, 255),
           (90, 205, 100, 255), (80, 150, 255, 255), (170, 100, 230, 255)]
LEG_POSES = [(4, 14), (5, 13), (7, 11), (6, 12)]   # Swift와 동일


def cat_rects(frame):
    """(x, y, w, h, color) 목록 — Swift PixelCat.runFrame(rainbowTrail: true) 복제."""
    pose = frame % 4
    bob = 1 if pose == 2 else 0
    wave = frame % 2
    rects = [(0, 2 + i + wave, 4 - wave, 1, c) for i, c in enumerate(RAINBOW)]
    rects += [
        (3, 2 + bob, 2, 1, CAT), (4, 3 + bob, 1, 1, CAT),      # 꼬리
        (5, 4 + bob, 9, 4, CAT),                                # 몸통
        (12, 2 + bob, 5, 4, CAT),                               # 머리
        (12, 1 + bob, 1, 1, CAT), (16, 1 + bob, 1, 1, CAT),     # 귀
    ]
    back, front = LEG_POSES[pose]
    rects += [(back, 8 + bob, 2, 2, CAT), (front, 8 + bob, 2, 2, CAT)]
    return rects


def render(frame, cell, canvas, offset):
    img = Image.new("RGBA", canvas, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox, oy = offset
    for x, y, w, h, color in cat_rects(frame):
        d.rectangle([ox + x * cell, oy + y * cell,
                     ox + (x + w) * cell - 1, oy + (y + h) * cell - 1], fill=color)
    return img


def make_gif():
    cell, pad = 12, 18
    size = (GRID_W * cell + pad * 2, GRID_H * cell + pad * 2)
    frames = []
    for i in range(8):
        frame = Image.new("RGBA", size, CARD)
        frame.alpha_composite(render(i, cell, size, (pad, pad)))
        frames.append(frame.convert("P", palette=Image.ADAPTIVE))
    frames[0].save(OUT / "tokencat-run.gif", save_all=True, append_images=frames[1:],
                   duration=70, loop=0, disposal=2)


def make_icns():
    # 1024 마스터: 둥근 사각 다크 카드 + 달리는 고양이(트레일 포함)
    master = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    d = ImageDraw.Draw(master)
    d.rounded_rectangle([64, 64, 960, 960], radius=180, fill=CARD)
    cell = 44
    ox = (1024 - GRID_W * cell) // 2
    oy = (1024 - GRID_H * cell) // 2 + 10
    master.alpha_composite(render(0, cell, (1024, 1024), (ox, oy)))

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                px = size * scale
                name = f"icon_{size}x{size}" + ("@2x" if scale == 2 else "") + ".png"
                master.resize((px, px), Image.NEAREST).save(iconset / name)
        subprocess.run(["iconutil", "-c", "icns", str(iconset),
                        "-o", str(OUT / "AppIcon.icns")], check=True)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    make_gif()
    make_icns()
    # 검수용 프리뷰
    render(0, 12, (GRID_W * 12 + 36, GRID_H * 12 + 36), (18, 18)).save("/tmp/preview_frame.png")
    print("✓ assets/tokencat-run.gif, assets/AppIcon.icns")
