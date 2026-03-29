#!/usr/bin/env python3
"""
composite.py — Composite raw window screenshots over aurora background
for App Store submission (2560 x 1600 px, Retina 13").

Usage:
    python3 composite.py \
        --raw-dir docs/assets/screenshots/raw \
        --output-dir docs/assets/screenshots \
        --background docs/assets/screenshot_bck.png \
        --punchlines "1|text|0|0\n..."
"""

import argparse
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageStat
except ImportError:
    print("Error: Pillow is required. Install with: pip3 install Pillow")
    sys.exit(1)


# --- Constants ---
CANVAS_WIDTH = 2560
CANVAS_HEIGHT = 1600
WINDOW_SCALE = 0.48
WINDOW_Y_FRACTION = 0.15
SHADOW_RADIUS = 30
SHADOW_OFFSET_Y = 12
SHADOW_OPACITY = 100
CORNER_RADIUS = 10

# Text styling
HEADLINE_FONT_SIZE = 88
HEADLINE_Y_FRACTION = 0.055
TEXT_COLOR = (255, 255, 255)
TEXT_SHADOW_COLOR = (0, 0, 0, 200)
TEXT_SHADOW_BLUR = 8

# Window glow for dark-theme shots
DARK_GLOW_RADIUS = 50
DARK_GLOW_OPACITY = 50
DARK_GLOW_COLOR = (80, 180, 140)


def find_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    """Find the best available font for text rendering."""
    if bold:
        font_paths = [
            "/Library/Fonts/SF-Pro-Display-Bold.otf",
            "/Library/Fonts/SF-Pro-Display-Semibold.otf",
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/SF-Pro.ttf",
            "/System/Library/Fonts/HelveticaNeue.ttc",
        ]
    else:
        font_paths = [
            "/Library/Fonts/SF-Pro-Display-Medium.otf",
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/SF-Pro.ttf",
            "/System/Library/Fonts/HelveticaNeue.ttc",
        ]
    for path in font_paths:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except (OSError, Exception):
                continue
    print("Warning: No system font found, using default")
    return ImageFont.load_default()


def create_drop_shadow(image: Image.Image, radius: int, offset_y: int,
                       opacity: int) -> Image.Image:
    padding = radius * 4
    shadow = Image.new("RGBA", (
        image.width + padding, image.height + padding
    ), (0, 0, 0, 0))
    shadow_rect = Image.new("RGBA", image.size, (0, 0, 0, opacity))
    shadow.paste(shadow_rect, (padding // 2, padding // 2 + offset_y))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=radius))
    return shadow


def create_window_glow(width: int, height: int, radius: int,
                       opacity: int, color: tuple) -> Image.Image:
    padding = radius * 4
    glow = Image.new("RGBA", (width + padding, height + padding), (0, 0, 0, 0))
    glow_rect = Image.new("RGBA", (width, height), (*color, opacity))
    glow.paste(glow_rect, (padding // 2, padding // 2))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=radius))
    return glow


def add_rounded_corners(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        [(0, 0), (image.width - 1, image.height - 1)],
        radius=radius, fill=255
    )
    result = image.copy()
    result.putalpha(mask)
    return result


def find_dialog_region(image: Image.Image) -> tuple:
    """Find the dialog sheet region in a window screenshot.

    The dialog is the brightest/most-contrasted rectangular region
    in the center of an otherwise dimmed window. We scan for rows/columns
    where pixel brightness jumps significantly.
    """
    gray = image.convert("L")
    width, height = gray.size

    # Scan horizontal brightness profile at center
    center_y = height // 2
    row_brightness = []
    for x in range(width):
        row_brightness.append(gray.getpixel((x, center_y)))

    # Find the dialog's left/right edges (brightness transitions)
    threshold = 40  # min brightness jump
    left = 0
    right = width - 1
    avg = sum(row_brightness) / len(row_brightness)

    for x in range(width // 4, width * 3 // 4):
        if row_brightness[x] > avg + threshold:
            left = max(0, x - 20)
            break
    for x in range(width * 3 // 4, width // 4, -1):
        if row_brightness[x] > avg + threshold:
            right = min(width - 1, x + 20)
            break

    # Scan vertical brightness at dialog center
    center_x = (left + right) // 2
    col_brightness = []
    for y in range(height):
        col_brightness.append(gray.getpixel((center_x, y)))

    avg_v = sum(col_brightness) / len(col_brightness)
    top = 0
    bottom = height - 1
    for y in range(height // 4, height * 3 // 4):
        if col_brightness[y] > avg_v + threshold:
            top = max(0, y - 20)
            break
    for y in range(height * 3 // 4, height // 4, -1):
        if col_brightness[y] > avg_v + threshold:
            bottom = min(height - 1, y + 20)
            break

    # Add padding
    pad = 40
    left = max(0, left - pad)
    top = max(0, top - pad)
    right = min(width, right + pad)
    bottom = min(height, bottom + pad)

    # Validate: dialog should be a reasonable size
    dw = right - left
    dh = bottom - top
    if dw < width * 0.15 or dh < height * 0.15:
        # Dialog detection failed, return full image
        return (0, 0, width, height)

    return (left, top, right, bottom)


def draw_text_with_shadow(draw: ImageDraw.Draw, canvas: Image.Image,
                          text: str, x: int, y: int,
                          font: ImageFont.FreeTypeFont):
    shadow_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_layer)
    shadow_draw.text((x, y), text, font=font, fill=TEXT_SHADOW_COLOR)
    shadow_layer = shadow_layer.filter(
        ImageFilter.GaussianBlur(radius=TEXT_SHADOW_BLUR)
    )
    canvas.paste(
        Image.alpha_composite(
            Image.new("RGBA", canvas.size, (0, 0, 0, 0)),
            shadow_layer
        ), (0, 0), shadow_layer
    )
    draw = ImageDraw.Draw(canvas)
    draw.text((x, y), text, font=font, fill=TEXT_COLOR)


def composite_screenshot(
    background_path: str,
    raw_path: str,
    output_path: str,
    punchline: str,
    is_dark_theme: bool = False,
    is_dialog: bool = False,
    crop_anchor: str = "top",  # "top", "center", or "bottom"
) -> bool:
    if not os.path.exists(raw_path):
        print(f"  Skipping: {raw_path} not found")
        return False

    bg = Image.open(background_path).convert("RGBA")
    bg = bg.resize((CANVAS_WIDTH, CANVAS_HEIGHT), Image.LANCZOS)

    window = Image.open(raw_path).convert("RGBA")

    # For dialog screenshots: crop to the dialog region, padded to landscape
    if is_dialog:
        dialog_box = find_dialog_region(window)
        dw = dialog_box[2] - dialog_box[0]
        dh = dialog_box[3] - dialog_box[1]
        print(f"  Dialog detected: {dw}x{dh}")

        # Expand the crop to landscape (16:10) proportions centered on the dialog
        target_aspect = CANVAS_WIDTH / CANVAS_HEIGHT
        crop_aspect = dw / dh if dh > 0 else target_aspect

        if crop_aspect < target_aspect:
            # Too tall — expand width, centered on dialog
            needed_width = int(dh * target_aspect)
            cx = (dialog_box[0] + dialog_box[2]) // 2
            x0 = max(0, cx - needed_width // 2)
            x1 = min(window.width, x0 + needed_width)
            x0 = max(0, x1 - needed_width)  # re-adjust if clamped right
            crop = (x0, dialog_box[1], x1, dialog_box[3])
        else:
            # Too wide — expand height, centered on dialog
            needed_height = int(dw / target_aspect)
            cy = (dialog_box[1] + dialog_box[3]) // 2
            y0 = max(0, cy - needed_height // 2)
            y1 = min(window.height, y0 + needed_height)
            y0 = max(0, y1 - needed_height)
            crop = (dialog_box[0], y0, dialog_box[2], y1)

        window = window.crop(crop)
        print(f"  Dialog crop (landscape): {window.width}x{window.height}")

    # For dialog shots: crop to landscape aspect ratio to focus on dialog.
    # For regular shots: keep full portrait height — window bleeds off bottom.
    if is_dialog:
        target_aspect = CANVAS_WIDTH / CANVAS_HEIGHT
        current_aspect = window.width / window.height
        if current_aspect < target_aspect:
            ideal_height = int(window.width / target_aspect)
            if ideal_height < window.height:
                if crop_anchor == "center":
                    y0 = (window.height - ideal_height) // 2
                    window = window.crop((0, y0, window.width, y0 + ideal_height))
                else:
                    window = window.crop((0, 0, window.width, ideal_height))
                print(f"  Dialog landscape crop ({crop_anchor}): {window.width}x{ideal_height}")

    # Scale window to target width
    target_width = int(CANVAS_WIDTH * WINDOW_SCALE)
    scale = target_width / window.width
    target_height = int(window.height * scale)

    # Clamp height
    max_height = int(CANVAS_HEIGHT * 1.2)  # Allow window to extend beyond canvas bottom
    if target_height > max_height:
        target_height = max_height
        scale = target_height / window.height
        target_width = int(window.width * scale)

    window = window.resize((target_width, target_height), Image.LANCZOS)
    window = add_rounded_corners(window, CORNER_RADIUS)

    window_x = (CANVAS_WIDTH - target_width) // 2
    window_y = int(CANVAS_HEIGHT * WINDOW_Y_FRACTION)

    if is_dark_theme:
        glow = create_window_glow(
            target_width, target_height,
            DARK_GLOW_RADIUS, DARK_GLOW_OPACITY, DARK_GLOW_COLOR
        )
        glow_x = window_x - DARK_GLOW_RADIUS * 2
        glow_y = window_y - DARK_GLOW_RADIUS * 2
        bg.paste(glow, (glow_x, glow_y), glow)

    shadow = create_drop_shadow(window, SHADOW_RADIUS, SHADOW_OFFSET_Y,
                                SHADOW_OPACITY)
    shadow_x = window_x - SHADOW_RADIUS * 2
    shadow_y = window_y - SHADOW_RADIUS * 2
    bg.paste(shadow, (shadow_x, shadow_y), shadow)
    bg.paste(window, (window_x, window_y), window)

    if punchline:
        font = find_font(HEADLINE_FONT_SIZE, bold=True)
        draw = ImageDraw.Draw(bg)
        bbox = draw.textbbox((0, 0), punchline, font=font)
        text_width = bbox[2] - bbox[0]
        text_x = (CANVAS_WIDTH - text_width) // 2
        text_y = int(CANVAS_HEIGHT * HEADLINE_Y_FRACTION)
        draw_text_with_shadow(draw, bg, punchline, text_x, text_y, font)

    final = Image.new("RGB", bg.size, (0, 0, 0))
    final.paste(bg, mask=bg.split()[3])
    final.save(output_path, "PNG", optimize=True)
    print(f"  Saved: {output_path}")
    return True


def main():
    parser = argparse.ArgumentParser(description="Composite App Store screenshots")
    parser.add_argument("--raw-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--background", required=True)
    parser.add_argument("--punchlines", required=True,
                        help="'num|text|is_dark|is_dialog|crop_anchor' per line")
    args = parser.parse_args()

    screenshots = {}
    for line in args.punchlines.strip().split("\n"):
        line = line.strip()
        if "|" not in line:
            continue
        parts = line.split("|")
        num = parts[0].strip()
        text = parts[1].strip() if len(parts) > 1 else ""
        is_dark = parts[2].strip() == "1" if len(parts) > 2 else False
        is_dialog = parts[3].strip() == "1" if len(parts) > 3 else False
        crop_anchor = parts[4].strip() if len(parts) > 4 and parts[4].strip() else "top"
        screenshots[num] = (text, is_dark, is_dialog, crop_anchor)

    os.makedirs(args.output_dir, exist_ok=True)

    success_count = 0
    for num, (text, is_dark, is_dialog, crop_anchor) in sorted(screenshots.items()):
        raw_path = os.path.join(args.raw_dir, f"screenshot_{num}_raw.png")
        output_path = os.path.join(args.output_dir, f"screenshot_{num}.png")
        flags = []
        if is_dark:
            flags.append("dark")
        if is_dialog:
            flags.append("dialog-crop")
        if crop_anchor != "top":
            flags.append(f"crop-{crop_anchor}")
        flag_str = f" ({', '.join(flags)})" if flags else ""
        print(f"Screenshot {num}: \"{text}\"{flag_str}")
        if composite_screenshot(args.background, raw_path, output_path, text,
                                is_dark_theme=is_dark, is_dialog=is_dialog,
                                crop_anchor=crop_anchor):
            success_count += 1

    print(f"\nComposited {success_count}/{len(screenshots)} screenshots.")


if __name__ == "__main__":
    main()
