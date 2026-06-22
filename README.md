# scenekit-italy 🇮🇹

**Italia 3D con SceneKit** — Mappa 3D navigabile dell'Italia renderizzata con SceneKit su iOS.

Edifici, strade e terrain generati da dati OpenStreetMap (OSM) tramite preprocessor Python, visualizzati in 3D con tilt, rotazione e follow GPS.

## Architettura

```
scenekit-italy/
├── preprocessor/          # Python: OSM → mesh 3D
│   ├── main.py            # CLI entry point
│   ├── osm_fetcher.py     # Download dati OSM (Overpass API + osmnx)
│   ├── building_processor.py  # Estrusione edifici 3D
│   ├── road_processor.py  # Superfici stradali 3D
│   ├── terrain_processor.py   # Piano terreno
│   ├── texture_generator.py   # 4K texture atlas (4096×4096)
│   ├── tile_exporter.py   # Export formato binario .stile
│   └── config.py          # Configurazione colori, altezze, tile
├── ios/                   # iOS app SceneKit
│   ├── scenekit-italy/
│   │   ├── Map3DViewController.mm  # ViewController principale
│   │   ├── Scene3DEngine/
│   │   │   ├── TileManager.mm      # Caricamento tile .stile
│   │   │   ├── CameraController.mm # Camera 3D orbitale
│   │   │   └── TextureAtlas.mm     # Texture 4K
│   │   └── ...
│   └── build_ipa.sh
├── data/tiles/            # Tile .stile pre-processati
└── assets/textures/       # Texture atlas 4K
```

## Formato Tile (.stile)

Formato binario compatto per mesh 3D:
```
Magic: "STIL" (4 bytes)
Version: uint32
NumBuildings: uint32
[Per ogni edificio: centerLat, centerLon, vertices, normals, indices, colorRGB]
NumRoads: uint32
[Per ogni strada: stessa struttura + roadType string]
```

## Requisiti

### Preprocessor
- Python 3.10+
- `pip install -r preprocessor/requirements.txt`

### iOS
- Ubuntu + clang-19 + ld64.lld-19
- iPhoneOS16.5.sdk
- Script: `cd ios && ./build_ipa.sh <version>`

## Build

```bash
# Processa un tile
cd preprocessor && python main.py --tile 44.49,11.34

# Processa area Bologna
cd preprocessor && python main.py --area bologna

# Genera texture 4K
cd preprocessor && python main.py --textures

# Build IPA iOS
cd ios && ./build_ipa.sh 1.0
```

## Licenza

MIT — Copyright 2026 Lorenzo
