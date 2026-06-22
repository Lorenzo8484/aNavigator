"""Terrain processor — generate flat ground plane meshes for tiles."""

from __future__ import annotations

import logging
from typing import Optional

import numpy as np

from config import (
    LOG_FORMAT,
    LOG_LEVEL,
    TILE_SIZE,
)

log = logging.getLogger("terrain_processor")
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO), format=LOG_FORMAT)


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

class TerrainMesh:
    """A ground plane mesh for one tile.

    Attributes
    ----------
    vertices : np.ndarray  (N, 3) float32  — (lon, lat, z)
    normals  : np.ndarray  (N, 3) float32
    indices  : np.ndarray  (M, 3) uint32
    bbox     : tuple[float, float, float, float]  — (lon_min, lat_min, lon_max, lat_max)
    """

    __slots__ = ("vertices", "normals", "indices", "bbox")

    def __init__(
        self,
        vertices: np.ndarray,
        normals: np.ndarray,
        indices: np.ndarray,
        bbox: tuple[float, float, float, float],
    ) -> None:
        self.vertices = np.asarray(vertices, dtype=np.float32)
        self.normals = np.asarray(normals, dtype=np.float32)
        self.indices = np.asarray(indices, dtype=np.uint32)
        self.bbox = bbox

    @property
    def vertex_count(self) -> int:
        return self.vertices.shape[0]

    @property
    def index_count(self) -> int:
        return self.indices.shape[0] * 3

    def __repr__(self) -> str:
        return (
            f"TerrainMesh(verts={self.vertex_count}, "
            f"tris={self.indices.shape[0]}, "
            f"bbox=({self.bbox[0]:.4f}, {self.bbox[1]:.4f}, "
            f"{self.bbox[2]:.4f}, {self.bbox[3]:.4f}))"
        )


# ---------------------------------------------------------------------------
# Mesh generation
# ---------------------------------------------------------------------------

def generate_terrain(
    bbox: tuple[float, float, float, float],
    subdivisions: int = 2,
    z: float = 0.0,
    add_grid: bool = False,
    grid_line_width: float = 0.00005,
) -> TerrainMesh:
    """Generate a flat terrain mesh for the given bounding box.

    Parameters
    ----------
    bbox : (lon_min, lat_min, lon_max, lat_max)
    subdivisions :
        Number of subdivisions per edge. 1 = 4 vertices (simple quad),
        2 = 9 vertices (4 quads), etc. Higher values ≈ more detailed ground.
    z : Elevation (default 0.0).  Used as flat plane.
    add_grid : If True, add grid lines on top of the terrain surface.
        When True, the returned mesh includes both the surface and grid
        line geometry.
    grid_line_width : Spacing between grid lines in degrees (lat/lon).

    Returns
    -------
    TerrainMesh
    """
    lon_min, lat_min, lon_max, lat_max = bbox
    log.info(
        "Generating terrain for bbox (%.4f, %.4f, %.4f, %.4f), "
        "subdivisions=%d, grid=%s",
        lon_min, lat_min, lon_max, lat_max,
        subdivisions,
        add_grid,
    )

    # ---- Surface mesh ----
    # Build a regular grid of vertices
    nx = subdivisions + 1
    ny = subdivisions + 1

    lons = np.linspace(lon_min, lon_max, nx)
    lats = np.linspace(lat_min, lat_max, ny)

    # Create vertex grid
    grid_lons, grid_lats = np.meshgrid(lons, lats)
    vertices = np.zeros((nx * ny, 3), dtype=np.float32)
    vertices[:, 0] = grid_lons.ravel()
    vertices[:, 1] = grid_lats.ravel()
    vertices[:, 2] = z

    # Upward normals for all vertices
    normals = np.tile(np.array([0.0, 0.0, 1.0], dtype=np.float32), (nx * ny, 1))

    # Triangle indices for the regular grid
    indices = []
    for j in range(ny - 1):
        for i in range(nx - 1):
            idx = j * nx + i
            # Quad: (idx, idx+1, idx+nx) and (idx+1, idx+nx+1, idx+nx)
            # Two triangles
            indices.append([idx, idx + 1, idx + nx])
            indices.append([idx + 1, idx + nx + 1, idx + nx])

    # ---- Optional grid lines ----
    if add_grid and grid_line_width > 0:
        grid_vertices: list[np.ndarray] = []
        grid_indices: list[list[int]] = []
        base_vertex_count = vertices.shape[0]

        # Generate grid lines at regular intervals
        lat_step = grid_line_width
        lon_step = grid_line_width

        # Horizontal lines (constant latitude)
        lat = lat_min
        line_idx = base_vertex_count
        while lat <= lat_max:
            pts = np.array([
                [lon_min, lat, z + 0.01],   # slightly above terrain
                [lon_max, lat, z + 0.01],
            ], dtype=np.float32)
            grid_vertices.append(pts)
            grid_indices.append([line_idx, line_idx + 1])
            line_idx += 2
            lat += lat_step

        # Vertical lines (constant longitude)
        lon = lon_min
        while lon <= lon_max:
            pts = np.array([
                [lon, lat_min, z + 0.01],
                [lon, lat_max, z + 0.01],
            ], dtype=np.float32)
            grid_vertices.append(pts)
            grid_indices.append([line_idx, line_idx + 1])
            line_idx += 2
            lon += lon_step

        if grid_vertices:
            grid_verts = np.vstack(grid_vertices)
            vertices = np.vstack([vertices, grid_verts])

            # Add grid line normals (upward)
            grid_norms = np.tile(
                np.array([0.0, 0.0, 1.0], dtype=np.float32),
                (grid_verts.shape[0], 1),
            )
            normals = np.vstack([normals, grid_norms])

            # Grid lines as thin triangle strips (each line is a thin quad)
            for a, b in grid_indices:
                # Make a thin quad from the line segment
                indices.append([a, b, a])
                indices.append([b, b, a])

    terrain = TerrainMesh(
        vertices=vertices,
        normals=normals,
        indices=np.array(indices, dtype=np.uint32),
        bbox=bbox,
    )

    log.info("  -> Terrain: %d vertices, %d triangles", terrain.vertex_count, terrain.indices.shape[0])
    return terrain


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def generate_flat_terrain(
    bbox: tuple[float, float, float, float],
    z: float = 0.0,
    subdivisions: int = 4,
    include_grid: bool = False,
) -> TerrainMesh:
    """Generate a flat terrain mesh (convenience wrapper).

    Parameters
    ----------
    bbox : (lon_min, lat_min, lon_max, lat_max)
    z : base elevation
    subdivisions : grid subdivisions per edge
    include_grid : whether to overlay a coordinate grid

    Returns
    -------
    TerrainMesh
    """
    return generate_terrain(
        bbox=bbox,
        subdivisions=subdivisions,
        z=z,
        add_grid=include_grid,
    )
