# Contexte du projet

## Projet
**SyncWave** — App macOS native qui synchronise automatiquement des rushes multi-camera par analyse de waveform audio, et exporte vers Adobe Premiere Pro via FCP 7 XML. Clone de PluralEyes (abandonne par Maxon en 2023).

## Stack technique
- **Langage** : Swift 5.9+ (UI, app shell) + **Python 3/scipy** (moteur de correlation)
- **UI** : SwiftUI (macOS 14+ Sonoma)
- **Correlation audio** : Python scipy (butter, filtfilt, FFT cross-correlation) — appele en subprocess
- **Extraction audio** : FFmpeg CLI (subprocess)
- **Export** : FCP 7 XML v4 (compatible Premiere Pro, DaVinci Resolve)
- **Preview video** : AVPlayerView via NSViewRepresentable
- **Tests** : XCTest (15 tests sur signaux synthetiques)
- **Build** : Swift Package Manager + Xcode
- **Distribution** : .app bundle signe ad-hoc, GitHub Releases avec auto-updater

## Derniere mise a jour
2026-03-29 14:30

## Ce qu'on a fait

- [2026-03-29] Moteur de sync passe a Python/scipy :
  - Le vDSP FFT cross-correlation en Swift echouait sur les fichiers longs (bug de normalisation de confiance : `maxVal / sqrt(E1*E2)` donnait 0.0000008 au lieu de 0.81 car maxVal est deja divise par fftSize)
  - Nouveau pipeline : FFmpeg extrait raw PCM → Python `sync_correlate.py` fait la correlation → Swift recoit le JSON
  - Teste et prouve : -159s offset, 81% confiance sur fichiers de 37min
  - Fix du signe : `timeline_offset = -correlation_lag` (le lag de correlation est inverse de la position timeline)

- [2026-03-29] Mode multi-clips :
  - WelcomeView avec 2 modes : "Sync rapide" (tout en vrac) et "Multi-clips" (pistes V1/V2/A1/A2...)
  - MultiTrackTimelineView avec pistes video en haut, audio en bas
  - TrackRowView avec drag & drop par piste, labels colores, renumerotation auto
  - Sync fonctionne en mode multi-clips (collecte les clips depuis les tracks)

- [2026-03-29] Ameliorations UI :
  - Progress detaille pendant la sync (message par etape + barre de progression)
  - Progress visuel par clip (grise → colore au fur et a mesure du traitement)
  - Systeme de mise a jour integre (dialog + preferences + menu)
  - Icone app, build release, GitHub Releases v1.0.0 et v1.0.1

- [2026-03-28] Implementation complete initiale (13 taches)

## Ou on en est

### Ce qui FONCTIONNE
- **Sync rapide (mode simple)** : fonctionne sur des fichiers de 37 minutes avec le moteur Python/scipy. Confiance 81%. Offsets corrects. Teste et valide dans Premiere Pro.
- **Export XML Premiere Pro** : format FCP 7 v4 correct, importe dans Premiere sans erreur
- **UI** : 2 modes (simple + multi-clips), timeline, preview video, status panel, export sheet
- **Auto-updater** : verifie GitHub Releases, propose installation
- **App standalone** : /Applications/SyncWave.app

### Ce qui NE FONCTIONNE PAS
- **Mode multi-clips** : la sync tourne mais l'export dans Premiere est incomplet :
  - Seuls les clips avec confiance > 30% sont exportes (les autres sont exclus)
  - Les clips d'une meme camera avec des enregistrements separes (stop/restart) ne sont pas bien geres — chaque clip est correle individuellement contre la reference, pas par groupe de piste
  - La timeline multi-piste ne montre pas visuellement les offsets apres sync
- **Precision du sync** : ~5ms de decalage visible dans les waveforms Premiere (l'affinage sub-ms n'est plus actif depuis le passage a Python)
- **Clips avec faible correlation** : Cam2-2752 a 0% confiance (+879s offset absurde) — le fichier n'a probablement pas assez de contenu audio commun avec la reference

## Architecture et decisions

### Pipeline de sync actuel
```
Fichier media → FFmpeg → raw PCM Float32 48kHz mono
                              ↓
                    Python sync_correlate.py
                    (scipy: butter filtfilt + envelope + FFT xcorr)
                              ↓
                    JSON {offset_seconds, confidence}
                              ↓
                    Swift SyncEngine → ExportEngine → FCP 7 XML
```

### Pourquoi Python au lieu de Swift/vDSP
Le vDSP FFT en Swift avait un bug de normalisation de la confiance (division par sqrt(refEnergy*tgtEnergy) alors que maxVal est deja divise par fftSize). L'offset etait en fait trouve correctement par vDSP, mais la confiance etait arrondie a 0% → le resultat etait rejete. Plutot que de continuer a debugger vDSP, on utilise Python/scipy qui est prouve et fiable. Le script est embarque dans le bundle .app.

### Convention de signe des offsets
- Python `S2 * conj(S1)` retourne un lag negatif quand le target demarre APRES la reference
- Pour le timeline, il faut l'oppose : `timeline_offset = -python_lag`
- Documente dans `tasks/lessons.md`

### Structure du projet
```
Sources/SyncWave/
├── App/      SyncWaveApp.swift, AppState.swift, AutoUpdater.swift
├── Models/   MediaClip, SyncResult, Project (avec ProjectMode, Track), ExportSettings
├── DSP/      AudioBuffer, AudioExtractor, GCCPHATCorrelator, DriftCorrector
├── Engine/   SyncEngine (appelle Python), ExportEngine (FCP 7 XML)
└── Views/    MainWindow, WelcomeView, ImportDropZone, TimelineView, TimelineTrackView,
              MultiTrackTimelineView, TrackRowView, SyncStatusPanel, PreviewView,
              ExportSheet, UpdateView, PreferencesView
Scripts/
├── sync_correlate.py    ← moteur de correlation Python/scipy
├── build-release.sh     ← build + bundle .app + zip
└── create-release.sh    ← publie sur GitHub Releases
```

## Ce qu'il reste a faire
- [x] Sync rapide (mode simple) fonctionnel
- [x] Export XML Premiere Pro
- [x] UI complete (2 modes)
- [x] Auto-updater + GitHub Releases
- [ ] **PRIORITE 1 : Precision sub-milliseconde** — ajouter un affinage dans le script Python (apres l'envelope coarse, faire une cross-correlation sur l'audio filtre dans une fenetre ±200ms). Actuellement ~5ms de decalage visible.
- [ ] **PRIORITE 2 : Mode multi-clips complet** — gerer les clips multiples par piste (grouper par piste, syncer chaque clip individuellement, garder l'ordre temporel intra-piste)
- [ ] **PRIORITE 3 : Exclure intelligemment les clips faibles** — au lieu d'exclure les clips < 30% confiance, les garder mais les marquer, laisser l'utilisateur decider
- [ ] Timeline multi-piste : afficher visuellement les offsets apres sync
- [ ] Test avec encore plus de fichiers et configurations
- [ ] Distribution .dmg

## Problemes connus
- **Precision ~5ms** : l'envelope a une resolution de 5ms. L'affinage sub-ms n'est plus actif depuis le passage a Python. Visible dans les waveforms Premiere.
- **Clips sans correlation** : certains clips (ex: Cam2-2752) obtiennent un offset absurde (+879s) parce qu'ils n'ont pas assez de contenu audio commun avec la reference. Pas de detection automatique de ce cas.
- **Fenetres multiples** : macOS peut encore restaurer des fenetres fantomes malgre les fixes (NSQuitAlwaysKeepsWindows, AppDelegate)
- **Python requis** : l'app necessite Python 3 + scipy + numpy installes sur le Mac. Pas de fallback si absent.

## Notes pour la prochaine session
- Le repo est sur GitHub : https://github.com/Lenouw/SyncWave
- L'app est dans /Applications/SyncWave.app
- Le moteur de sync est `Scripts/sync_correlate.py` — c'est LA qu'il faut ajouter l'affinage sub-ms
- Le SyncEngine Swift est `Sources/SyncWave/Engine/SyncEngine.swift` — appelle Python en subprocess
- L'export XML est `Sources/SyncWave/Engine/ExportEngine.swift`
- Les fichiers de test du podcast sont dans le Dropbox : `CosyCosa/Dropbox CosyCosa/2026-Rushs Tournage Podcast/03 - Mars 2026/2026-03-17 Akalai Yanis/`
- Pour builder : `swift build -c release && bash Scripts/build-release.sh`
- Le bug de confiance vDSP est documente dans `tasks/lessons.md`
- La reference Premiere (vrai export) est dans `Exemples/Premiere.xml`
