# aNavigator 🗺️

**Navigatore per autisti** — autobus, auto e camion. Italia.

Mappa 2.5D con MapLibre GL JS + OpenFreeMap vector tiles.
Routing OSRM, fermate autobus Overpass, turn-by-turn vocale.
Zero API key. 100% gratuito.

## Funzionalità

| | |
|---|---|
| 🗺️ **Mappa 2.5D** | Pitch 50°, rotazione, strade colorate |
| 🔍 **Ricerca** | Indirizzi e luoghi (Nominatim) |
| 🚗 **Routing** | Turn-by-turn (OSRM) |
| 🗣️ **Navigazione vocale** | AVSpeechSynthesizer, lingua italiana |
| 🚌 **Fermate autobus** | Da Overpass API in tempo reale |
| 🧭 **Bussola** | Orientamento magnetico |
| 📍 **Tracking** | Posizione GPS con heading |
| ⚙️ **Impostazioni** | Camera, voce, tema, testo, bussola |
| 🪟 **Finestra autobus** | Info fermate e modalità autista |
| 📋 **Log** | Debugging in tempo reale |

## Tecnologie

| Componente | Cosa usa |
|---|---|
| **Mappa** | [MapLibre GL JS](https://maplibre.org) + [OpenFreeMap](https://openfreemap.org) |
| **Tile** | Vector tiles `.pbf` — gratis, niente API key |
| **Ricerca** | [Nominatim](https://nominatim.org) — OpenStreetMap |
| **Routing** | [OSRM](https://project-osrm.org) |
| **Fermate bus** | [Overpass API](https://overpass-api.de) |
| **Voce** | AVSpeechSynthesizer |
| **Build** | clang-19 + ld64.lld-19 + iPhoneOS16.5.sdk (WSL) |

## Architettura

```
aNavigator/
├── ios/
│   ├── anavigatore/                 # Sorgenti iOS
│   │   ├── AppDelegate.h / .m
│   │   ├── MapViewController.h / .mm   # Controller mappa (1550 righe)
│   │   ├── SettingsViewController.h / .mm
│   │   ├── BusViewController.h / .mm
│   │   ├── SettingsStore.h / .mm
│   │   ├── LocalizationManager.h / .mm
│   │   ├── main.m
│   │   ├── Info.plist
│   │   ├── map.html                  # MapLibre GL JS — 450 righe
│   │   └── assets/                   # Bus 3D, freccia, bussola
│   ├── build/                        # IPA output
│   └── build_ipa.sh                  # Script compilazione
├── backup/                           # Backup di ogni versione
│   └── v1.0/                         # 28 file per ricompilare
├── README.md
└── LICENSE
```

## Build

```bash
cd ios
./build_ipa.sh 1.0
```

Output: `ios/build/aNavigator_v1.0.ipa`

## Requisiti Build

- Ubuntu / WSL
- clang-19, ld64.lld-19
- iPhoneOS16.5.sdk in `/home/alina/sdk/`
- Python 3.x (per creare IPA)

## Download

Scarica l'ultima IPA da [GitHub Releases](https://github.com/Lorenzo8484/aNavigator/releases).

---

*Italy-first navigation. Built for bus drivers, car drivers, and truck drivers.*
