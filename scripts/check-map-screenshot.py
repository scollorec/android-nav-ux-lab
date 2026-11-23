#!/usr/bin/env python3
"""Fail when the central map viewport is blank or visually uniform."""
from __future__ import annotations

import argparse
from pathlib import Path
from PIL import Image, ImageStat


def measure(path: Path) -> tuple[int, float, tuple[int, int]]:
    with Image.open(path) as opened:
        image = opened.convert("RGB")
    width, height = image.size
    if width < 320 or height < 480:
        raise ValueError(f"Screenshot resolution too small: {width}x{height}")

    # The center of the phone viewport is map canvas, away from status/search
    # overlays at the top and navigation controls near the bottom.
    viewport = image.crop((
        int(width * 0.12), int(height * 0.28),
        int(width * 0.88), int(height * 0.72),
    )).resize((64, 64), Image.Resampling.BILINEAR)
    colour_counts = viewport.getcolors(maxcolors=4097)
    distinct_colours = len(colour_counts) if colour_counts is not None else 4097
    luminance = viewport.convert("L")
    luminance_stddev = ImageStat.Stat(luminance).stddev[0]
    return distinct_colours, luminance_stddev, (width, height)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("screenshot", type=Path)
    args = parser.parse_args()
    try:
        colours, stddev, size = measure(args.screenshot)
    except Exception as exc:
        print(f"Screenshot validation failed: {exc}")
        return 1

    print(
        f"Viewport sample: {size[0]}x{size[1]}, "
        f"{colours} distinct colours, luminance standard deviation {stddev:.2f}"
    )
    if colours < 24 or stddev < 3.0:
        print("Map viewport appears blank or nearly uniform")
        return 1
    print("Map viewport contains visible visual detail")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
