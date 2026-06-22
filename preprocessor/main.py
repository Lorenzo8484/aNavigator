#!/usr/bin/env python3
"""scenekit-italy preprocessor — CLI entry point.

Downloads OSM data and converts it to SceneKit-compatible 3D meshes.

Usage:
    python main.py --tile LAT,LON        Process a single tile
    python main.py --area bologna        Process tiles covering Bologna
    python main.py --area roma           Process tiles covering Rome
    python main.py --all                 Process all of Italy (DANGER: huge)
    python main.py --textures            Only generate texture atlases
    python main.py --help                Show help
"""

from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path
from typing import Any, Optional

from config import (
    ITALY_BBOX,
    LOG_FORMAT,
    LOG_LEVEL,
    OUTPUT_DIR,
    TILE_SIZE,
    TILES_DIR,
)

log = logging.getLogger("main")
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO), format=LOG_FORMAT)


# ---------------------------------------------------------------------------
# Known areas (bounding boxes in degrees: lon_min, lat_min, lon_max, lat_max)
# ---------------------------------------------------------------------------
AREAS: dict[str, tuple[float, float, float, float]] = {
    "bologna":      (11.30, 44.46, 11.38, 44.52),
    "roma":         (12.44, 41.85, 12.54, 41.94),
    "milano":       (9.15, 45.44, 9.22, 45.49),
    "firenze":      (11.22, 43.75, 11.28, 43.80),
    "napoli":       (14.21, 40.81, 14.30, 40.86),
    "torino":       (7.65, 45.04, 7.72, 45.10),
    "venezia":      (12.30, 45.42, 12.37, 45.46),
    "palermo":      (13.34, 38.10, 13.39, 38.14),
}


# ---------------------------------------------------------------------------
# Tile generation logic
# ---------------------------------------------------------------------------

def generate_tile(
    bbox: tuple[float, float, float, float],
    use_cache: bool = True,
    force_osmnx: bool = False,
    include_terrain: bool = True,
    terrain_subdivisions: int = 4,
    terrain_grid: bool = False,
    verbose: bool = False,
) -> Optional[Path]:
    """Process a single tile: fetch OSM data → build meshes → export.

    Parameters
    ----------
    bbox : (lon_min, lat_min, lon_max, lat_max)
    use_cache : cache OSM responses
    force_osmnx : prefer osmnx over direct Overpass
    include_terrain : generate a ground plane
    terrain_subdivisions : terrain mesh resolution
    terrain_grid : overlay a grid
    verbose : enable debug logging

    Returns
    -------
    Path to exported tile file, or None on failure.
    """
    from osm_fetcher import fetch_tile
    from building_processor import process_buildings
    from road_processor import process_roads
    from terrain_processor import generate_flat_terrain
    from tile_exporter import export_tile

    if verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    lon_min, lat_min, lon_max, lat_max = bbox

    log.info(
        "=" * 60,
    )
    log.info(
        "Processing tile (%.4f, %.4f, %.4f, %.4f)",
        lon_min, lat_min, lon_max, lat_max,
    )

    t0 = time.perf_counter()

    # Step 1: Fetch OSM data
    try:
        log.info("Step 1/4: Fetching OSM data ...")
        data = fetch_tile(
            bbox,
            mode="full",
            use_cache=use_cache,
            force_osmnx=force_osmnx,
        )
    except Exception as exc:
        log.error("Failed to fetch OSM data: %s", exc)
        return None

    buildings_raw = data.get("buildings", [])
    roads_raw = data.get("roads", [])
    log.info("  -> Fetched %d buildings, %d roads", len(buildings_raw), len(roads_raw))

    # Step 2: Process buildings
    log.info("Step 2/4: Processing buildings ...")
    b_meshes = process_buildings(buildings_raw)

    # Step 3: Process roads
    log.info("Step 3/4: Processing roads ...")
    r_meshes = process_roads(roads_raw)

    # Step 4: Generate terrain
    terrain = None
    if include_terrain:
        log.info("Step 3b/4: Generating terrain ...")
        terrain = generate_flat_terrain(
            bbox,
            z=0.0,
            subdivisions=terrain_subdivisions,
            include_grid=terrain_grid,
        )

    # Step 5: Export
    log.info("Step 4/4: Exporting tile ...")
    try:
        path = export_tile(
            buildings=b_meshes,
            roads=r_meshes,
            terrain=terrain,
            bbox=bbox,
        )
    except Exception as exc:
        log.error("Failed to export tile: %s", exc)
        return None

    elapsed = time.perf_counter() - t0
    log.info(
        "Tile complete in %.1f s: %s",
        elapsed,
        path,
    )
    return path


def generate_tiles_for_bbox(
    area_bbox: tuple[float, float, float, float],
    tile_size: float = TILE_SIZE,
    **kwargs: Any,
) -> list[Path]:
    """Split a bounding box into tiles and process each one.

    Parameters
    ----------
    area_bbox : (lon_min, lat_min, lon_max, lat_max)
    tile_size : tile dimension in degrees
    **kwargs : forwarded to generate_tile()

    Returns
    -------
    List of exported tile file paths.
    """
    lon_min, lat_min, lon_max, lat_max = area_bbox
    paths: list[Path] = []

    # Snap to tile grid
    lon_start = int(lon_min / tile_size) * tile_size
    lat_start = int(lat_min / tile_size) * tile_size

    lon = lon_start
    while lon < lon_max:
        lat = lat_start
        while lat < lat_max:
            t_lon_max = min(lon + tile_size, lon_max)
            t_lat_max = min(lat + tile_size, lat_max)
            # Skip degenerate (zero-area) tiles at boundaries
            if t_lon_max - lon < 1e-10 or t_lat_max - lat < 1e-10:
                lat += tile_size
                continue
            tile_bbox = (lon, lat, t_lon_max, t_lat_max)
            path = generate_tile(tile_bbox, **kwargs)
            if path:
                paths.append(path)
            lat += tile_size
        lon += tile_size

    return paths


def process_all_italy(**kwargs: Any) -> list[Path]:
    """Process all of Italy.  WARNING: this will generate thousands of tiles."""
    log.warning("=" * 60)
    log.warning("PROCESSING ALL ITALY — THIS WILL GENERATE MANY TILES AND TAKE A LONG TIME")
    log.warning("=" * 60)
    return generate_tiles_for_bbox(ITALY_BBOX, **kwargs)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="scenekit-italy preprocessor — OSM to SceneKit 3D meshes",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --tile 11.34,44.49          Process one tile near Bologna
  %(prog)s --area bologna              Process tiles covering Bologna city centre
  %(prog)s --area roma --no-cache      Process Rome without using cached data
  %(prog)s --all                       Process ALL of Italy (very large!)
  %(prog)s --textures                  Only generate texture atlases
  %(prog)s --list-areas                Show available named areas
        """,
    )

    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--tile",
        type=str,
        metavar="LAT,LON",
        help="Process a single tile at the given latitude, longitude",
    )
    mode.add_argument(
        "--area",
        type=str,
        metavar="NAME",
        help="Process a named area (e.g. bologna, roma, milano)",
    )
    mode.add_argument(
        "--all",
        action="store_true",
        dest="process_all",
        help="Process all of Italy (DANGER: generates thousands of tiles)",
    )
    mode.add_argument(
        "--textures",
        action="store_true",
        help="Only generate texture atlases (no OSM fetching)",
    )
    mode.add_argument(
        "--list-areas",
        action="store_true",
        help="List available named areas and exit",
    )

    parser.add_argument(
        "--no-cache",
        action="store_false",
        dest="use_cache",
        help="Bypass OSM response cache",
    )
    parser.add_argument(
        "--force-osmnx",
        action="store_true",
        help="Force use of osmnx (even if direct Overpass is preferred)",
    )
    parser.add_argument(
        "--no-terrain",
        action="store_false",
        dest="include_terrain",
        help="Skip terrain generation",
    )
    parser.add_argument(
        "--terrain-grid",
        action="store_true",
        help="Add grid lines on terrain",
    )
    parser.add_argument(
        "--terrain-subdivisions",
        type=int,
        default=4,
        metavar="N",
        help="Terrain mesh subdivisions per edge (default: 4)",
    )
    parser.add_argument(
        "--output",
        type=str,
        metavar="DIR",
        help="Output directory (default: preprocessor/output/)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable debug logging",
    )

    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv)

    # Configure logging
    level = logging.DEBUG if args.verbose else getattr(logging, LOG_LEVEL, logging.INFO)
    logging.getLogger().setLevel(level)

    # Handle --list-areas
    if args.list_areas:
        print("Available named areas:")
        for name, bbox in sorted(AREAS.items()):
            print(f"  {name:15s}  ({bbox[0]:.2f}, {bbox[1]:.2f}, {bbox[2]:.2f}, {bbox[3]:.2f})")
        return 0

    # Handle --textures (atlas generation only)
    if args.textures:
        from texture_generator import generate_all_atlases
        log.info("Generating texture atlases only ...")
        paths = generate_all_atlases()
        for kind, p in paths.items():
            print(f"  {kind:10s} -> {p}")
        return 0

    # Determine output directory
    if args.output:
        output_dir = Path(args.output)
        output_dir.mkdir(parents=True, exist_ok=True)
        # Override config paths
        import config as cfg
        cfg.TILES_DIR = output_dir / "tiles"
        cfg.TILES_DIR.mkdir(parents=True, exist_ok=True)

    # Common kwargs for tile processing
    tile_kwargs: dict[str, Any] = {
        "use_cache": args.use_cache,
        "force_osmnx": args.force_osmnx,
        "include_terrain": args.include_terrain,
        "terrain_subdivisions": args.terrain_subdivisions,
        "terrain_grid": args.terrain_grid,
        "verbose": args.verbose,
    }

    # --tile LAT,LON
    if args.tile:
        try:
            parts = args.tile.split(",")
            lat = float(parts[0].strip())
            lon = float(parts[1].strip())
        except (ValueError, IndexError):
            log.error("Invalid tile format: '%s'.  Use --tile LAT,LON", args.tile)
            return 1

        # Create a tile-sized bounding box around the given point
        half = TILE_SIZE / 2
        bbox = (lon - half, lat - half, lon + half, lat + half)
        path = generate_tile(bbox, **tile_kwargs)
        return 0 if path else 1

    # --area NAME
    if args.area:
        name = args.area.lower().strip()
        if name not in AREAS:
            log.error(
                "Unknown area '%s'.  Use --list-areas to see available areas.",
                name,
            )
            return 1

        bbox = AREAS[name]
        log.info("Processing area '%s': %s", name, bbox)
        paths = generate_tiles_for_bbox(bbox, **tile_kwargs)
        log.info("Area '%s' complete: %d tiles generated", name, len(paths))
        return 0

    # --all
    if args.process_all:
        paths = process_all_italy(**tile_kwargs)
        log.info("All Italy complete: %d tiles generated", len(paths))
        return 0

    # No mode specified
    log.error("No action specified.  Use --tile, --area, --all, --textures, or --help.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
