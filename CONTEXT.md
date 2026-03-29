# Contexte du projet

## Projet
**SyncWave** — App macOS native de synchronisation multi-camera multi-clips. Remplace PluralEyes (abandonne en 2023) pour le cas specifique des tournages avec coupures/reprises (plusieurs fichiers par camera + enregistreur externe continu). L'app detecte quels clips se chevauchent dans le temps, les synchronise, et exporte vers Premiere Pro.

## Stack technique
- **Swift 5.9+ / SwiftUI** : UI, app shell, export XML
- **Python 3 / scipy** : moteur de correlation audio (subprocess)
- **FFmpeg CLI** : extraction audio en raw PCM (subprocess)
- **Export** : FCP 7 XML v4 (Premiere Pro compatible)
- **Distribution** : .app bundle, GitHub Releases, auto-updater integre

## Derniere mise a jour
2026-03-29 15:00

## Ce qu'on a fait

- [2026-03-29] Pivot vers multi-clips uniquement :
  - Mode simple supprime (Premiere le fait deja nativement)
  - App demarre directement en mode multi-clips avec pistes V1/V2/A1/A2/A3
  - Moteur multi-clips : `sync_multi.py` correle TOUTES les paires entre pistes
  - Graphe de positions : BFS greedy avec seuils de confiance (0.5 puis 0.3)
  - Timeline NLE : clips positionnes visuellement par offset, feedback grise→colore
  - Ordre des pistes NLE : V en haut (reversed), A en bas (convention Premiere)
  - Extraction non-bloquante : clips qui echouent sont ignores

- [2026-03-29] Moteur Python/scipy :
  - Remplacement de vDSP par Python pour la correlation (vDSP avait un bug de normalisation)
  - `sync_correlate.py` pour le sync simple (valide : -159s, 81% confiance sur 37min)
  - `sync_multi.py` pour le sync multi-clips (en cours de debug)

- [2026-03-29] UI et polishing :
  - Systeme de mise a jour (dialog + preferences + menu)
  - Progress par clip (grise→colore)
  - Icone app, GitHub Releases v1.0.0 et v1.0.1

- [2026-03-28] Implementation initiale complete

## Ou on en est

### Ce qui FONCTIONNE
- App macOS standalone dans /Applications/SyncWave.app
- UI multi-clips : pistes V/A, drag & drop, timeline avec positionnement visuel
- Moteur de sync simple (1 clip par camera) : valide avec 81% confiance sur 37min
- Export XML Premiere Pro : format correct, importe sans erreur
- Auto-updater, GitHub Releases

### Ce qui NE FONCTIONNE PAS
- **Moteur multi-clips** : les correlations entre pistes produisent des offsets aberrants pour certains clips (+1314s au lieu de ~160s). Le graphe BFS propage les erreurs.
- **Crash a l'export** : `Dictionary.init(uniqueKeysWithValues:)` crashe dans `ExportEngine.generateFCP7XML` quand il y a des clips avec le meme ID dans `syncResult.alignments` (cles dupliquees). Le crash est a `ExportEngine.swift:41`.
- **Fichiers WAV incompatibles** : certains WAV de l'enregistreur (Stereo Mix.wav) ne sont pas lisibles par FFmpeg → extraction echouee.
- **Precision sync** : ~5ms de decalage (envelope resolution), pas d'affinage sub-ms dans le moteur Python.

## Architecture et decisions

### Pipeline
```
Fichiers media (V1, V2, A1, A2...)
       ↓
FFmpeg → raw PCM Float32 48kHz mono (par clip)
       ↓
Python sync_multi.py :
  - Preprocess (DC removal, bandpass 200-4000Hz, normalise)
  - Envelope (20ms window, 5ms hop)
  - Correle toutes les paires entre pistes differentes
  - BFS greedy pour construire les positions timeline
       ↓
JSON → Swift SyncEngine → ExportEngine → FCP 7 XML
```

### Pourquoi multi-clips uniquement
Premiere Pro gere deja le sync simple (1 enregistrement continu par camera). Le créneau de SyncWave est le multi-clips : tournages avec coupures/reprises ou chaque camera a plusieurs fichiers. C'est ce que PluralEyes faisait et qu'aucun outil ne fait aujourd'hui.

### Le crash export (a fixer en priorite)
`ExportEngine.swift:41` : `Dictionary(uniqueKeysWithValues: syncResult.alignments.map { ($0.clipID, $0) })` crashe si deux alignments ont le meme clipID. Cela arrive quand le meme fichier est place sur deux pistes (ex: Track1-Mic 1.wav sur A1 et A2).

## Ce qu'il reste a faire
- [ ] **PRIORITE 1 : Fix crash export** — `Dictionary(uniqueKeysWithValues:)` crashe sur cles dupliquees dans ExportEngine.swift:41. Remplacer par `Dictionary(_:uniquingKeysWith:)`.
- [ ] **PRIORITE 2 : Fiabiliser le moteur multi-clips** — les correlations entre certaines paires donnent des offsets aberrants. Il faut :
  - Ajouter une validation de coherence : si offset > duree max des clips, rejeter
  - Utiliser les metadonnees de fichier (date de creation, timecode) pour regrouper les clips en sessions
  - Tester avec un jeu de donnees plus simple (3 clips du meme moment)
- [ ] **PRIORITE 3 : Precision sub-ms** — ajouter un affinage cross-correlation fine dans sync_multi.py apres l'envelope coarse
- [ ] Support des WAV propriétaires (Stereo Mix) : essayer AVFoundation en fallback
- [ ] Waveform visuelle sur les clips de la timeline
- [ ] Distribution .dmg

## Problemes connus
- **Crash export** : `ExportEngine.swift:41` — `Dictionary(uniqueKeysWithValues:)` crashe sur cles dupliquees quand le meme fichier est sur plusieurs pistes
- **Offsets aberrants** : sync_multi.py peut donner +1314s au lieu de +159s pour certains clips. Le seuil de confiance BFS (0.5) ne suffit pas a filtrer les mauvaises correlations.
- **Stereo Mix.wav** : FFmpeg ne peut pas lire ces fichiers (format proprietaire de l'enregistreur). L'extraction echoue silencieusement.
- **Python/scipy requis** : l'app necessite Python 3 + scipy + numpy installes sur le Mac
- **Fenetres multiples** : peut encore apparaitre dans certains cas

## Notes pour la prochaine session
- Repo : https://github.com/Lenouw/SyncWave
- App : /Applications/SyncWave.app
- **Le crash export** est le bug le plus critique. Ligne 41 de `Sources/SyncWave/Engine/ExportEngine.swift`. Remplacer `Dictionary(uniqueKeysWithValues:)` par `Dictionary(_:uniquingKeysWith: { first, _ in first })`.
- Le moteur multi-clips est `Scripts/sync_multi.py` — le BFS greedy est la partie fragile
- Le moteur simple (qui fonctionne) est `Scripts/sync_correlate.py`
- Les fichiers de test du podcast sont dans le Dropbox : `CosyCosa/Dropbox CosyCosa/2026-Rushs Tournage Podcast/03 - Mars 2026/2026-03-17 Akalai Yanis/`
- Les fichiers du dossier `5178` sont lisibles par FFmpeg, les autres (5176, 5177) ne le sont pas
- Pour builder : `swift build -c release && bash Scripts/build-release.sh`
- Convention de signe : `timeline_offset = -python_correlation_lag`
