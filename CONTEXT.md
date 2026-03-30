# Contexte du projet — SyncWave

## Projet
**SyncWave** — App macOS native de synchronisation multi-camera multi-clips pour les tournages podcast. Remplace PluralEyes pour le cas des tournages avec coupures/reprises et micros individuels par invité.

Repo GitHub : https://github.com/Lenouw/SyncWave

## Stack technique
- **Swift 5.9+ / SwiftUI** : UI, app shell, export XML
- **Python 3 / scipy** : moteur de corrélation audio (subprocess via sync_multi.py)
- **AVFoundation / vDSP** : lecture audio, extraction de waveforms
- **Sparkle 2.9** : auto-updater avec signature EdDSA
- **FFmpeg CLI** : extraction audio en raw PCM
- **Export** : FCP 7 XML v4 (Premiere Pro compatible)

## Version actuelle
**v1.5.0** — stable, installée dans `/Applications/SyncWave.app`

## Dernière mise à jour
2026-03-30

## Ce qu'on a fait

- [2026-03-30] Session features :
  - WaveformGenerator.swift (AVAssetReader + vDSP) — waveforms sur clips audio
  - AudioSubTrackView.swift + WaveformView.swift — sous-pistes ch1/ch2 sous les vidéos
  - Piste V3 ajoutée par défaut
  - Résolution vidéo dynamique dans le XML export (4K si fichiers 4K)
  - Notification de fin de sync (NSSound + UNUserNotification)
  - Export XML nettoyé : 1 piste audio par source = 6 pistes propres dans Premiere
  - Bump version 1.5.0

- [2026-03-29] Session marathon :
  - App construite de zéro : Swift + Python, ~60 commits
  - Moteur de sync : envelope cross-correlation via Python/scipy
  - Clustering automatique par corrélation (Union-Find) — plus de tri par nom
  - Export XML FCP 7 v4 avec mapping pistes (V1→V1+A1, V2→V2+A2, audio→A3+)
  - Mode multi-clips avec groupement par session
  - Sparkle intégré pour les mises à jour automatiques
  - Pipeline validé : 3 caméras × 3 micros × 2 sessions, 78-90% confiance
  - GitHub releases v1.0.0 à v1.5.0

## Où on en est

### Ce qui FONCTIONNE (validé)
- **Sync multi-caméras** : 78-90% confiance, offsets corrects (3 cam × 2 sessions)
- **Sync micros individuels** : via caméras comme pont (clustering automatique)
- **Export XML** : 6 pistes propres dans Premiere (V1/V2/V3 + A1/A2/A3), résolution dynamique
- **Waveforms** : visibles sur les clips audio (AVAssetReader + vDSP)
- **Sous-pistes audio** : ch1/ch2 sous chaque piste vidéo dans la timeline
- **Sparkle** : auto-updater intégré avec EdDSA
- **UI** : timeline NLE, drag & drop par piste, progress visuel, 6 pistes (V1-V3, A1-A3)
- **Notification de fin de sync** : NSSound + UNUserNotification
- **Logs** : ~/Library/Logs/SyncWave/SyncWave.log

### Problème connu non résolu
- **Pistes audio mono dans Premiere** : les pistes caméra arrivent en mono (canal G seulement) au lieu de stéréo G+D. Plusieurs tentatives sur TL.SQTrackAudioChannelType sans succès. Abandonné pour garder 6 pistes propres.

## Architecture et décisions

### Pipeline (VERROUILLÉ — ne pas modifier)
```
Pistes SyncWave (V1, V2, V3, A1, A2, A3)
       ↓
FFmpeg → raw PCM Float32 48kHz mono
       ↓
Python sync_multi.py :
  1. Clustering automatique par corrélation (Union-Find)
  2. Cameras-first, puis audio vs caméras
  3. Greedy graph pour positionner les clips
       ↓
JSON positions → Swift → ExportEngine → FCP 7 XML
```

**Fichiers verrouillés** (voir tasks/lessons.md pour détails) :
- `Scripts/sync_multi.py`
- `Scripts/sync_correlate.py`
- `Sources/SyncWave/Engine/SyncEngine.swift`
- `Sources/SyncWave/Engine/ExportEngine.swift`

### Convention de signe
`timeline_offset = -python_correlation_lag`

### Export XML
- SyncWave V1 → Premiere V1 + A1
- SyncWave V2 → Premiere V2 + A2
- SyncWave A1 → Premiere A(N+1)
- 1 piste audio XML par source = 6 pistes au total

### Sparkle
- Clé publique EdDSA : `1AvZry8Dl0dM3/B2UjkbZeziG7erROR+03HNyrP8T+E=`
- Appcast : `https://raw.githubusercontent.com/Lenouw/SyncWave/main/appcast.xml`

## Build
```bash
swift build                    # debug
bash Scripts/build-release.sh # release + install /Applications
```
Le fichier `VERSION` contient la version courante (1.5.0).

## Fichiers tests podcast
Dossiers 5160 + 5161 dans le Dropbox du 17 fev 2026 (3 caméras MP4 + 3 micros WAV × 2 sessions)

## Problèmes connus
- **Certains WAV illisibles** : fichiers de certains dossiers du recorder non lisibles par FFmpeg
- **Python/scipy requis** : l'app nécessite Python 3 + scipy + numpy
