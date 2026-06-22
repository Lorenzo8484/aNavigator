"""Road processor — convert OSM road ways to flat 3D road surfaces."""

from __future__ import annotations

import logging
from typing import Any, Optional

import numpy as np
from shapely.geometry import LineString, MultiLineString, shape as shapely_shape

from config import (
    LOG_FORMAT,
    LOG_LEVEL,
    ROAD_COLORS,
    ROAD_WIDTHS,
)

log = logging.getLogger("road_processor")
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO), format=LOG_FORMAT)


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

class RoadMesh:
    """A single road segment mesh.

    Attributes
    ----------
    vertices : np.ndarray  (N, 3) float32
    normals  : np.ndarray  (N, 3) float32  — upward normals
    indices  : np.ndarray  (M, 3) uint32   — triangle index triplets
    color    : tuple[int,int,int]          — RGB asphalt colour
    center   : tuple[float,float]          — (lon, lat) midpoint
    road_type : str                        — highway tag value
    name     : Optional[str]               — road name, if available
    """

    __slots__ = ("vertices", "normals", "indices", "color", "center", "road_type", "name")

    def __init__(
        self,
        vertices: np.ndarray,
        normals: np.ndarray,
        indices: np.ndarray,
        color: tuple[int, int, int],
        center: tuple[float, float],
        road_type: str = "default",
        name: Optional[str] = None,
    ) -> None:
        self.vertices = np.asarray(vertices, dtype=np.float32)
        self.normals = np.asarray(normals, dtype=np.float32)
        self.indices = np.asarray(indices, dtype=np.uint32)
        self.color = color
        self.center = center
        self.road_type = road_type
        self.name = name

    @property
    def vertex_count(self) -> int:
        return self.vertices.shape[0]

    @property
    def index_count(self) -> int:
        return self.indices.shape[0] * 3

    def __repr__(self) -> str:
        return (
            f"RoadMesh(verts={self.vertex_count}, "
            f"tris={self.indices.shape[0]}, "
            f"type={self.road_type}, "
            f"name={self.name or 'unnamed'})"
        )


# ---------------------------------------------------------------------------
# Road width / colour helpers
# ---------------------------------------------------------------------------

def _get_road_width(highway_tag: str) -> float:
    """Get road width in metres based on highway classification."""
    return ROAD_WIDTHS.get(highway_tag, ROAD_WIDTHS["default"])


def _get_road_color(highway_tag: str) -> tuple[int, int, int]:
    """Get road colour based on highway classification."""
    # Map OSM highway types to our colour categories
    if highway_tag in ("motorway", "motorway_link", "trunk", "trunk_link"):
        return ROAD_COLORS["autostrada"]
    elif highway_tag in ("primary", "primary_link"):
        return ROAD_COLORS["primaria"]
    elif highway_tag in ("secondary", "secondary_link", "tertiary", "tertiary_link"):
        return ROAD_COLORS["secondaria"]
    elif highway_tag in (
        "residential", "living_street", "unclassified", "service",
        "pedestrian", "track", "footway", "path", "cycleway",
    ):
        return ROAD_COLORS["residenziale"]
    else:
        return ROAD_COLORS["default"]


# ---------------------------------------------------------------------------
# Mesh generation
# ---------------------------------------------------------------------------

def _offset_line(
    coords: np.ndarray,
    width: float,
) -> tuple[np.ndarray, np.ndarray]:
    """Offset a polyline to create a ribbon (two parallel sides).

    Parameters
    ----------
    coords : (N, 2) array of (lon, lat) points
    width  : total width of the road in metres

    Returns
    -------
    left_coords  : (N, 2) left edge
    right_coords : (N, 2) right edge
    """
    if len(coords) < 2:
        return coords.copy(), coords.copy()

    half = width / 2.0

    # Approximate metre-per-degree scaling at given latitude
    # This is a rough conversion; for a proper implementation we'd project.
    lat = np.mean(coords[:, 1])
    lat_rad = np.deg2rad(lat)
    m_per_deg_lon = 111320.0 * np.cos(lat_rad)
    m_per_deg_lat = 110540.0  # roughly constant

    # Guard against poles
    if abs(m_per_deg_lon) < 1.0:
        m_per_deg_lon = 111320.0

    left = np.zeros_like(coords)
    right = np.zeros_like(coords)

    left[0] = _offset_point(coords[0], coords[1], half, m_per_deg_lon, m_per_deg_lat, -1)
    right[0] = _offset_point(coords[0], coords[1], half, m_per_deg_lon, m_per_deg_lat, +1)

    for i in range(1, len(coords) - 1):
        # Average direction of incoming and outgoing segments
        prev_dir = coords[i] - coords[i - 1]
        next_dir = coords[i + 1] - coords[i]

        avg_dir = prev_dir / (np.linalg.norm(prev_dir) + 1e-12) + \
                  next_dir / (np.linalg.norm(next_dir) + 1e-12)

        if np.linalg.norm(avg_dir) < 1e-12:
            avg_dir = prev_dir

        perp = np.array([-avg_dir[1], avg_dir[0]])
        perp_norm = np.linalg.norm(perp)
        if perp_norm < 1e-12:
            perp = np.array([1.0, 0.0])
        else:
            perp = perp / perp_norm

        lon_offset = perp[0] / m_per_deg_lon
        lat_offset = perp[1] / m_per_deg_lat

        left[i] = coords[i] + np.array([-lon_offset, -lat_offset]) * half
        right[i] = coords[i] + np.array([lon_offset, lat_offset]) * half

    left[-1] = _offset_point(coords[-1], coords[-2], half, m_per_deg_lon, m_per_deg_lat, +1)
    right[-1] = _offset_point(coords[-1], coords[-2], half, m_per_deg_lon, m_per_deg_lat, -1)

    return left, right


def _offset_point(
    pt: np.ndarray,
    neighbor: np.ndarray,
    half: float,
    m_per_deg_lon: float,
    m_per_deg_lat: float,
    direction: int,
) -> np.ndarray:
    """Offset a single point perpendicular to the direction to neighbor.

    direction = -1 → left, +1 → right
    """
    delta = neighbor - pt
    d_norm = np.linalg.norm(delta)
    if d_norm < 1e-12:
        delta = np.array([1.0, 0.0])
    else:
        delta = delta / d_norm

    perp = np.array([-delta[1], delta[0]])
    lon_off = perp[0] / m_per_deg_lon
    lat_off = perp[1] / m_per_deg_lat
    return pt + np.array([lon_off, lat_off]) * half * direction


def _road_to_mesh(
    coords: list[tuple[float, float]],
    width: float,
    color: tuple[int, int, int],
    center: tuple[float, float],
    road_type: str,
    name: Optional[str],
    z: float = 0.05,  # slightly above ground to avoid z-fighting
) -> Optional[RoadMesh]:
    """Convert a list of coordinate pairs into a flat road surface mesh."""
    if len(coords) < 2:
        return None

    pts = np.array(coords, dtype=np.float64)

    left, right = _offset_line(pts, width)

    n = len(left)
    # Build vertices: left edge then right edge, all at height z
    left_3d = np.hstack([left, np.full((n, 1), z)])
    right_3d = np.hstack([right, np.full((n, 1), z)])

    # Interleave for proper triangulation: left[0], right[0], left[1], right[1], ...
    vertices = np.empty((n * 2, 3), dtype=np.float32)
    vertices[0::2] = left_3d
    vertices[1::2] = right_3d

    # Upward normals for flat road surface
    normals = np.tile(np.array([0.0, 0.0, 1.0], dtype=np.float32), (n * 2, 1))

    # Triangle indices: each quad (li, ri, li+1, ri+1) → 2 triangles
    indices = []
    for i in range(n - 1):
        li = i * 2
        ri = i * 2 + 1
        li1 = (i + 1) * 2
        ri1 = (i + 1) * 2 + 1
        # Triangle 1: li, ri, li1
        indices.append([li, ri, li1])
        # Triangle 2: ri, ri1, li1
        indices.append([ri, ri1, li1])

    if not indices:
        return None

    return RoadMesh(
        vertices=vertices,
        normals=normals,
        indices=np.array(indices, dtype=np.uint32),
        color=color,
        center=center,
        road_type=road_type,
        name=name,
    )


def _process_feature(
    feature: dict[str, Any],
) -> list[RoadMesh]:
    """Process one OSM road feature into road mesh(es)."""
    tags = feature.get("tags", {})
    highway = tags.get("highway", "").lower()

    # Skip non-drivable/non-physical highway types that are not useful as surfaces
    if highway in ("bus_stop", "platform", "rest_area", "services", "construction", "proposed"):
        return []

    width = _get_road_width(highway)
    color = _get_road_color(highway)
    name = tags.get("name")

    geom_data = feature.get("geometry")
    if geom_data is None:
        return []

    try:
        geom = shapely_shape(geom_data)
    except Exception as exc:
        log.warning("Failed to parse road geometry: %s", exc)
        return []

    meshes: list[RoadMesh] = []

    if isinstance(geom, LineString):
        coords = list(geom.coords)
        if len(coords) >= 2:
            center_lon = float(np.mean([c[0] for c in coords]))
            center_lat = float(np.mean([c[1] for c in coords]))
            mesh = _road_to_mesh(coords, width, color, (center_lon, center_lat), highway, name)
            if mesh:
                meshes.append(mesh)

    elif isinstance(geom, MultiLineString):
        for line in geom.geoms:
            coords = list(line.coords)
            if len(coords) >= 2:
                center_lon = float(np.mean([c[0] for c in coords]))
                center_lat = float(np.mean([c[1] for c in coords]))
                mesh = _road_to_mesh(coords, width, color, (center_lon, center_lat), highway, name)
                if mesh:
                    meshes.append(mesh)

    return meshes


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def process_roads(
    features: list[dict[str, Any]],
) -> list[RoadMesh]:
    """Process a list of OSM road features into 3D road surface meshes.

    Parameters
    ----------
    features : list of dicts with 'geometry' and 'tags' keys

    Returns
    -------
    list of RoadMesh
    """
    log.info("Processing %d road features ...", len(features))
    meshes: list[RoadMesh] = []

    for i, feat in enumerate(features):
        try:
            results = _process_feature(feat)
            meshes.extend(results)
        except Exception as exc:
            log.warning("Failed to process road %d: %s", i, exc)
            continue

    log.info(
        "  -> Generated %d road meshes (from %d features)",
        len(meshes),
        len(features),
    )
    return meshes
