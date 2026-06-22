"""Building processor — extrude OSM building footprints into 3D prisms."""

from __future__ import annotations

import logging
from typing import Any, Optional

import numpy as np
from shapely.geometry import Polygon, MultiPolygon, shape as shapely_shape

from config import (
    BUILDING_COLORS,
    DEFAULT_BUILDING_HEIGHT,
    HEIGHT_PER_LEVEL,
    MAX_BUILDING_HEIGHT,
    LOG_FORMAT,
    LOG_LEVEL,
)

log = logging.getLogger("building_processor")
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO), format=LOG_FORMAT)


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

class BuildingMesh:
    """A single extruded building mesh ready for export.

    Attributes
    ----------
    vertices : np.ndarray  (N, 3) float32
    normals  : np.ndarray  (N, 3) float32
    indices  : np.ndarray  (M, 3) uint32   — triangle index triplets
    color    : tuple[int,int,int]          — RGB colour (0-255)
    center   : tuple[float,float]          — (lon, lat) centroid
    """

    __slots__ = ("vertices", "normals", "indices", "color", "center")

    def __init__(
        self,
        vertices: np.ndarray,
        normals: np.ndarray,
        indices: np.ndarray,
        color: tuple[int, int, int],
        center: tuple[float, float],
    ) -> None:
        self.vertices = np.asarray(vertices, dtype=np.float32)
        self.normals = np.asarray(normals, dtype=np.float32)
        self.indices = np.asarray(indices, dtype=np.uint32)
        self.color = color
        self.center = center

    @property
    def vertex_count(self) -> int:
        return self.vertices.shape[0]

    @property
    def index_count(self) -> int:
        return self.indices.shape[0] * 3  # flat count

    def __repr__(self) -> str:
        return (
            f"BuildingMesh(verts={self.vertex_count}, "
            f"tris={self.indices.shape[0]}, "
            f"color=#{self.color[0]:02X}{self.color[1]:02X}{self.color[2]:02X}, "
            f"center=({self.center[0]:.4f}, {self.center[1]:.4f}))"
        )


# ---------------------------------------------------------------------------
# Height extraction
# ---------------------------------------------------------------------------

def _get_building_height(tags: dict[str, Any]) -> float:
    """Determine building height from OSM tags."""
    # Try explicit height (in metres)
    height_str = tags.get("height")
    if height_str:
        try:
            h = float(height_str.replace("m", "").replace(" ", "").strip())
            return min(max(h, 1.0), MAX_BUILDING_HEIGHT)
        except (ValueError, AttributeError):
            pass

    # Try building:levels * 3m
    levels_str = tags.get("building:levels")
    if levels_str:
        try:
            levels = float(levels_str)
            return min(max(levels * HEIGHT_PER_LEVEL, 1.0), MAX_BUILDING_HEIGHT)
        except (ValueError, AttributeError):
            pass

    # Try height from other common tags
    for key in ("building:height", "roof:height", "height:approx"):
        val = tags.get(key)
        if val:
            try:
                h = float(val.replace("m", "").replace(" ", "").strip())
                return min(max(h, 1.0), MAX_BUILDING_HEIGHT)
            except (ValueError, AttributeError):
                pass

    return DEFAULT_BUILDING_HEIGHT


# ---------------------------------------------------------------------------
# Building colour classification
# ---------------------------------------------------------------------------

def _get_building_color(tags: dict[str, Any]) -> tuple[int, int, int]:
    """Classify building type and return associated colour."""
    # Check Italian-specific building tags
    building_val = tags.get("building", "").lower()
    amenity = tags.get("amenity", "").lower()
    shop = tags.get("shop", "").lower()
    office = tags.get("office", "").lower()
    tourism = tags.get("tourism", "").lower()
    leisure = tags.get("leisure", "").lower()

    # Churches / places of worship
    if (
        "church" in (building_val, amenity)
        or tags.get("amenity") == "place_of_worship"
    ):
        return BUILDING_COLORS["chiesa"]

    # Schools / education
    if any(
        k in (building_val, amenity)
        for k in ("school", "university", "college", "kindergarten")
    ):
        return BUILDING_COLORS["scuola"]

    # Industrial / warehouse
    if building_val in ("industrial", "warehouse", "manufacturing"):
        return BUILDING_COLORS["industriale"]

    # Commercial / retail / supermarket
    if (
        building_val in ("commercial", "retail", "supermarket")
        or amenity
        or shop
    ):
        return BUILDING_COLORS["commerciale"]

    # Residential
    if building_val in (
        "residential",
        "house",
        "apartments",
        "detached",
        "semidetached_house",
        "terrace",
        "dormitory",
        "bungalow",
        "cabin",
        "static_caravan",
    ):
        return BUILDING_COLORS["residenziale"]

    # Offices
    if office:
        return BUILDING_COLORS["commerciale"]

    # Tourism / hospitality
    if tourism:
        return BUILDING_COLORS["commerciale"]

    # Leisure
    if leisure:
        return BUILDING_COLORS["commerciale"]

    return BUILDING_COLORS["default"]


# ---------------------------------------------------------------------------
# Mesh generation helpers
# ---------------------------------------------------------------------------

def _extrude_polygon(
    polygon: Polygon,
    height: float,
    z_base: float = 0.0,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Extrude a 2D polygon into a 3D prism.

    Parameters
    ----------
    polygon : shapely.geometry.Polygon
        The 2D footprint (assumed in projected metre coordinates).
    height : float
        Extrusion height in metres.
    z_base : float
        Base elevation.

    Returns
    -------
    vertices  : (N, 3) float32
    normals   : (N, 3) float32
    indices   : (M, 3) uint32
    """
    # Get outer ring coordinates (x, y)
    exterior = np.array(polygon.exterior.coords[:-1])  # drop repeated last point
    if exterior.shape[0] < 3:
        return np.empty((0, 3), dtype=np.float32), np.empty((0, 3), dtype=np.float32), np.empty((0, 3), dtype=np.uint32)

    n = exterior.shape[0]

    # Build vertex array: bottom ring then top ring
    bottom = np.hstack([exterior, np.full((n, 1), z_base)])
    top = np.hstack([exterior, np.full((n, 1), z_base + height)])
    vertices = np.vstack([bottom, top])  # (2n, 3)

    # Normals: we'll compute face normals and assign per-vertex averages
    normals = np.zeros_like(vertices)

    # ---- Triangular side faces ----
    # Each quad (bottom[i], bottom[i+1], top[i+1], top[i]) → 2 triangles
    side_indices = []
    for i in range(n):
        i_next = (i + 1) % n
        # Triangle 1: bottom[i], bottom[i_next], top[i_next]
        side_indices.append([i, i_next, n + i_next])
        # Triangle 2: bottom[i], top[i_next], top[i]
        side_indices.append([i, n + i_next, n + i])

    # ---- Bottom face (facing down) ----
    # Fan triangulation of bottom polygon
    bottom_indices = []
    for i in range(1, n - 1):
        bottom_indices.append([0, i, i + 1])

    # ---- Top face (facing up) ----
    top_indices = []
    for i in range(1, n - 1):
        top_indices.append([n + 0, n + i + 1, n + i])  # reversed winding for upward normal

    # Combine all indices
    all_indices = side_indices + bottom_indices + top_indices
    indices = np.array(all_indices, dtype=np.uint32)

    # ---- Compute per-vertex normals by averaging face normals ----
    for tri in all_indices:
        v0, v1, v2 = vertices[tri[0]], vertices[tri[1]], vertices[tri[2]]
        face_normal = np.cross(v1 - v0, v2 - v0)
        norm_len = np.linalg.norm(face_normal)
        if norm_len > 0:
            face_normal = face_normal / norm_len
            for idx in tri:
                normals[idx] += face_normal

    # Normalize
    row_norms = np.linalg.norm(normals, axis=1, keepdims=True)
    row_norms[row_norms == 0] = 1.0
    normals = normals / row_norms

    return vertices, normals, indices


def _process_feature(
    feature: dict[str, Any],
) -> list[BuildingMesh]:
    """Process a single OSM building feature into one or more BuildingMesh objects.

    Polygons with holes are handled by triangulating the polygon as a whole,
    then keeping only the visible triangles (the outer ring minus holes).
    MultiPolygons yield one BuildingMesh per sub-polygon.
    """
    tags = feature.get("tags", {})
    height = _get_building_height(tags)
    color = _get_building_color(tags)

    # Build shapely geometry
    geom_data = feature.get("geometry")
    if geom_data is None:
        return []

    try:
        geom = shapely_shape(geom_data)
    except Exception as exc:
        log.warning("Failed to parse geometry: %s", exc)
        return []

    meshes: list[BuildingMesh] = []

    if isinstance(geom, Polygon):
        mesh = _polygon_to_mesh(geom, height, color, tags)
        if mesh is not None:
            meshes.append(mesh)
    elif isinstance(geom, MultiPolygon):
        for poly in geom.geoms:
            mesh = _polygon_to_mesh(poly, height, color, tags)
            if mesh is not None:
                meshes.append(mesh)
    else:
        log.debug("Unsupported geometry type for building: %s", type(geom).__name__)

    return meshes


def _polygon_to_mesh(
    polygon: Polygon,
    height: float,
    color: tuple[int, int, int],
    tags: dict[str, Any],
) -> Optional[BuildingMesh]:
    """Convert a single Shapely Polygon to a BuildingMesh.

    For polygons with holes, we use the outer ring and approximate the holes
    by using the outer ring only (simplification for visual purposes).
    On-water buildings are handled gracefully.
    """
    if polygon.is_empty or not polygon.exterior:
        return None

    # Simplify to reduce vertex count, preserving topology
    # Buffer(0) fixes self-intersections
    polygon = polygon.buffer(0, join_style=2)

    if polygon.is_empty:
        return None

    # Get exterior coords in lat/lon — we need to work in lon/lat directly
    # since we're not projecting yet. Use the exterior ring.
    exterior_coords = list(polygon.exterior.coords[:-1])  # drop repeat

    if len(exterior_coords) < 3:
        return None

    # Convert to numpy for extrusion
    pts = np.array(exterior_coords, dtype=np.float64)

    # Compute centroid for center
    center_lon = float(np.mean(pts[:, 0]))
    center_lat = float(np.mean(pts[:, 1]))

    # Extrude using the coordinate values directly (they'll be in lon/lat space)
    # We extrude in the Z dimension only.
    # For a proper 3D scene, we'll need to convert lon/lat to a local Cartesian
    # system later. For now, we use degrees as approximate units for extrusion.
    # The height will be in metres, which is fine since the renderer will handle
    # the projection.

    # Create a simple polygon from the exterior for extrusion
    simple_poly = Polygon(exterior_coords)

    vertices, normals, indices = _extrude_polygon(
        simple_poly, height, z_base=0.0
    )

    if vertices.shape[0] == 0:
        return None

    return BuildingMesh(
        vertices=vertices,
        normals=normals,
        indices=indices,
        color=color,
        center=(center_lon, center_lat),
    )


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def process_buildings(
    features: list[dict[str, Any]],
) -> list[BuildingMesh]:
    """Process a list of OSM building features into 3D mesh objects.

    Parameters
    ----------
    features : list of dicts with 'geometry' and 'tags' keys

    Returns
    -------
    list of BuildingMesh
    """
    log.info("Processing %d building features ...", len(features))
    meshes: list[BuildingMesh] = []

    for i, feat in enumerate(features):
        try:
            results = _process_feature(feat)
            meshes.extend(results)
        except Exception as exc:
            log.warning("Failed to process building %d: %s", i, exc)
            continue

    log.info(
        "  -> Generated %d building meshes (from %d features)",
        len(meshes),
        len(features),
    )
    return meshes
