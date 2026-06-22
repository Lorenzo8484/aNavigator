"""Tile exporter — serialise processed tile data to compact binary format."""

from __future__ import annotations

import logging
import struct
from pathlib import Path
from typing import Any, Optional

import numpy as np

from config import (
    LOG_FORMAT,
    LOG_LEVEL,
    TILES_DIR,
)
from building_processor import BuildingMesh
from road_processor import RoadMesh
from terrain_processor import TerrainMesh

log = logging.getLogger("tile_exporter")
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO), format=LOG_FORMAT)


# ---------------------------------------------------------------------------
# Binary format specification
# ---------------------------------------------------------------------------
#
# File structure (little-endian):
#
# [Header]
#   magic        : 4 bytes  = b"STIL"  (SceneKit Tile)
#   version      : uint16   = 1
#   num_buildings: uint32
#   num_roads    : uint32
#   has_terrain  : uint8    (0 or 1)
#
# [Buildings]  (repeated num_buildings times)
#   lat_center   : float32
#   lon_center   : float32
#   num_vertices : uint32
#   vertices     : num_vertices * 3 * float32   (x, y, z per vertex)
#   normals      : num_vertices * 3 * float32   (nx, ny, nz per vertex)
#   num_indices  : uint32
#   indices      : num_indices * uint32         (triangle indices)
#   color_r      : uint8
#   color_g      : uint8
#   color_b      : uint8
#   padding      : 1 byte
#
# [Roads]  (repeated num_roads times)
#   lat_center   : float32
#   lon_center   : float32
#   road_type_len: uint16
#   road_type    : road_type_len * ascii bytes
#   num_vertices : uint32
#   vertices     : num_vertices * 3 * float32
#   normals      : num_vertices * 3 * float32
#   num_indices  : uint32
#   indices      : num_indices * uint32
#   color_r      : uint8
#   color_g      : uint8
#   color_b      : uint8
#   padding      : 1 byte
#
# [Terrain]
#   if has_terrain == 1:
#     num_vertices : uint32
#     vertices     : num_vertices * 3 * float32
#     normals      : num_vertices * 3 * float32
#     num_indices  : uint32
#     indices      : num_indices * uint32
#   otherwise:
#     <nothing>
#
# ---------------------------------------------------------------------------


MAGIC = b"STIL"
VERSION = 1


def _build_header(
    num_buildings: int,
    num_roads: int,
    has_terrain: bool,
) -> bytes:
    return struct.pack(
        "<4sHIIB",
        MAGIC,
        VERSION,
        num_buildings,
        num_roads,
        1 if has_terrain else 0,
    )


def _build_building_block(mesh: BuildingMesh) -> bytes:
    """Serialise a single BuildingMesh to bytes."""
    parts = [
        struct.pack("<ff", mesh.center[1], mesh.center[0]),  # lat, lon
        struct.pack("<I", mesh.vertex_count),
        mesh.vertices.astype(np.float32).tobytes(),
        mesh.normals.astype(np.float32).tobytes(),
        struct.pack("<I", mesh.indices.size),  # flat count
        mesh.indices.astype(np.uint32).tobytes(),
        struct.pack("<BBBx", mesh.color[0], mesh.color[1], mesh.color[2]),  # + padding
    ]
    return b"".join(parts)


def _build_road_block(mesh: RoadMesh) -> bytes:
    """Serialise a single RoadMesh to bytes."""
    rtype_bytes = (mesh.road_type or "default").encode("ascii")
    rtype_len = len(rtype_bytes)
    if rtype_len > 65535:
        rtype_bytes = rtype_bytes[:65535]
        rtype_len = 65535

    parts = [
        struct.pack("<ff", mesh.center[1], mesh.center[0]),  # lat, lon
        struct.pack("<H", rtype_len),
        rtype_bytes,
        struct.pack("<I", mesh.vertex_count),
        mesh.vertices.astype(np.float32).tobytes(),
        mesh.normals.astype(np.float32).tobytes(),
        struct.pack("<I", mesh.indices.size),
        mesh.indices.astype(np.uint32).tobytes(),
        struct.pack("<BBBx", mesh.color[0], mesh.color[1], mesh.color[2]),
    ]
    return b"".join(parts)


def _build_terrain_block(terrain: TerrainMesh) -> bytes:
    """Serialise a TerrainMesh to bytes."""
    parts = [
        struct.pack("<I", terrain.vertex_count),
        terrain.vertices.astype(np.float32).tobytes(),
        terrain.normals.astype(np.float32).tobytes(),
        struct.pack("<I", terrain.indices.size),
        terrain.indices.astype(np.uint32).tobytes(),
    ]
    return b"".join(parts)


# ---------------------------------------------------------------------------
# Tile file naming
# ---------------------------------------------------------------------------

def _tile_filename(
    lon_min: float,
    lat_min: float,
    lon_max: float,
    lat_max: float,
    suffix: str = ".stile",
) -> str:
    """Generate a filename for a tile based on its bbox."""
    # Use the south-west corner rounded to 2 decimals
    sw_lon = f"{lon_min:+.2f}"
    sw_lat = f"{lat_min:+.2f}"
    return f"tile_{sw_lon}_{sw_lat}{suffix}"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def export_tile(
    buildings: list[BuildingMesh],
    roads: list[RoadMesh],
    terrain: Optional[TerrainMesh],
    bbox: tuple[float, float, float, float],
    output_dir: Optional[Path] = None,
) -> Path:
    """Export a processed tile to the compact binary format.

    Parameters
    ----------
    buildings : list of BuildingMesh
    roads : list of RoadMesh
    terrain : TerrainMesh or None
    bbox : (lon_min, lat_min, lon_max, lat_max) — used for filename
    output_dir : output directory (default: TILES_DIR)

    Returns
    -------
    Path to the exported tile file.
    """
    if output_dir is None:
        output_dir = TILES_DIR

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    filename = _tile_filename(*bbox)
    filepath = output_dir / filename

    log.info(
        "Exporting tile %s: %d buildings, %d roads, terrain=%s",
        filename,
        len(buildings),
        len(roads),
        "yes" if terrain else "no",
    )

    # Build header
    header = _build_header(
        num_buildings=len(buildings),
        num_roads=len(roads),
        has_terrain=terrain is not None,
    )

    # Build building blocks
    building_blocks = [_build_building_block(m) for m in buildings]

    # Build road blocks
    road_blocks = [_build_road_block(m) for m in roads]

    # Build terrain block
    terrain_block = _build_terrain_block(terrain) if terrain is not None else b""

    # Combine
    payload = header
    payload += b"".join(building_blocks)
    payload += b"".join(road_blocks)
    payload += terrain_block

    # Write
    try:
        filepath.write_bytes(payload)
        size_mb = len(payload) / (1024 * 1024)
        log.info(
            "  -> Wrote %.2f MB to %s",
            size_mb,
            filepath,
        )
    except OSError as exc:
        log.error("Failed to write tile %s: %s", filepath, exc)
        raise

    return filepath


# ---------------------------------------------------------------------------
# De-serialization (for verification / downstream tools)
# ---------------------------------------------------------------------------

def load_tile(filepath: Path) -> dict[str, Any]:
    """Load a .stile tile file and return its contents as a Python dict.

    This is primarily for verification and downstream use in renderers.
    """
    data = filepath.read_bytes()
    offset = 0

    # Parse header
    magic = data[offset:offset + 4]
    offset += 4
    if magic != MAGIC:
        raise ValueError(f"Invalid magic: {magic!r}")

    version, num_buildings, num_roads, has_terrain = struct.unpack_from(
        "<HIIB", data, offset
    )
    offset += struct.calcsize("<HIIB")

    result: dict[str, Any] = {
        "version": version,
        "num_buildings": num_buildings,
        "num_roads": num_roads,
        "has_terrain": bool(has_terrain),
        "buildings": [],
        "roads": [],
        "terrain": None,
    }

    for _ in range(num_buildings):
        lat, lon = struct.unpack_from("<ff", data, offset)
        offset += struct.calcsize("<ff")

        nv = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        verts = np.frombuffer(data, dtype=np.float32, count=nv * 3, offset=offset).reshape(nv, 3)
        offset += nv * 3 * 4
        norms = np.frombuffer(data, dtype=np.float32, count=nv * 3, offset=offset).reshape(nv, 3)
        offset += nv * 3 * 4

        ni = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        idxs = np.frombuffer(data, dtype=np.uint32, count=ni, offset=offset)
        offset += ni * 4

        cr, cg, cb, _ = struct.unpack_from("<BBBB", data, offset)
        offset += 4

        result["buildings"].append({
            "center": (lon, lat),
            "vertices": verts,
            "normals": norms,
            "indices": idxs,
            "color": (cr, cg, cb),
        })

    for _ in range(num_roads):
        lat, lon = struct.unpack_from("<ff", data, offset)
        offset += struct.calcsize("<ff")
        rtype_len = struct.unpack_from("<H", data, offset)[0]
        offset += 2
        rtype = data[offset:offset + rtype_len].decode("ascii")
        offset += rtype_len

        nv = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        verts = np.frombuffer(data, dtype=np.float32, count=nv * 3, offset=offset).reshape(nv, 3)
        offset += nv * 3 * 4
        norms = np.frombuffer(data, dtype=np.float32, count=nv * 3, offset=offset).reshape(nv, 3)
        offset += nv * 3 * 4

        ni = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        idxs = np.frombuffer(data, dtype=np.uint32, count=ni, offset=offset)
        offset += ni * 4

        cr, cg, cb, _ = struct.unpack_from("<BBBB", data, offset)
        offset += 4

        result["roads"].append({
            "center": (lon, lat),
            "road_type": rtype,
            "vertices": verts,
            "normals": norms,
            "indices": idxs,
            "color": (cr, cg, cb),
        })

    if has_terrain:
        nv = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        verts = np.frombuffer(data, dtype=np.float32, count=nv * 3, offset=offset).reshape(nv, 3)
        offset += nv * 3 * 4
        norms = np.frombuffer(data, dtype=np.float32, count=nv * 3, offset=offset).reshape(nv, 3)
        offset += nv * 3 * 4
        ni = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        idxs = np.frombuffer(data, dtype=np.uint32, count=ni, offset=offset)
        offset += ni * 4

        result["terrain"] = {
            "vertices": verts,
            "normals": norms,
            "indices": idxs,
        }

    log.info(
        "Loaded tile %s: %d buildings, %d roads, terrain=%s, total=%d bytes",
        filepath.name,
        num_buildings,
        num_roads,
        bool(has_terrain),
        len(data),
    )

    return result
