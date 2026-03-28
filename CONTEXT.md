# Contexte du projet

## Projet
**SyncWave** — Clone open-source de PluralEyes, l'app de synchronisation automatique audio/video multi-camera abandonnee par Maxon en 2023. App macOS native pour synchroniser des rushes multi-cam d'interviews (2-4 cameras + micro externe) et exporter vers Premiere Pro.

## Stack technique
- **Langage** : Swift 5.9+
- **UI** : SwiftUI (macOS 14+ Sonoma)
- **DSP/Audio** : Accelerate/vDSP (FFT, cross-correlation hardware-acceleree sur Apple Silicon)
- **Media** : AVFoundation (extraction audio) + FFmpeg CLI en fallback (MXF, BRAW, R3D)
- **Export** : FCP 7 XML v5 (compatible Premiere Pro, DaVinci Resolve, EDIUS)
- **Tests** : XCTest (15 tests)
- **Build** : Swift Package Manager

## Derniere mise a jour
2026-03-28 22:30

## Ce qu'on a fait
- [2026-03-28] Implementation complete de SyncWave v1 en une session :
  - Recherche approfondie sur PluralEyes (5 agents en parallele)
  - Design spec + plan d'implementation (13 taches)
  - Execution via subagent-driven development (13 taches, toutes completees)
  - 15 commits propres, 15 tests passent, build OK

## Ou on en est
**L'app v1 est fonctionnelle.** Tous les composants sont implementes :

### Moteur DSP (complet)
- `GCCPHATCorrelator` : cross-correlation via vDSP, precision ±20µs a 48kHz
- `DriftCorrector` : detection de drift par correlation normalisee + regression lineaire
- `AudioExtractor` : AVFoundation + fallback FFmpeg
- `AudioBuffer` : wrapper Float32 PCM avec downsampling et windowing

### Engine (complet)
- `SyncEngine` : orchestre extraction → correlation → drift → resultats
- `ExportEngine` : genere FCP 7 XML valide pour Premiere Pro

### UI (complet)
- `MainWindow` : toolbar (Importer, Synchroniser, Exporter)
- `ImportDropZone` : drag & drop pour fichiers media
- `TimelineView` + `TimelineTrackView` : timeline multi-piste avec code couleur
- `SyncStatusPanel` : statut par clip + confiance globale
- `PreviewView` : lecteur video AVPlayer
- `ExportSheet` : modal d'export avec options

### Modeles (complet)
- `MediaClip`, `SyncResult`, `ClipAlignment`, `Project`, `ExportSettings`

## Architecture et decisions

### Algorithme de sync (2 phases)
1. **GCC-PHAT** sur signal complet : detecte l'offset entre deux clips
2. **Correction de drift** : correlation normalisee sur fenetres glissantes + regression lineaire
- L'implementeur a ameliore l'approche du spec : correlation normalisee directe au lieu de GCC-PHAT fenetre pour le drift (plus precis pour petits drifts)

### Pourquoi vDSP et pas libfftw3/Chromaprint
- **vDSP** : precision identique a libfftw3, hardware-accelere sur Apple Silicon (AMX), zero dependance
- **Chromaprint** : concu pour identification musicale (Shazam-like), resolution 512ms — inutile pour sync sub-ms
- **libfftw3** : aucun avantage sur Apple Silicon, ajouterait une dependance C

### Seuils de confiance
- >= 0.7 : vert (sync OK)
- 0.3-0.7 : jaune (douteux)
- < 0.3 : rouge (echec)

## Ce qu'il reste a faire
- [x] Scaffolding projet Xcode/SPM
- [x] Modeles de donnees
- [x] Moteur GCC-PHAT
- [x] Correction de drift
- [x] Extracteur audio (AVFoundation + FFmpeg)
- [x] SyncEngine
- [x] ExportEngine FCP 7 XML
- [x] UI complete (import, timeline, preview, export)
- [ ] Tester avec des vrais rushes multi-camera
- [ ] Mute/Solo par piste audio dans le preview
- [ ] Waveform visuelle dans la timeline (v1 = blocs colores)
- [ ] Distribution : creer un .dmg ou signer pour le Mac App Store
- [ ] Export FCPXML 1.10 (Final Cut Pro X) — v2
- [ ] Export AAF (Avid) — v2

## Notes pour la prochaine session
- L'app compile et tourne via `swift run` (ou `swift build` + execution du binaire)
- 15 tests passent via `swift test`
- Pour tester avec de vrais fichiers : lancer l'app, drag & drop des clips, clic Synchroniser, puis Exporter XML
- Le XML genere s'importe dans Premiere Pro via File > Import
- Le moteur DSP est le coeur : `Sources/SyncWave/DSP/GCCPHATCorrelator.swift` (~200 lignes)
- Fichiers cles modifies : tout dans `Sources/SyncWave/` (App, Models, DSP, Engine, Views)
