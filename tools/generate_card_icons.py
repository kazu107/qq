#!/usr/bin/env python3
"""Generate deterministic square card art from card definitions.

The game references card art by stable file name:
assets/icons/cards/<card_id>.png.  This script intentionally keeps those paths
unchanged and replaces only the image contents.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFilter


ROOT_DIR = Path(__file__).resolve().parents[1]
DEFAULT_CARDS_PATH = ROOT_DIR / "data" / "cards.json"
DEFAULT_OUT_DIR = ROOT_DIR / "assets" / "icons" / "cards"

Color = tuple[int, int, int]
Rgba = tuple[int, int, int, int]


PALETTES: dict[str, dict[str, Color]] = {
    "attack": {
        "top": (8, 18, 28),
        "bottom": (4, 6, 12),
        "accent": (67, 210, 255),
        "hot": (255, 244, 184),
        "secondary": (255, 104, 42),
    },
    "shield": {
        "top": (8, 25, 44),
        "bottom": (5, 10, 20),
        "accent": (88, 206, 255),
        "hot": (207, 246, 255),
        "secondary": (44, 128, 245),
    },
    "time": {
        "top": (16, 12, 38),
        "bottom": (3, 7, 18),
        "accent": (173, 118, 255),
        "hot": (255, 227, 92),
        "secondary": (67, 222, 255),
    },
    "heal": {
        "top": (6, 36, 30),
        "bottom": (4, 13, 16),
        "accent": (70, 238, 159),
        "hot": (222, 255, 189),
        "secondary": (38, 184, 228),
    },
    "bleed": {
        "top": (48, 8, 20),
        "bottom": (9, 5, 10),
        "accent": (255, 67, 96),
        "hot": (255, 218, 176),
        "secondary": (145, 26, 46),
    },
    "control": {
        "top": (14, 19, 44),
        "bottom": (5, 7, 18),
        "accent": (89, 232, 255),
        "hot": (255, 236, 110),
        "secondary": (114, 93, 255),
    },
    "support": {
        "top": (13, 33, 30),
        "bottom": (4, 12, 14),
        "accent": (85, 246, 178),
        "hot": (241, 255, 174),
        "secondary": (56, 172, 255),
    },
    "omega": {
        "top": (38, 16, 12),
        "bottom": (8, 4, 10),
        "accent": (255, 199, 69),
        "hot": (255, 246, 193),
        "secondary": (255, 68, 90),
    },
    "rift": {
        "top": (18, 8, 42),
        "bottom": (4, 5, 17),
        "accent": (198, 91, 255),
        "hot": (109, 241, 255),
        "secondary": (255, 83, 183),
    },
    "neutral": {
        "top": (16, 22, 34),
        "bottom": (5, 8, 14),
        "accent": (104, 196, 255),
        "hot": (231, 245, 255),
        "secondary": (255, 179, 71),
    },
}

RARITY_GLOWS: dict[str, Color] = {
    "common": (92, 180, 255),
    "uncommon": (72, 235, 157),
    "rare": (170, 111, 255),
    "epic": (255, 192, 72),
}


def _mix(a: Color, b: Color, t: float) -> Color:
    t = max(0.0, min(1.0, t))
    return (
        int(a[0] + (b[0] - a[0]) * t),
        int(a[1] + (b[1] - a[1]) * t),
        int(a[2] + (b[2] - a[2]) * t),
    )


def _rgba(color: Color, alpha: int = 255) -> Rgba:
    return (color[0], color[1], color[2], max(0, min(255, alpha)))


def _seed_for(card_id: str) -> int:
    return int(hashlib.sha256(card_id.encode("utf-8")).hexdigest()[:16], 16)


def _effect_types(card: dict[str, Any]) -> set[str]:
    return {str(effect.get("type", "")) for effect in card.get("effects", [])}


def _effect_mode(card: dict[str, Any], effect_type: str, key: str) -> str:
    for effect in card.get("effects", []):
        if effect.get("type") == effect_type:
            return str(effect.get(key, ""))
    return ""


def _palette_key(card: dict[str, Any]) -> str:
    tags = set(card.get("tags", []))
    effects = _effect_types(card)
    if "omega" in tags or "finisher" in tags:
        return "omega"
    if "rift" in tags or "phase" in tags:
        return "rift"
    if "timeline_flow" in effects or "time" in tags or "delay" in tags or "haste" in tags:
        return "time"
    if "bleed" in tags:
        return "bleed"
    if "heal" in tags or "heal" in effects:
        return "heal"
    if "shield" in tags or "gain_shield" in effects:
        return "shield"
    if "control" in tags or "debuff" in tags:
        return "control"
    if "support" in tags or "cooldown" in tags:
        return "support"
    if "attack" in tags or "deal_damage" in effects:
        return "attack"
    return "neutral"


def _draw_gradient(base: Image.Image, top: Color, bottom: Color) -> None:
    draw = ImageDraw.Draw(base)
    w, h = base.size
    for y in range(h):
        t = y / max(1, h - 1)
        draw.line([(0, y), (w, y)], fill=_rgba(_mix(top, bottom, t), 255))


def _layer(size: tuple[int, int]) -> Image.Image:
    return Image.new("RGBA", size, (0, 0, 0, 0))


def _composite_glow(base: Image.Image, layer: Image.Image, blur: float) -> None:
    if blur > 0:
        base.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))
    base.alpha_composite(layer)


def _line_with_glow(
    base: Image.Image,
    points: list[tuple[float, float]],
    color: Color,
    width: int,
    alpha: int = 230,
    glow: int = 22,
) -> None:
    glow_layer = _layer(base.size)
    glow_draw = ImageDraw.Draw(glow_layer)
    glow_draw.line(points, fill=_rgba(color, min(210, alpha)), width=width + glow, joint="curve")
    base.alpha_composite(glow_layer.filter(ImageFilter.GaussianBlur(max(2, glow // 2))))
    sharp = _layer(base.size)
    sharp_draw = ImageDraw.Draw(sharp)
    sharp_draw.line(points, fill=_rgba(color, alpha), width=width, joint="curve")
    sharp_draw.line(points, fill=_rgba((255, 255, 255), min(180, alpha)), width=max(1, width // 4), joint="curve")
    base.alpha_composite(sharp)


def _soft_disc(
    base: Image.Image,
    center: tuple[float, float],
    radius: float,
    color: Color,
    alpha: int,
    blur: float,
) -> None:
    disc = _layer(base.size)
    draw = ImageDraw.Draw(disc)
    x, y = center
    draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=_rgba(color, alpha))
    base.alpha_composite(disc.filter(ImageFilter.GaussianBlur(blur)))


def _polygon_with_glow(
    base: Image.Image,
    points: list[tuple[float, float]],
    fill: Rgba,
    outline: Color,
    width: int,
    glow: int,
) -> None:
    glow_layer = _layer(base.size)
    glow_draw = ImageDraw.Draw(glow_layer)
    glow_draw.polygon(points, outline=_rgba(outline, 180))
    glow_draw.line(points + [points[0]], fill=_rgba(outline, 200), width=width + glow, joint="curve")
    base.alpha_composite(glow_layer.filter(ImageFilter.GaussianBlur(max(2, glow // 2))))

    sharp = _layer(base.size)
    sharp_draw = ImageDraw.Draw(sharp)
    sharp_draw.polygon(points, fill=fill)
    sharp_draw.line(points + [points[0]], fill=_rgba(outline, 245), width=width, joint="curve")
    base.alpha_composite(sharp)


def _draw_arrowhead(
    draw: ImageDraw.ImageDraw,
    tip: tuple[float, float],
    angle: float,
    size: float,
    color: Rgba,
) -> None:
    left = (tip[0] - math.cos(angle - 0.65) * size, tip[1] - math.sin(angle - 0.65) * size)
    right = (tip[0] - math.cos(angle + 0.65) * size, tip[1] - math.sin(angle + 0.65) * size)
    draw.polygon([tip, left, right], fill=color)


def _draw_background(base: Image.Image, card: dict[str, Any], rng: random.Random, palette: dict[str, Color]) -> None:
    w, h = base.size
    _draw_gradient(base, palette["top"], palette["bottom"])
    _soft_disc(base, (w * (0.3 + rng.random() * 0.4), h * (0.18 + rng.random() * 0.24)), w * 0.38, palette["accent"], 95, w * 0.12)
    _soft_disc(base, (w * (0.6 + rng.random() * 0.2), h * (0.68 + rng.random() * 0.16)), w * 0.32, palette["secondary"], 70, w * 0.14)

    band_layer = _layer(base.size)
    band_draw = ImageDraw.Draw(band_layer)
    for _ in range(10):
        x = rng.uniform(-w * 0.35, w * 1.05)
        y = rng.uniform(-h * 0.15, h * 1.05)
        length = rng.uniform(w * 0.3, w * 0.85)
        angle = rng.choice([-0.9, -0.65, 0.65, 0.9])
        dx = math.cos(angle) * length
        dy = math.sin(angle) * length
        band_draw.line((x, y, x + dx, y + dy), fill=_rgba(palette["accent"], rng.randint(18, 54)), width=rng.randint(4, 14))
    base.alpha_composite(band_layer.filter(ImageFilter.GaussianBlur(2.0)))

    grid_layer = _layer(base.size)
    grid_draw = ImageDraw.Draw(grid_layer)
    spacing = max(44, w // 9)
    for x in range(-spacing, w + spacing, spacing):
        grid_draw.line([(x, 0), (x + int(w * 0.18), h)], fill=_rgba(palette["hot"], 14), width=1)
    for y in range(spacing, h, spacing):
        grid_draw.line([(0, y), (w, y - int(h * 0.12))], fill=_rgba(palette["hot"], 12), width=1)
    base.alpha_composite(grid_layer)

    for _ in range(68):
        x = rng.randint(0, w - 1)
        y = rng.randint(0, h - 1)
        r = rng.choice([1, 1, 2, 2, 3])
        alpha = rng.randint(35, 125)
        ImageDraw.Draw(base).ellipse((x - r, y - r, x + r, y + r), fill=_rgba(_mix(palette["accent"], palette["hot"], rng.random()), alpha))


def _draw_shield(base: Image.Image, palette: dict[str, Color], cx: float, cy: float, scale: float, tilt: float = 0.0) -> None:
    w, _ = base.size
    pts = [
        (-0.02, -0.38),
        (0.28, -0.24),
        (0.22, 0.20),
        (0.00, 0.42),
        (-0.22, 0.20),
        (-0.28, -0.24),
    ]
    cos_t = math.cos(tilt)
    sin_t = math.sin(tilt)
    poly: list[tuple[float, float]] = []
    for x, y in pts:
        px = cx + (x * cos_t - y * sin_t) * scale
        py = cy + (x * sin_t + y * cos_t) * scale
        poly.append((px, py))
    _polygon_with_glow(base, poly, _rgba(palette["secondary"], 92), palette["accent"], max(3, int(w * 0.012)), max(10, int(w * 0.04)))

    draw = ImageDraw.Draw(base)
    draw.line([poly[0], poly[3]], fill=_rgba(palette["hot"], 180), width=max(2, int(w * 0.009)))
    draw.line([poly[5], poly[3], poly[2]], fill=_rgba(palette["hot"], 120), width=max(2, int(w * 0.007)))
    _soft_disc(base, (cx, cy - scale * 0.04), scale * 0.26, palette["hot"], 70, scale * 0.05)


def _draw_slash(base: Image.Image, palette: dict[str, Color], rng: random.Random, heavy: bool = False) -> None:
    w, h = base.size
    direction = -1 if rng.random() < 0.5 else 1
    if direction > 0:
        start = (w * 0.13, h * 0.76)
        end = (w * 0.86, h * 0.19)
    else:
        start = (w * 0.14, h * 0.23)
        end = (w * 0.86, h * 0.79)
    width = int(w * (0.06 if heavy else 0.042))
    _line_with_glow(base, [start, end], palette["accent"], width, 235, int(w * 0.07))
    _line_with_glow(
        base,
        [(start[0] + w * 0.06, start[1] + h * 0.04 * direction), (end[0] - w * 0.05, end[1] - h * 0.04 * direction)],
        palette["hot"],
        max(3, width // 3),
        190,
        int(w * 0.04),
    )
    for _ in range(16 if heavy else 10):
        t = rng.random()
        x = start[0] + (end[0] - start[0]) * t
        y = start[1] + (end[1] - start[1]) * t
        dx = rng.uniform(-w * 0.12, w * 0.12)
        dy = rng.uniform(-h * 0.12, h * 0.12)
        _line_with_glow(base, [(x, y), (x + dx, y + dy)], palette["secondary"], max(2, int(w * 0.009)), 150, int(w * 0.025))


def _draw_hammer(base: Image.Image, palette: dict[str, Color], rng: random.Random) -> None:
    w, h = base.size
    layer = _layer(base.size)
    draw = ImageDraw.Draw(layer)
    handle = [(w * 0.36, h * 0.77), (w * 0.45, h * 0.82), (w * 0.68, h * 0.31), (w * 0.59, h * 0.27)]
    head = [(w * 0.48, h * 0.22), (w * 0.77, h * 0.34), (w * 0.71, h * 0.48), (w * 0.42, h * 0.36)]
    draw.polygon(handle, fill=_rgba((41, 35, 32), 245))
    draw.line(handle + [handle[0]], fill=_rgba(palette["hot"], 150), width=max(2, int(w * 0.01)))
    draw.polygon(head, fill=_rgba(_mix((150, 159, 171), palette["accent"], 0.28), 235))
    draw.line(head + [head[0]], fill=_rgba(palette["hot"], 230), width=max(3, int(w * 0.012)))
    base.alpha_composite(layer.filter(ImageFilter.GaussianBlur(7)))
    base.alpha_composite(layer)
    _draw_slash(base, palette, rng, heavy=True)


def _draw_projectile(base: Image.Image, palette: dict[str, Color], rng: random.Random, beam: bool = False) -> None:
    w, h = base.size
    if beam:
        y = h * rng.uniform(0.42, 0.56)
        _line_with_glow(base, [(w * 0.06, y + h * 0.09), (w * 0.92, y - h * 0.08)], palette["hot"], int(w * 0.055), 235, int(w * 0.09))
        _line_with_glow(base, [(w * 0.08, y + h * 0.12), (w * 0.9, y - h * 0.1)], palette["accent"], int(w * 0.018), 220, int(w * 0.04))
        return

    start = (w * 0.16, h * 0.72)
    end = (w * 0.78, h * 0.28)
    _line_with_glow(base, [start, end], palette["accent"], int(w * 0.03), 220, int(w * 0.06))
    _soft_disc(base, end, w * 0.095, palette["hot"], 220, w * 0.025)
    draw = ImageDraw.Draw(base)
    draw.ellipse((end[0] - w * 0.055, end[1] - w * 0.055, end[0] + w * 0.055, end[1] + w * 0.055), fill=_rgba(palette["hot"], 245))
    for _ in range(12):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(w * 0.09, w * 0.22)
        _line_with_glow(base, [end, (end[0] + math.cos(a) * r, end[1] + math.sin(a) * r)], palette["secondary"], max(2, int(w * 0.008)), 140, int(w * 0.02))


def _draw_meteor(base: Image.Image, palette: dict[str, Color], rng: random.Random) -> None:
    w, h = base.size
    tail_start = (w * 0.12, h * 0.18)
    impact = (w * 0.66, h * 0.66)
    _line_with_glow(base, [tail_start, impact], palette["secondary"], int(w * 0.11), 210, int(w * 0.1))
    _line_with_glow(base, [(w * 0.24, h * 0.12), impact], palette["hot"], int(w * 0.045), 220, int(w * 0.05))
    rock = [
        (impact[0] - w * 0.11, impact[1] - h * 0.06),
        (impact[0] + w * 0.04, impact[1] - h * 0.13),
        (impact[0] + w * 0.13, impact[1] + h * 0.03),
        (impact[0] + w * 0.02, impact[1] + h * 0.14),
        (impact[0] - w * 0.13, impact[1] + h * 0.08),
    ]
    _polygon_with_glow(base, rock, _rgba((77, 58, 49), 245), palette["hot"], max(3, int(w * 0.012)), int(w * 0.05))


def _draw_time_vortex(base: Image.Image, card: dict[str, Any], palette: dict[str, Color], rng: random.Random) -> None:
    w, h = base.size
    cx, cy = w * 0.5, h * 0.5
    mode = _effect_mode(card, "timeline_flow", "mode")
    layer = _layer(base.size)
    draw = ImageDraw.Draw(layer)
    for idx, radius in enumerate([0.33, 0.25, 0.17]):
        bbox = (cx - w * radius, cy - h * radius, cx + w * radius, cy + h * radius)
        start = 25 + idx * 34 + rng.randint(-18, 18)
        extent = 250 if mode != "reverse" else -250
        draw.arc(bbox, start=start, end=start + extent, fill=_rgba(palette["accent"], 230 - idx * 35), width=max(4, int(w * (0.018 - idx * 0.002))))
    for tick in range(12):
        a = tick / 12.0 * math.tau
        p1 = (cx + math.cos(a) * w * 0.29, cy + math.sin(a) * h * 0.29)
        p2 = (cx + math.cos(a) * w * 0.34, cy + math.sin(a) * h * 0.34)
        draw.line([p1, p2], fill=_rgba(palette["hot"], 160), width=max(2, int(w * 0.008)))
    hand_angle = -0.8 if mode == "reverse" else 0.9
    draw.line([(cx, cy), (cx + math.cos(hand_angle) * w * 0.2, cy + math.sin(hand_angle) * h * 0.2)], fill=_rgba(palette["hot"], 230), width=max(4, int(w * 0.014)))
    if mode == "stop":
        bar_w = w * 0.055
        for dx in [-bar_w, bar_w]:
            draw.rounded_rectangle((cx + dx - bar_w * 0.45, cy - h * 0.13, cx + dx + bar_w * 0.45, cy + h * 0.13), radius=int(w * 0.015), fill=_rgba(palette["hot"], 220))
    else:
        for tip_angle in [math.pi * 0.95, math.pi * 1.45]:
            tip = (cx + math.cos(tip_angle) * w * 0.33, cy + math.sin(tip_angle) * h * 0.33)
            _draw_arrowhead(draw, tip, tip_angle + (1.15 if mode == "reverse" else -1.15), w * 0.065, _rgba(palette["hot"], 210))
    _composite_glow(base, layer, w * 0.025)
    _soft_disc(base, (cx, cy), w * 0.11, palette["hot"], 105, w * 0.035)


def _draw_reload(base: Image.Image, palette: dict[str, Color], rng: random.Random) -> None:
    w, h = base.size
    cx, cy = w * 0.5, h * 0.5
    layer = _layer(base.size)
    draw = ImageDraw.Draw(layer)
    bbox = (w * 0.22, h * 0.22, w * 0.78, h * 0.78)
    draw.arc(bbox, 25, 315, fill=_rgba(palette["accent"], 235), width=max(6, int(w * 0.03)))
    tip_angle = math.radians(315)
    tip = (cx + math.cos(tip_angle) * w * 0.28, cy + math.sin(tip_angle) * h * 0.28)
    _draw_arrowhead(draw, tip, tip_angle + 1.25, w * 0.085, _rgba(palette["accent"], 235))
    draw.rounded_rectangle((w * 0.42, h * 0.29, w * 0.58, h * 0.71), radius=int(w * 0.025), fill=_rgba((28, 40, 48), 225), outline=_rgba(palette["hot"], 190), width=max(2, int(w * 0.01)))
    for y in [0.39, 0.5, 0.61]:
        draw.line([(w * 0.44, h * y), (w * 0.56, h * y)], fill=_rgba(palette["hot"], 150), width=max(2, int(w * 0.008)))
    _composite_glow(base, layer, w * 0.035)


def _draw_heal(base: Image.Image, palette: dict[str, Color], rng: random.Random) -> None:
    w, h = base.size
    layer = _layer(base.size)
    draw = ImageDraw.Draw(layer)
    cx, cy = w * 0.5, h * 0.48
    bar = w * 0.105
    length = w * 0.34
    draw.rounded_rectangle((cx - bar / 2, cy - length / 2, cx + bar / 2, cy + length / 2), radius=int(w * 0.025), fill=_rgba(palette["accent"], 235))
    draw.rounded_rectangle((cx - length / 2, cy - bar / 2, cx + length / 2, cy + bar / 2), radius=int(w * 0.025), fill=_rgba(palette["accent"], 235))
    draw.arc((w * 0.22, h * 0.2, w * 0.78, h * 0.76), 205, 335, fill=_rgba(palette["hot"], 180), width=max(4, int(w * 0.014)))
    _composite_glow(base, layer, w * 0.035)
    for _ in range(12):
        x = rng.uniform(w * 0.22, w * 0.78)
        y = rng.uniform(h * 0.2, h * 0.76)
        _soft_disc(base, (x, y), rng.uniform(w * 0.014, w * 0.03), palette["hot"], 120, w * 0.012)


def _draw_chain_drones(base: Image.Image, palette: dict[str, Color], rng: random.Random, turret: bool = False) -> None:
    w, h = base.size
    centers = [(w * 0.3, h * 0.44), (w * 0.52, h * 0.31), (w * 0.69, h * 0.56)]
    if turret:
        centers = [(w * 0.32, h * 0.56), (w * 0.52, h * 0.39), (w * 0.72, h * 0.56)]
    layer = _layer(base.size)
    draw = ImageDraw.Draw(layer)
    for a, b in zip(centers, centers[1:]):
        draw.line([a, b], fill=_rgba(palette["accent"], 150), width=max(3, int(w * 0.014)))
    for i, (cx, cy) in enumerate(centers):
        r = w * (0.07 if i == 1 else 0.055)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=_rgba((22, 33, 43), 235), outline=_rgba(palette["hot"], 220), width=max(2, int(w * 0.01)))
        draw.ellipse((cx - r * 0.38, cy - r * 0.38, cx + r * 0.38, cy + r * 0.38), fill=_rgba(palette["accent"], 235))
    if turret:
        draw.rounded_rectangle((w * 0.43, h * 0.62, w * 0.61, h * 0.75), radius=int(w * 0.02), fill=_rgba((24, 32, 39), 240), outline=_rgba(palette["hot"], 180), width=max(2, int(w * 0.01)))
        draw.line([(w * 0.52, h * 0.62), (w * 0.78, h * 0.45)], fill=_rgba(palette["accent"], 245), width=max(5, int(w * 0.018)))
        draw.line([(w * 0.46, h * 0.75), (w * 0.34, h * 0.88)], fill=_rgba(palette["hot"], 160), width=max(3, int(w * 0.01)))
        draw.line([(w * 0.58, h * 0.75), (w * 0.7, h * 0.88)], fill=_rgba(palette["hot"], 160), width=max(3, int(w * 0.01)))
    _composite_glow(base, layer, w * 0.035)


def _draw_rift(base: Image.Image, palette: dict[str, Color], rng: random.Random) -> None:
    w, h = base.size
    cx, cy = w * 0.5, h * 0.5
    points: list[tuple[float, float]] = []
    for i in range(92):
        t = i / 91.0
        a = t * math.tau * 2.5 + rng.uniform(-0.04, 0.04)
        r = w * (0.05 + 0.32 * t)
        points.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.78))
    _line_with_glow(base, points, palette["accent"], max(4, int(w * 0.018)), 225, int(w * 0.055))
    _line_with_glow(base, points[14:72], palette["secondary"], max(2, int(w * 0.011)), 180, int(w * 0.03))
    _soft_disc(base, (cx, cy), w * 0.12, palette["hot"], 115, w * 0.04)


def _draw_shield_spend(base: Image.Image, palette: dict[str, Color], rng: random.Random) -> None:
    w, h = base.size
    _draw_shield(base, palette, w * 0.42, h * 0.52, w * 0.78, -0.08)
    cracks = [
        [(w * 0.42, h * 0.27), (w * 0.48, h * 0.43), (w * 0.39, h * 0.55), (w * 0.48, h * 0.72)],
        [(w * 0.34, h * 0.38), (w * 0.48, h * 0.44), (w * 0.6, h * 0.37)],
    ]
    for crack in cracks:
        _line_with_glow(base, crack, palette["hot"], max(3, int(w * 0.012)), 230, int(w * 0.03))
    _line_with_glow(base, [(w * 0.53, h * 0.61), (w * 0.87, h * 0.34)], palette["secondary"], int(w * 0.035), 220, int(w * 0.055))


def _draw_battery(base: Image.Image, palette: dict[str, Color], rng: random.Random) -> None:
    w, h = base.size
    layer = _layer(base.size)
    draw = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = w * 0.32, h * 0.24, w * 0.68, h * 0.78
    draw.rounded_rectangle((x0, y0, x1, y1), radius=int(w * 0.035), fill=_rgba((17, 28, 34), 230), outline=_rgba(palette["accent"], 220), width=max(3, int(w * 0.014)))
    draw.rounded_rectangle((w * 0.43, h * 0.18, w * 0.57, h * 0.25), radius=int(w * 0.015), fill=_rgba(palette["accent"], 190))
    for i in range(4):
        y = y1 - (i + 1) * (y1 - y0) * 0.2
        draw.rounded_rectangle((x0 + w * 0.055, y, x1 - w * 0.055, y + h * 0.06), radius=int(w * 0.018), fill=_rgba(_mix(palette["secondary"], palette["hot"], i / 3.0), 210))
    _composite_glow(base, layer, w * 0.035)


def _draw_archive(base: Image.Image, palette: dict[str, Color], rng: random.Random) -> None:
    w, h = base.size
    layer = _layer(base.size)
    draw = ImageDraw.Draw(layer)
    for i in range(4):
        offset = i * w * 0.035
        draw.rounded_rectangle((w * 0.29 + offset, h * 0.22 + offset, w * 0.68 + offset, h * 0.62 + offset), radius=int(w * 0.025), fill=_rgba((20, 27, 34), 220), outline=_rgba(_mix(palette["accent"], palette["hot"], i / 3.0), 190), width=max(2, int(w * 0.008)))
        draw.line([(w * 0.35 + offset, h * 0.36 + offset), (w * 0.62 + offset, h * 0.36 + offset)], fill=_rgba(palette["hot"], 120), width=max(2, int(w * 0.006)))
        draw.line([(w * 0.35 + offset, h * 0.45 + offset), (w * 0.59 + offset, h * 0.45 + offset)], fill=_rgba(palette["accent"], 120), width=max(2, int(w * 0.006)))
    _composite_glow(base, layer, w * 0.03)


def _draw_trap(base: Image.Image, palette: dict[str, Color], rng: random.Random) -> None:
    w, h = base.size
    layer = _layer(base.size)
    draw = ImageDraw.Draw(layer)
    for i in range(3):
        y = h * (0.42 + i * 0.1)
        draw.line([(w * 0.23, y), (w * 0.77, y)], fill=_rgba(palette["accent"], 190), width=max(3, int(w * 0.012)))
        for x in [0.32, 0.5, 0.68]:
            draw.polygon([(w * x, y - h * 0.035), (w * (x + 0.035), y), (w * x, y + h * 0.035)], fill=_rgba(palette["hot"], 180))
    _composite_glow(base, layer, w * 0.03)


def _draw_overlays(base: Image.Image, card: dict[str, Any], palette: dict[str, Color], rng: random.Random) -> None:
    tags = set(card.get("tags", []))
    effects = _effect_types(card)
    w, h = base.size

    if "bleed" in tags:
        layer = _layer(base.size)
        draw = ImageDraw.Draw(layer)
        for cx, cy, r in [(w * 0.73, h * 0.25, w * 0.045), (w * 0.79, h * 0.37, w * 0.032), (w * 0.67, h * 0.35, w * 0.026)]:
            draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=_rgba((255, 45, 75), 210))
            draw.polygon([(cx, cy - r * 1.7), (cx - r * 0.62, cy - r * 0.15), (cx + r * 0.62, cy - r * 0.15)], fill=_rgba((255, 45, 75), 210))
        _composite_glow(base, layer, w * 0.025)

    if "debuff" in tags or "weak" in tags or "apply_status" in effects:
        layer = _layer(base.size)
        draw = ImageDraw.Draw(layer)
        cx, cy = w * 0.25, h * 0.25
        draw.polygon([(cx, cy - w * 0.07), (cx + w * 0.07, cy), (cx, cy + w * 0.07), (cx - w * 0.07, cy)], fill=_rgba(palette["secondary"], 135), outline=_rgba(palette["hot"], 185))
        draw.line([(cx - w * 0.04, cy - w * 0.02), (cx + w * 0.02, cy + w * 0.01), (cx - w * 0.015, cy + w * 0.058)], fill=_rgba((20, 10, 30), 225), width=max(2, int(w * 0.009)))
        _composite_glow(base, layer, w * 0.02)

    if "interrupt" in tags or "interrupt_card" in effects:
        _line_with_glow(
            base,
            [(w * 0.18, h * 0.82), (w * 0.34, h * 0.7), (w * 0.45, h * 0.76), (w * 0.62, h * 0.58), (w * 0.82, h * 0.64)],
            (255, 232, 97),
            max(3, int(w * 0.011)),
            190,
            int(w * 0.03),
        )

    if "buff" in tags or "empower_card" in effects:
        layer = _layer(base.size)
        draw = ImageDraw.Draw(layer)
        for i in range(3):
            y = h * (0.76 - i * 0.09)
            draw.polygon([(w * 0.22, y), (w * 0.32, y - h * 0.07), (w * 0.42, y), (w * 0.36, y), (w * 0.32, y - h * 0.025), (w * 0.28, y)], fill=_rgba(palette["hot"], 130 + i * 25))
        _composite_glow(base, layer, w * 0.025)

    if "slow" in tags:
        layer = _layer(base.size)
        draw = ImageDraw.Draw(layer)
        cx, cy = w * 0.77, h * 0.74
        for a in range(0, 180, 60):
            rad = math.radians(a)
            draw.line([(cx - math.cos(rad) * w * 0.08, cy - math.sin(rad) * w * 0.08), (cx + math.cos(rad) * w * 0.08, cy + math.sin(rad) * w * 0.08)], fill=_rgba((177, 234, 255), 170), width=max(2, int(w * 0.008)))
        _composite_glow(base, layer, w * 0.02)

    rarity = str(card.get("rarity", "common"))
    rarity_color = RARITY_GLOWS.get(rarity, RARITY_GLOWS["common"])
    _soft_disc(base, (w * 0.12, h * 0.12), w * 0.065, rarity_color, 72 if rarity == "common" else 115, w * 0.035)


def _draw_vignette(base: Image.Image) -> None:
    w, h = base.size
    overlay = _layer(base.size)
    draw = ImageDraw.Draw(overlay)
    for i in range(24):
        alpha = int(4 + i * 4.6)
        inset = i * min(w, h) * 0.008
        draw.rounded_rectangle((inset, inset, w - inset, h - inset), radius=int(w * 0.08), outline=(0, 0, 0, alpha), width=max(1, int(w * 0.012)))
    base.alpha_composite(overlay)


def _choose_main_motif(card: dict[str, Any], base: Image.Image, palette: dict[str, Color], rng: random.Random) -> None:
    card_id = str(card.get("id", ""))
    tags = set(card.get("tags", []))
    effects = _effect_types(card)
    w, h = base.size

    if card_id in {"final_archive"} or "archive" in card_id:
        _draw_archive(base, palette, rng)
        _draw_chain_drones(base, palette, rng)
        return
    if "battery" in card_id or "capacitor" in card_id or "reactor" in card_id:
        _draw_battery(base, palette, rng)
        if "deal_damage" in effects:
            _draw_projectile(base, palette, rng, beam=False)
        return
    if "meteor" in card_id:
        _draw_meteor(base, palette, rng)
        return
    if "turret" in card_id or "drone" in card_id or "foundry" in card_id:
        _draw_chain_drones(base, palette, rng, turret=True)
        return
    if "tripwire" in card_id or "snare" in card_id:
        _draw_trap(base, palette, rng)
        return
    if "timeline_flow" in effects or "time" in tags or "chrono" in card_id or "paradox" in card_id or "zero_hour" in card_id:
        _draw_time_vortex(base, card, palette, rng)
        if "deal_damage" in effects and "zero_hour" in card_id:
            _draw_projectile(base, palette, rng, beam=True)
        return
    if "shield_spend" in tags or "consume_shield" in effects:
        _draw_shield_spend(base, palette, rng)
        return
    if "rift" in tags or "phase" in tags or "null" in card_id:
        _draw_rift(base, palette, rng)
        if "deal_damage" in effects:
            _draw_projectile(base, palette, rng, beam=True)
        return
    if "heal" in tags or "heal" in effects or "repair" in card_id or "medic" in card_id:
        _draw_heal(base, palette, rng)
        return
    if "reload" in card_id or "cooldown" in tags or "loader" in card_id:
        _draw_reload(base, palette, rng)
        return
    if "shield" in tags or "gain_shield" in effects or "guard" in card_id or "aegis" in card_id or "armor" in card_id:
        _draw_shield(base, palette, w * 0.5, h * 0.5, w * 0.92, rng.uniform(-0.08, 0.08))
        if "deal_damage" in effects:
            _draw_slash(base, palette, rng, heavy=False)
        return
    if "hammer" in card_id or "swing" in card_id:
        _draw_hammer(base, palette, rng)
        return
    if "shot" in card_id or "dart" in card_id or "ray" in card_id or "lance" in card_id or "volley" in card_id:
        _draw_projectile(base, palette, rng, beam=("ray" in card_id or "lance" in card_id))
        return
    if "chain" in tags or "auto_queue_card" in effects:
        _draw_chain_drones(base, palette, rng)
        if "deal_damage" in effects:
            _draw_slash(base, palette, rng, heavy=False)
        return
    if "deal_damage" in effects or "attack" in tags:
        _draw_slash(base, palette, rng, heavy=("heavy" in tags or "finisher" in tags))
        return

    _draw_rift(base, palette, rng)


def generate_card_icon(card: dict[str, Any], size: int) -> Image.Image:
    seed = _seed_for(str(card.get("id", "")))
    rng = random.Random(seed)
    work_size = size * 2
    base = Image.new("RGBA", (work_size, work_size), (0, 0, 0, 255))
    palette = PALETTES[_palette_key(card)]

    _draw_background(base, card, rng, palette)
    _choose_main_motif(card, base, palette, rng)
    _draw_overlays(base, card, palette, rng)
    _draw_vignette(base)

    final = base.resize((size, size), Image.Resampling.LANCZOS)
    return final.convert("RGB")


def generate_all(cards_path: Path, out_dir: Path, size: int, only: set[str] | None) -> list[Path]:
    cards = json.loads(cards_path.read_text(encoding="utf-8"))
    out_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for card in cards:
        card_id = str(card.get("id", ""))
        if only is not None and card_id not in only:
            continue
        if not card_id:
            continue
        image = generate_card_icon(card, size)
        out_path = out_dir / f"{card_id}.png"
        image.save(out_path, optimize=True)
        written.append(out_path)
    return written


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate deterministic card icons.")
    parser.add_argument("--cards", type=Path, default=DEFAULT_CARDS_PATH)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument("--only", nargs="*", default=None, help="Optional card ids to regenerate.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    only = set(args.only) if args.only else None
    written = generate_all(args.cards, args.out_dir, args.size, only)
    print(f"Generated {len(written)} card icons at {args.size}x{args.size} into {args.out_dir}")


if __name__ == "__main__":
    main()
