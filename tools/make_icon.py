"""釣りとも！アプリアイコン生成スクリプト。

以前の「犬とも」では提供された画像を加工したが、今回はソース画像なしで
Pillow の描画機能のみで釣りテーマのアプリアイコン（1024px）を作る。
生成物:
- app/assets/icon/app_icon.png          （flutter_launcher_icons のソース）
- app/web/icons/Icon-*.png             （PWA アイコン）
- app/web/favicon.png
- app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png

アイコンは「海の青背景 + 白い魚」のシンプルな構成。マスカラブル
アイコンでも発言内容が切れないよう、図形は中央 80% 内に収める。
"""
from PIL import Image, ImageDraw

SIZE = 1024

# 海の青（テーマ色 #0277BD 系）
TOP = (1, 87, 155)      # #01579B
BOTTOM = (41, 182, 246)  # #29B6F6


def gradient(size):
    im = Image.new("RGB", (size, size))
    for y in range(size):
        t = y / (size - 1)
        r = round(TOP[0] + (BOTTOM[0] - TOP[0]) * t)
        g = round(TOP[1] + (BOTTOM[1] - TOP[1]) * t)
        b = round(TOP[2] + (BOTTOM[2] - TOP[2]) * t)
        for x in range(size):
            im.putpixel((x, y), (r, g, b))
    return im


def draw_fish(base):
    d = ImageDraw.Draw(base)
    white = (255, 255, 255)
    dark = (1, 87, 155)
    cx, cy = 512, 500

    # 尾びれ（左向きの三角形）
    d.polygon([(cx - 210, cy), (cx - 390, cy - 170), (cx - 390, cy + 170)],
              fill=white)
    # 体（楕円）
    d.ellipse([(cx - 230, cy - 150), (cx + 290, cy + 150)], fill=white)
    # 背びれ
    d.polygon([(cx - 90, cy - 140), (cx + 60, cy - 140), (cx + 30, cy - 240)],
              fill=white)
    # 腹びれ
    d.polygon([(cx - 60, cy + 140), (cx + 70, cy + 140), (cx + 40, cy + 230)],
              fill=white)
    # 目
    eye_r = 36
    d.ellipse([(cx + 170 - eye_r, cy - 40 - eye_r),
               (cx + 170 + eye_r, cy - 40 + eye_r)], fill=dark)
    # えら（弧の代わりに細い楕円線）
    d.arc([(cx + 60, cy - 120), (cx + 140, cy + 120)], 100, 260,
          fill=dark, width=14)
    # 波（下部に2本）
    wave = (129, 212, 250)
    for i, y in enumerate((810, 860)):
        pts = []
        x = 0
        while x <= SIZE:
            import math
            yoff = 34 * math.sin(x / 92.0 + i * 1.7)
            pts.append((x, y + yoff))
            x += 8
        d.line(pts, fill=wave, width=26)
    return base


def main():
    icon = draw_fish(gradient(SIZE))
    icon.save("app/assets/icon/app_icon.png")

    # Web（PWA）アイコン
    for name, size in (("Icon-192.png", 192), ("Icon-512.png", 512),
                       ("Icon-maskable-192.png", 192),
                       ("Icon-maskable-512.png", 512)):
        icon.resize((size, size), Image.LANCZOS).save(
            f"app/web/icons/{name}")
    icon.resize((64, 64), Image.LANCZOS).save("app/web/favicon.png")

    # iOS AppIcon
    for name, size in (("Icon-App-20x20@1x.png", 20),
                       ("Icon-App-20x20@2x.png", 40),
                       ("Icon-App-20x20@3x.png", 60),
                       ("Icon-App-29x29@1x.png", 29),
                       ("Icon-App-29x29@2x.png", 58),
                       ("Icon-App-29x29@3x.png", 87),
                       ("Icon-App-40x40@1x.png", 40),
                       ("Icon-App-40x40@2x.png", 80),
                       ("Icon-App-40x40@3x.png", 120),
                       ("Icon-App-50x50@1x.png", 50),
                       ("Icon-App-50x50@2x.png", 100),
                       ("Icon-App-50x50@3x.png", 150),
                       ("Icon-App-57x57@1x.png", 57),
                       ("Icon-App-57x57@2x.png", 114),
                       ("Icon-App-60x60@2x.png", 120),
                       ("Icon-App-60x60@3x.png", 180),
                       ("Icon-App-72x72@1x.png", 72),
                       ("Icon-App-72x72@2x.png", 144),
                       ("Icon-App-76x76@1x.png", 76),
                       ("Icon-App-76x76@2x.png", 152),
                       ("Icon-App-83.5x83.5@1x.png", 167),
                       ("Icon-App-83.5x83.5@2x.png", 334),
                       ("Icon-App-1024x1024@1x.png", 1024)):
        icon.resize((size, size), Image.LANCZOS).save(
            "app/ios/Runner/Assets.xcassets/AppIcon.appiconset/" + name)
    print("icon generated")


if __name__ == "__main__":
    main()
