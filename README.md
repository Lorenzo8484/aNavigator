# aNavigator 🗺️

**Navigatore 2.5D per iOS** — Mappa con tilt, routing, e UI completa. MapLibre GL JS + OpenFreeMap vector tiles.

Zero API key. 100% gratuito. Build in WSL con clang-19.

## Screenshot

```
         ╔═══════════════════════╗
         ║     🧭  🌍  ⚙️       ║
         ║     [  Cerca... ]    ║
         ║                      ║
         ║    ┌──────────────┐  ║
         ║    │  🛣️ 2.5D Map │  ║
         ║    │  pitch 50°   │  ║
         ║    └──────────────┘  ║
         ║                      ║
         ║  📍   🚌   🔧      ║
         ╚═══════════════════════╝
```

## Funzionalità

- **Mappa 2.5D** con pitch 50°, rotazione
- **Ricerca** indirizzi (Nominatim)
- **Routing** turn-by-turn (OSRM)
- **Navigazione vocale** (AVSpeechSynthesizer)
- **Impostazioni** camera, voce, tema, testo
- **Fermate autobus** da Overpass API
- **Bussola** + **Tracking** posizione
- **Log** debugging
- **Niente edifici 3D** — stile pulito

## Architettura

```
aNavigator/
├── ios/
│   ├── anavigatore/              # Sorgenti iOS
│   │   ├── AppDelegate.h / .m
│   │   ├── MapViewController.h / .mm   # Controller mappa
│   │   ├── SettingsViewController.h / .mm
│   │   ├── BusViewController.h / .mm
│   │   ├── SettingsStore.h / .mm
│   │   ├── LocalizationManager.h / .mm
│   │   ├── main.m
│   │   ├── Info.plist
│   │   ├── map.html               # MapLibre GL JS
│   │   ├── build_ipa.sh
│   │   └── assets/                # 12 file (bus 3D, arrow, compass)
│   └── build/                     # IPA output
├── backup/
│   └── v1.0/                      # File per ricompilazione
├── README.md
└── LICENSE.md
```

## Tecnologie

| Componente | Cosa usa |
|------------|----------|
| **Mappa** | [MapLibre GL JS](https://maplibre.org) + [OpenFreeMap](https://openfreemap.org) |
| **Tile** | Vector tiles `.pbf` (gratis, no API key) |
| **Ricerca** | [Nominatim](https://nominatim.org) (OpenStreetMap) |
| **Routing** | [OSRM](https://project-osrm.org) |
| **Autobus** | [Overpass API](https://overpass-api.de) |
| **Voce** | AVSpeechSynthesizer |
| **Build** | clang-19 + ld64.lld-19 + iPhoneOS16.5.sdk |

## Requisiti Build

- Ubuntu / WSL
- `clang-19`, `ld64.lld-19`
- `iPhoneOS16.5.sdk` in `/home/alina/sdk/`
- `zip` o Python 3.x

## Build

```bash
cd ios
./build_ipa.sh 1.0
```

Output: `ios/build/aNavigator_v1.0.ipa`

## Licenza

MIT — Copyright 2026 Lorenzo
