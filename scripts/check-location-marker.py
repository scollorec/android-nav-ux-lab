#!/usr/bin/env python3
"""Detect the blue/green Android-nav current-location dot in an emulator screenshot.

This is a visual regression heuristic, not semantic map recognition. The app
specifies an electric-blue marker for a fresh fix and green for a stale or
unusable last-known fix; the marker is a small circle with a white outline.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image


def find_location_components(image: Image.Image) -> list[dict[str, float | int | str]]:
    rgb = image.convert("RGB")
    width, height = rgb.size
    raw_pixels = rgb.tobytes()
    mask = bytearray(width * height)

    for index in range(width * height):
        offset = index * 3
        red, green, blue = raw_pixels[offset : offset + 3]
        if blue >= 190 and 75 <= green <= 185 and red <= 70 and blue - red >= 140:
            mask[index] = 1  # fresh electric-blue location marker
        elif 20 <= red <= 100 and green >= 155 and 35 <= blue <= 135 and green - red >= 90:
            mask[index] = 2  # stale / unusable green location marker

    visited = bytearray(width * height)
    components: list[dict[str, float | int | str]] = []
    for start, selected in enumerate(mask):
        if not selected or visited[start]:
            continue
        queue = deque([start])
        visited[start] = 1
        count = sum_x = sum_y = 0
        min_x, min_y = width, height
        max_x = max_y = -1
        while queue:
            current = queue.popleft()
            y, x = divmod(current, width)
            count += 1
            sum_x += x
            sum_y += y
            min_x, max_x = min(min_x, x), max(max_x, x)
            min_y, max_y = min(min_y, y), max(max_y, y)
            for dy in (-1, 0, 1):
                ny = y + dy
                if ny < 0 or ny >= height:
                    continue
                row_offset = ny * width
                for dx in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    nx = x + dx
                    if nx < 0 or nx >= width:
                        continue
                    neighbour = row_offset + nx
                    if mask[neighbour] == selected and not visited[neighbour]:
                        visited[neighbour] = 1
                        queue.append(neighbour)

        box_width, box_height = max_x - min_x + 1, max_y - min_y + 1
        aspect = box_width / max(box_height, 1)
        centre_y = sum_y / count
        # The map's location dot is compact and circular. Exclude the bottom
        # app-build banner, whose green text must never be mistaken for a fix.
        inside_map_area = height * 0.08 <= centre_y <= height * 0.92
        circular_shape = 0.65 <= aspect <= 1.5
        if 20 <= count <= 800 and 6 <= box_width <= 30 and 6 <= box_height <= 30 and circular_shape and inside_map_area:
            components.append({
                "pixels": count,
                "x": round(sum_x / count, 2),
                "y": round(centre_y, 2),
                "width": box_width,
                "height": box_height,
                "color": "blue" if selected == 1 else "green",
            })
    return sorted(components, key=lambda item: int(item["pixels"]), reverse=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--expect", choices=("centered", "off-centre"), required=True)
    parser.add_argument("--tolerance", type=float, default=0.12)
    parser.add_argument("--compare-to", type=Path, help="Prior viewport; require a changed background outside the central marker region")
    parser.add_argument("--min-background-difference", type=float, default=0.01)
    args = parser.parse_args()
    try:
        image = Image.open(args.image).convert("RGB")
    except Exception as exc:
        print(json.dumps({"ok": False, "error": f"Unable to read screenshot: {exc}"}))
        return 2

    width, height = image.size
    components = find_location_components(image)
    if not components:
        print(json.dumps({"ok": False, "error": "No qualifying blue or green location-marker component found", "width": width, "height": height}))
        return 1

    marker = components[0]
    dx = abs(float(marker["x"]) - width / 2) / width
    dy = abs(float(marker["y"]) - height / 2) / height
    centered = dx <= args.tolerance and dy <= args.tolerance
    off_centre = dx >= 0.15 or dy >= 0.15
    ok = centered if args.expect == "centered" else off_centre
    background_difference = None
    if args.compare_to is not None:
        try:
            previous = Image.open(args.compare_to).convert("RGB")
            if previous.size != image.size:
                previous = previous.resize(image.size)
            previous_pixels = previous.tobytes()
            current_pixels = image.tobytes()
            changed = total = 0
            for y in range(height):
                for x in range(width):
                    if abs(x - width / 2) <= width * 0.12 and abs(y - height / 2) <= height * 0.12:
                        continue
                    offset = (y * width + x) * 3
                    delta = max(
                        abs(previous_pixels[offset] - current_pixels[offset]),
                        abs(previous_pixels[offset + 1] - current_pixels[offset + 1]),
                        abs(previous_pixels[offset + 2] - current_pixels[offset + 2]),
                    )
                    total += 1
                    if delta >= 24:
                        changed += 1
            background_difference = changed / max(total, 1)
            ok = ok and background_difference >= args.min_background_difference
        except Exception as exc:
            print(json.dumps({"ok": False, "error": f"Unable to compare map backgrounds: {exc}"}))
            return 2

    print(json.dumps({
        "ok": ok,
        "expect": args.expect,
        "screen": {"width": width, "height": height},
        "marker": marker,
        "normalized_offset": {"x": round(dx, 4), "y": round(dy, 4)},
        "components_detected": len(components),
        "background_difference_ratio": None if background_difference is None else round(background_difference, 4),
    }, sort_keys=True))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
