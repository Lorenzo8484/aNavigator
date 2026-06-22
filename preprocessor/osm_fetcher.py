"""OSM data fetcher — downloads OSM data via Overpass API with caching."""

from __future__ import annotations

import hashlib
import json
import logging
import time
from pathlib import Path
from typing import Any, Optional
from urllib.parse import urlencode

import requests

from config import (
    CACHE_DIR,
    LOG_FORMAT,
    LOG_LEVEL,
    OVERPASS_API_URL,
    OVERPASS_MAX_RETRIES,
    OVERPASS_TIMEOUT,
)

log = logging.getLogger("osm_fetcher")
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO), format=LOG_FORMAT)

# ---------------------------------------------------------------------------
# Optional osmnx import
# ---------------------------------------------------------------------------
try:
    import osmnx as ox

    OSMNX_AVAILABLE = True
    log.info("osmnx is available — will use it for data fetching")
except ImportError:
    OSMNX_AVAILABLE = False
    log.warning("osmnx not installed — falling back to direct Overpass API calls")

try:
    import geopandas as gpd
except ImportError:
    # Fallback: define a stub for type hints only
    from pandas import DataFrame as _DF

    class gpd:  # type: ignore
        class GeoDataFrame(_DF):  # type: ignore
            pass


# ---------------------------------------------------------------------------
# Cache helpers
# ---------------------------------------------------------------------------
def _cache_path(bbox: tuple[float, float, float, float]) -> Path:
    """Return a unique cache file path for a given bounding box."""
    key = f"{bbox[0]:.4f}_{bbox[1]:.4f}_{bbox[2]:.4f}_{bbox[3]:.4f}"
    hashed = hashlib.sha256(key.encode()).hexdigest()[:16]
    return CACHE_DIR / f"osm_{hashed}.json"


def _load_cached(cache_file: Path) -> Optional[dict[str, Any]]:
    if cache_file.exists():
        try:
            with open(cache_file, "r") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError) as exc:
            log.warning("Failed to read cache %s: %s", cache_file, exc)
    return None


def _save_cache(cache_file: Path, data: dict[str, Any]) -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        with open(cache_file, "w") as f:
            json.dump(data, f)
        log.debug("Cached result -> %s", cache_file)
    except OSError as exc:
        log.warning("Failed to write cache %s: %s", cache_file, exc)


# ---------------------------------------------------------------------------
# Overpass queries
# ---------------------------------------------------------------------------
BUILDINGS_QUERY_TEMPLATE = """
[out:json][timeout:{timeout}];
(
  way["building"]({south},{west},{north},{east});
  relation["building"]({south},{west},{north},{east});
);
out center tags;
""".strip()

ROADS_QUERY_TEMPLATE = """
[out:json][timeout:{timeout}];
(
  way["highway"]({south},{west},{north},{east});
);
out body;
>;  # emit child nodes for full geometry
out skel qt;
""".strip()

FULL_QUERY_TEMPLATE = """
[out:json][timeout:{timeout}];
(
  way["building"]({south},{west},{north},{east});
  relation["building"]({south},{west},{north},{east});
  way["highway"]({south},{west},{north},{east});
);
out body;
>;  # emit child nodes
out skel qt;
""".strip()


def _build_query(
    bbox: tuple[float, float, float, float],
    mode: str = "full",
) -> str:
    """Build an Overpass QL query for the given bounding box.

    Parameters
    ----------
    bbox : (lon_min, lat_min, lon_max, lat_max)
    mode : 'buildings', 'roads', or 'full'

    Returns
    -------
    Query string.
    """
    west, south, east, north = bbox  # Overpass uses (south, west, north, east)
    kwargs = {
        "south": south,
        "west": west,
        "north": north,
        "east": east,
        "timeout": OVERPASS_TIMEOUT,
    }

    if mode == "buildings":
        return BUILDINGS_QUERY_TEMPLATE.format(**kwargs)
    elif mode == "roads":
        return ROADS_QUERY_TEMPLATE.format(**kwargs)
    else:
        return FULL_QUERY_TEMPLATE.format(**kwargs)


# ---------------------------------------------------------------------------
# osmnx-based fetcher
# ---------------------------------------------------------------------------
def _gdf_to_features(gdf: "gpd.GeoDataFrame") -> list[dict[str, Any]]:
    """Convert a GeoDataFrame from osmnx to our feature dict format."""
    features: list[dict[str, Any]] = []
    for _, row in gdf.iterrows():
        geom = row.get("geometry")
        if geom is None:
            continue
        # Collect all non-geometry columns as tags; osmnx stores OSM tags
        # as columns with string values.
        tags: dict[str, str] = {}
        for col in gdf.columns:
            val = row.get(col)
            if col != "geometry" and isinstance(val, str) and val:
                tags[col] = val
        try:
            features.append({
                "geometry": geom.__geo_interface__,
                "tags": tags,
            })
        except Exception:
            continue
    return features


def _fetch_via_osmnx(
    bbox: tuple[float, float, float, float],
    mode: str = "full",
) -> dict[str, Any]:
    """Fetch OSM data using osmnx (v2.x API).

    Returns a dict with 'buildings' and 'roads' lists (each containing
    GeoJSON-like feature dicts).
    """
    west, south, east, north = bbox
    log.info("osmnx fetching bbox (%.4f, %.4f, %.4f, %.4f)", west, south, east, north)

    result: dict[str, Any] = {"buildings": [], "roads": []}

    try:
        if mode in ("full", "buildings"):
            log.debug("  -> osmnx: fetching buildings")
            # osmnx v2.x uses features_from_bbox(bbox, tags)
            # bbox = (left, bottom, right, top) = (west, south, east, north)
            gdf_b = ox.features_from_bbox(
                (west, south, east, north),
                {"building": True},
            )
            if gdf_b is not None and not gdf_b.empty:
                result["buildings"] = _gdf_to_features(gdf_b)
                log.info("  -> osmnx: %d buildings", len(result["buildings"]))
            else:
                log.info("  -> osmnx: no buildings found")

        if mode in ("full", "roads"):
            log.debug("  -> osmnx: fetching roads")
            gdf_r = ox.features_from_bbox(
                (west, south, east, north),
                {"highway": True},
            )
            if gdf_r is not None and not gdf_r.empty:
                result["roads"] = _gdf_to_features(gdf_r)
                log.info("  -> osmnx: %d roads", len(result["roads"]))
            else:
                log.info("  -> osmnx: no roads found")

    except Exception as exc:
        log.error("osmnx fetch failed: %s", exc, exc_info=True)
        raise

    return result


# ---------------------------------------------------------------------------
# Direct Overpass API fetcher
# ---------------------------------------------------------------------------
def _fetch_via_overpass(
    bbox: tuple[float, float, float, float],
    mode: str = "full",
) -> dict[str, Any]:
    """Fetch OSM data via direct Overpass API call (without osmnx).

    Returns a dict with 'buildings' and 'roads' lists.
    """
    west, south, east, north = bbox
    query = _build_query(bbox, mode)
    log.info("Overpass fetching bbox (%.4f, %.4f, %.4f, %.4f)", west, south, east, north)

    last_exc: Optional[Exception] = None
    for attempt in range(1, OVERPASS_MAX_RETRIES + 1):
        try:
            log.debug("  Overpass attempt %d/%d", attempt, OVERPASS_MAX_RETRIES)
            resp = requests.post(
                OVERPASS_API_URL,
                data={"data": query},
                timeout=OVERPASS_TIMEOUT,
                headers={"User-Agent": "scenekit-italy-preprocessor/1.0"},
            )
            resp.raise_for_status()
            raw: dict[str, Any] = resp.json()
            log.debug("  Overpass response: %d elements", len(raw.get("elements", [])))
            return _parse_overpass_response(raw)
        except requests.RequestException as exc:
            last_exc = exc
            log.warning("  Attempt %d failed: %s", attempt, exc)
            if attempt < OVERPASS_MAX_RETRIES:
                wait = 2 ** attempt
                log.info("  Retrying in %ds ...", wait)
                time.sleep(wait)

    raise RuntimeError(
        f"Overpass API failed after {OVERPASS_MAX_RETRIES} attempts: {last_exc}"
    )


def _parse_overpass_response(
    raw: dict[str, Any],
) -> dict[str, Any]:
    """Parse raw Overpass JSON into {'buildings': [...], 'roads': [...]} dicts."""
    elements = raw.get("elements", [])
    nodes_map: dict[int, tuple[float, float]] = {}

    # First pass: collect node coordinates
    for el in elements:
        if el.get("type") == "node":
            nodes_map[el["id"]] = (float(el.get("lon", 0)), float(el.get("lat", 0)))

    result: dict[str, Any] = {"buildings": [], "roads": []}

    for el in elements:
        el_type = el.get("type")
        if el_type not in ("way", "relation"):
            continue
        tags = el.get("tags", {})

        # -- Buildings --
        if "building" in tags:
            coords = _extract_coords(el, nodes_map)
            if not coords:
                continue
            geom = {"type": "Polygon", "coordinates": [coords]}
            result["buildings"].append({"geometry": geom, "tags": dict(tags)})

        # -- Roads (highways) --
        if "highway" in tags and el_type == "way":
            coords = _extract_coords(el, nodes_map)
            if not coords:
                continue
            geom_type = "Polygon" if coords[0] == coords[-1] else "LineString"
            geom = {"type": geom_type, "coordinates": coords}
            result["roads"].append({"geometry": geom, "tags": dict(tags)})

    log.info("  Parsed: %d buildings, %d roads", len(result["buildings"]), len(result["roads"]))
    return result


def _extract_coords(
    element: dict[str, Any],
    nodes_map: dict[int, tuple[float, float]],
) -> list[tuple[float, float]]:
    """Extract ordered coordinate pairs from a way/relation element."""
    nodes = element.get("nodes", [])
    coords: list[tuple[float, float]] = []
    for nid in nodes:
        pt = nodes_map.get(nid)
        if pt is not None:
            coords.append(pt)
    return coords


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def fetch_tile(
    bbox: tuple[float, float, float, float],
    mode: str = "full",
    use_cache: bool = True,
    force_osmnx: bool = False,
) -> dict[str, Any]:
    """Fetch OSM data for a single tile (bounding box).

    Parameters
    ----------
    bbox : (lon_min, lat_min, lon_max, lat_max)
    mode : 'buildings', 'roads', or 'full'
    use_cache : if True, cache and re-use responses
    force_osmnx : if True, always use osmnx even if not the default

    Returns
    -------
    dict with keys 'buildings' and 'roads'.
    """
    cache_file = _cache_path(bbox)

    # Check cache
    if use_cache:
        cached = _load_cached(cache_file)
        if cached is not None:
            log.info("Cache hit for bbox %s", bbox)
            return cached

    # Fetch
    if OSMNX_AVAILABLE or force_osmnx:
        data = _fetch_via_osmnx(bbox, mode)
    else:
        data = _fetch_via_overpass(bbox, mode)

    # Save to cache
    if use_cache:
        _save_cache(cache_file, data)

    return data
