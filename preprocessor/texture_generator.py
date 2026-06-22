"""Texture generator — create 4K texture atlases for buildings, roads, and terrain."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from config import (
    BUILDING_COLORS,
    LOG_FORMAT,
    LOG_LEVEL,
    ROAD_COLORS,
    TEXTURES_DIR,
    TEXTURE_SIZE_4K,
)

log = logging.getLogger("texture_generator")
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO), format=LOG_FORMAT)


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _make_atlas(
    size: int = TEXTURE_SIZE_4K,
    bg_color: tuple[int, int, int] = (255, 255, 255),
) -> Image.Image:
    """Create a blank RGBA atlas image."""
    return Image.new("RGBA", (size, size), (*bg_color, 255))


def _save_atlas(image: Image.Image, filename: str) -> Path:
    """Save an atlas to TEXTURES_DIR and return the path."""
    TEXTURES_DIR.mkdir(parents=True, exist_ok=True)
    path = TEXTURES_DIR / filename
    image.save(path, "PNG")
    log.info("Saved texture atlas: %s  (%d×%d)", path, *image.size)
    return path


# ---------------------------------------------------------------------------
# Building texture atlas
# ---------------------------------------------------------------------------

def generate_buildings_atlas(
    size: int = TEXTURE_SIZE_4K,
) -> Image.Image:
    """Generate a 4K texture atlas for buildings.

    Creates a grid of coloured building facade textures with a subtle
    brick/window pattern for each building colour category.
    """
    log.info("Generating buildings texture atlas (%d×%d) ...", size, size)
    atlas = _make_atlas(size, bg_color=(200, 200, 200))

    n_colors = len(BUILDING_COLORS)
    # Layout: one row per color, each row has repeated tile pattern
    tile_size = size // max(n_colors, 1)
    if tile_size < 4:
        tile_size = size // 4

    cols = size // tile_size

    for idx, (category, color) in enumerate(BUILDING_COLORS.items()):
        row = idx
        for col in range(cols):
            x0 = col * tile_size
            y0 = row * tile_size
            x1 = x0 + tile_size
            y1 = y0 + tile_size

            tile = _make_building_tile(tile_size, color)
            atlas.paste(tile, (x0, y0))

        log.debug("  Built tile %s %s", category, color)

    return atlas


def _make_building_tile(
    size: int,
    color: tuple[int, int, int],
) -> Image.Image:
    """Create a single building facade tile with a window pattern."""
    tile = Image.new("RGBA", (size, size), (*color, 255))
    draw = ImageDraw.Draw(tile)

    r, g, b = color
    # Subtle lighter/darker variations
    light = (min(255, r + 30), min(255, g + 30), min(255, b + 30))
    dark = (max(0, r - 30), max(0, g - 30), max(0, b - 30))

    # Draw a simple window grid
    window_size = max(size // 8, 4)
    window_spacing = max(size // 4, window_size + 4)

    for wy in range(window_spacing // 2, size - window_size, window_spacing):
        for wx in range(window_spacing // 2, size - window_size, window_spacing):
            # Window frame (slightly darker)
            draw.rectangle(
                [wx - 1, wy - 1, wx + window_size + 1, wy + window_size + 1],
                fill=dark,
            )
            # Window pane (lighter)
            draw.rectangle(
                [wx, wy, wx + window_size, wy + window_size],
                fill=light,
            )
            # Subtle cross divider
            mid_x = wx + window_size // 2
            mid_y = wy + window_size // 2
            draw.line([(mid_x, wy), (mid_x, wy + window_size)], fill=dark, width=1)
            draw.line([(wx, mid_y), (wx + window_size, mid_y)], fill=dark, width=1)

    return tile


# ---------------------------------------------------------------------------
# Road texture atlas
# ---------------------------------------------------------------------------

def generate_roads_atlas(
    size: int = TEXTURE_SIZE_4K,
) -> Image.Image:
    """Generate a 4K texture atlas for roads.

    Creates asphalt textures with lane markings for each road colour.
    """
    log.info("Generating roads texture atlas (%d×%d) ...", size, size)
    atlas = _make_atlas(size, bg_color=(180, 180, 180))

    tile_size = size // max(len(ROAD_COLORS), 1)
    cols = size // tile_size

    for idx, (category, color) in enumerate(ROAD_COLORS.items()):
        row = idx
        for col in range(cols):
            x0 = col * tile_size
            y0 = row * tile_size
            x1 = x0 + tile_size
            y1 = y0 + tile_size

            tile = _make_road_tile(tile_size, color, category)
            atlas.paste(tile, (x0, y0))

        log.debug("  Built road tile %s %s", category, color)

    return atlas


def _make_road_tile(
    size: int,
    color: tuple[int, int, int],
    road_type: str,
) -> Image.Image:
    """Create a single road texture tile with asphalt surface.

    Major roads get dashed centre lines; minor roads get plain asphalt.
    """
    tile = Image.new("RGBA", (size, size), (*color, 255))
    draw = ImageDraw.Draw(tile)

    # Add subtle noise for asphalt texture
    noise = np.random.randint(-15, 16, (size, size, 3), dtype=np.int16)
    arr = np.array(tile, dtype=np.int16)
    arr[:, :, :3] = np.clip(arr[:, :, :3] + noise, 0, 255)
    tile = Image.fromarray(arr.astype(np.uint8), "RGBA")
    draw = ImageDraw.Draw(tile)

    # Lane markings for major roads
    if road_type in ("autostrada", "primaria", "secondaria"):
        # Dashed centre line
        center_y = size // 2
        dash_length = max(size // 16, 4)
        gap_length = dash_length
        mark_color = (255, 255, 200)  # slightly warm white

        x = 0
        while x < size:
            x_end = min(x + dash_length, size)
            draw.rectangle([x, center_y - 1, x_end, center_y + 1], fill=mark_color)
            x += dash_length + gap_length

        # Edge lines
        edge_margin = max(size // 12, 4)
        draw.rectangle([0, edge_margin, size, edge_margin + 1], fill=mark_color)
        draw.rectangle([0, size - edge_margin, size, size - edge_margin + 1], fill=mark_color)

    # Residential roads: subtle cobblestone / pavement pattern
    if road_type == "residenziale":
        # Very subtle grid
        step = max(size // 16, 4)
        darker = (max(0, color[0] - 10), max(0, color[1] - 10), max(0, color[2] - 10))
        for i in range(0, size, step):
            draw.line([(i, 0), (i, size)], fill=darker, width=1)
            draw.line([(0, i), (size, i)], fill=darker, width=1)

    return tile


# ---------------------------------------------------------------------------
# Terrain texture atlas
# ---------------------------------------------------------------------------

def generate_terrain_atlas(
    size: int = TEXTURE_SIZE_4K,
) -> Image.Image:
    """Generate a 4K texture atlas for terrain.

    Creates a grass/ground texture with subtle variations.
    """
    log.info("Generating terrain texture atlas (%d×%d) ...", size, size)
    atlas = _make_atlas(size, bg_color=(100, 140, 80))

    # Generate a seamless grass-like texture using Perlin-like noise
    base_hue = np.array([100, 140, 80], dtype=np.float32)

    # Create a large noise field
    noise_scale = 0.03
    x_coords = np.tile(np.arange(size, dtype=np.float32), (size, 1))
    y_coords = np.tile(np.arange(size, dtype=np.float32)[:, None], (1, size))

    # Simple value noise approximation using random phases
    np.random.seed(42)  # deterministic
    noise = np.random.randn(16, 16)
    # Scale up with bilinear interpolation
    noise_large = np.zeros((size, size), dtype=np.float32)
    for i in range(16):
        for j in range(16):
            si = int(i * size / 16)
            ei = int((i + 1) * size / 16)
            sj = int(j * size / 16)
            ej = int((j + 1) * size / 16)
            noise_large[si:ei, sj:ej] = noise[i, j]

    # Smooth with blur
    noise_img = Image.fromarray(
        ((noise_large - noise_large.min()) / (noise_large.max() - noise_large.min() + 1e-8) * 255).astype(np.uint8)
    )
    noise_img = noise_img.filter(ImageFilter.GaussianBlur(radius=16))

    # Convert to array
    noise_arr = np.array(noise_img, dtype=np.float32) / 255.0

    # Create RGB channels with correlated noise for natural look
    r = np.clip(base_hue[0] + noise_arr * 40 - 20, 0, 255).astype(np.uint8)
    g = np.clip(base_hue[1] + noise_arr * 50 - 25, 0, 255).astype(np.uint8)
    b = np.clip(base_hue[2] + noise_arr * 30 - 15, 0, 255).astype(np.uint8)

    # Use different noise offset for each channel to add variation
    r2 = np.clip(base_hue[0] + 10 + noise_arr * 30 - 15, 0, 255).astype(np.uint8)
    g2 = np.clip(base_hue[1] + 15 + noise_arr * 35 - 17, 0, 255).astype(np.uint8)
    b2 = np.clip(base_hue[2] + 5 + noise_arr * 25 - 12, 0, 255).astype(np.uint8)

    # Blend two layers for richer texture
    blend_mask = np.tile(np.linspace(0, 1, size), (size, 1)).astype(np.float32)

    r_final = (r * (1 - blend_mask) + r2 * blend_mask).astype(np.uint8)
    g_final = (g * (1 - blend_mask) + g2 * blend_mask).astype(np.uint8)
    b_final = (b * (1 - blend_mask) + b2 * blend_mask).astype(np.uint8)

    arr = np.stack([r_final, g_final, b_final, np.full((size, size), 255, dtype=np.uint8)], axis=-1)
    atlas = Image.fromarray(arr, "RGBA")

    return atlas


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def generate_all_atlases(
    size: int = TEXTURE_SIZE_4K,
    save: bool = True,
) -> dict[str, Optional[Path]]:
    """Generate all three texture atlases.

    Parameters
    ----------
    size : atlas dimension (default 4096)
    save : if True, save to disk

    Returns
    -------
    dict with keys 'buildings', 'roads', 'terrain' mapping to file paths (or None)
    """
    paths: dict[str, Optional[Path]] = {
        "buildings": None,
        "roads": None,
        "terrain": None,
    }

    buildings = generate_buildings_atlas(size=size)
    if save:
        paths["buildings"] = _save_atlas(buildings, "buildings_atlas_4k.png")

    roads = generate_roads_atlas(size=size)
    if save:
        paths["roads"] = _save_atlas(roads, "roads_atlas_4k.png")

    terrain = generate_terrain_atlas(size=size)
    if save:
        paths["terrain"] = _save_atlas(terrain, "terrain_atlas_4k.png")

    return paths


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)
    generate_all_atlases()
