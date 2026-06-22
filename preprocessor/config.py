"""Configuration settings for the scenekit-italy preprocessor."""

import os
from pathlib import Path

# ---------------------------------------------------------------------------
# Tile / geographic settings
# ---------------------------------------------------------------------------

# Tile size in degrees.  ~0.01° ≈ 1 km at mid latitudes.
TILE_SIZE: float = 0.01

# Approximate bounding box of Italy (lon_min, lat_min, lon_max, lat_max).
ITALY_BBOX: tuple[float, float, float, float] = (6.6, 36.6, 18.5, 47.1)

# Number of decimal places to round coordinates to (improves dedup / file size).
COORD_PRECISION: int = 7

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# Root directory for all preprocessor output.
OUTPUT_DIR: Path = Path(__file__).resolve().parent / "output"

# Sub-directories per data type
TILES_DIR: Path = OUTPUT_DIR / "tiles"
TEXTURES_DIR: Path = OUTPUT_DIR / "textures"
CACHE_DIR: Path = OUTPUT_DIR / "cache"
LOGS_DIR: Path = OUTPUT_DIR / "logs"

# Ensure directories exist at import time.
_mkdirs = (OUTPUT_DIR, TILES_DIR, TEXTURES_DIR, CACHE_DIR, LOGS_DIR)
for _d in _mkdirs:
    _d.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Texture settings
# ---------------------------------------------------------------------------

TEXTURE_SIZE_4K: int = 4096  # 4K atlas dimensions
TEXTURE_SIZE_2K: int = 2048  # fallback

# ---------------------------------------------------------------------------
# Building colours (RGB tuples, 0-255)
# ---------------------------------------------------------------------------
BUILDING_COLORS: dict[str, tuple[int, int, int]] = {
    "residenziale": (0xD4, 0xC5, 0xA9),  # warm beige
    "commerciale":  (0x8F, 0xA8, 0xC0),  # steel blue
    "industriale":  (0xA0, 0xA0, 0xA0),  # grey
    "chiesa":       (0xC0, 0x40, 0x40),  # reddish
    "scuola":       (0xD4, 0xA0, 0x60),  # warm orange
    "default":      (0xC0, 0xB0, 0x90),  # tan
}

# ---------------------------------------------------------------------------
# Road colours (RGB tuples, 0-255)
# ---------------------------------------------------------------------------
ROAD_COLORS: dict[str, tuple[int, int, int]] = {
    "autostrada":   (0xD0, 0xD0, 0xD0),  # light grey
    "primaria":     (0xE0, 0xE0, 0xE0),  # slightly lighter
    "secondaria":   (0xF0, 0xF0, 0xF0),  # near-white
    "residenziale": (0xF5, 0xF5, 0xF5),  # white-ish
    "default":      (0xE8, 0xE8, 0xE8),
}

# ---------------------------------------------------------------------------
# Road widths in metres (scene units) — approximate Italian standards
# ---------------------------------------------------------------------------
ROAD_WIDTHS: dict[str, float] = {
    "motorway":       15.0,
    "motorway_link":   8.0,
    "trunk":          14.0,
    "trunk_link":      7.0,
    "primary":        12.0,
    "primary_link":    6.0,
    "secondary":      10.0,
    "secondary_link":  5.0,
    "tertiary":        8.0,
    "tertiary_link":   4.0,
    "unclassified":    6.0,
    "residential":     6.0,
    "living_street":   4.0,
    "service":         4.0,
    "pedestrian":      3.0,
    "track":           3.0,
    "footway":         2.0,
    "path":            2.0,
    "cycleway":        2.5,
    "default":         5.0,
}

# ---------------------------------------------------------------------------
# Building height defaults
# ---------------------------------------------------------------------------
DEFAULT_BUILDING_HEIGHT: float = 8.0          # metres
HEIGHT_PER_LEVEL: float = 3.0                 # average floor-to-floor
MAX_BUILDING_HEIGHT: float = 200.0            # sanity clamp

# ---------------------------------------------------------------------------
# Overpass API
# ---------------------------------------------------------------------------
OVERPASS_API_URL: str = "https://overpass-api.de/api/interpreter"
OVERPASS_TIMEOUT: int = 120  # seconds
OVERPASS_MAX_RETRIES: int = 3

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOG_LEVEL: str = os.environ.get("SCENEKIT_LOG", "INFO")
LOG_FORMAT: str = (
    "[%(asctime)s] %(levelname)-8s %(name)s  %(message)s"
)
