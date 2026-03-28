# Contexte du projet

## Projet
**SyncWave** — Clone de PluralEyes (abandonne par Maxon en 2023). App macOS native pour synchroniser automatiquement des rushes multi-camera (2-4 cameras + micro externe type Zoom H6) par analyse de waveform audio, et exporter vers Adobe Premiere Pro via FCP 7 XML.

## Stack technique
- **Langage** : Swift 5.9+
- **UI** : SwiftUI (macOS 14+ Sonoma)
- **DSP/Audio** : Accelerate/vDSP (FFT, cross-correlation hardware-acceleree sur Apple Silicon)
- **Media** : AVFoundation (extraction audio) + FFmpeg CLI en fallback (MXF, BRAW, R3D)
- **Export** : FCP 7 XML v4 (compatible Premiere Pro, DaVinci Resolve, EDIUS)
- **Tests** : XCTest (15 tests)
- **Build** : Swift Package Manager + Xcode

## Derniere mise a jour
2026-03-28 23:00

## Ce qu'on a fait
- [2026-03-28] Session complete d'implementation :
  - Recherche approfondie sur PluralEyes (5 agents en parallele : features, UX, alternatives, libs DSP, format XML Premiere)
  - Design spec + plan d'implementation (13 taches)
  - Execution via subagent-driven development (13 taches completees)
  - 17 commits, 15 tests passent, build OK
  - Fix du format XML export : reecrit pour correspondre exactement au format Premiere Pro (version 4, tracks separes, stereo, file references, outputs)
  - Fix des offsets negatifs dans le XML (normalisation pour que le clip le plus ancien = frame 0)
  - Fix activation fenetre macOS (NSApplication.setActivationPolicy + activate)
  - Fix warning Xcode (withUnsafeMutableBytes result unused)
  - Tests avec vrais fichiers : l'export XML est maintenant accepte par Premiere Pro, mais la synchronisation audio est incorrecte

## Ou on en est

### Ce qui FONCTIONNE
- **Structure complete de l'app** : 3 couches (UI → Engine → DSP)
- **UI macOS native** : MainWindow, drag & drop, timeline multi-piste, preview video, panel de statut sync, export sheet
- **Export XML Premiere Pro** : format FCP 7 XML v4 correct, importe dans Premiere sans erreur, tous les clips apparaissent sur la timeline avec video + audio stereo
- **15 tests unitaires** passent (modeles, GCC-PHAT avec signaux synthetiques, drift correction, extraction audio, SyncEngine, ExportEngine)
- **L'app se lance dans Xcode** (Cmd+R)

### Ce qui NE FONCTIONNE PAS
- **Le moteur de sync ne produit pas les bons offsets avec de vrais fichiers audio**. La confiance est basse (25%) et les clips ne sont pas alignes correctement dans Premiere. L'algorithme GCC-PHAT fonctionne avec des signaux synthetiques (tests passent) mais echoue avec du vrai audio enregistre par des cameras.

## Architecture et decisions

### Structure du projet
```
Sources/SyncWave/
├── App/      SyncWaveApp.swift, AppState.swift
├── Models/   MediaClip, SyncResult, Project, ExportSettings
├── DSP/      AudioBuffer, AudioExtractor, GCCPHATCorrelator, DriftCorrector
├── Engine/   SyncEngine, ExportEngine
└── Views/    MainWindow, ImportDropZone, TimelineView, TimelineTrackView,
              SyncStatusPanel, PreviewView, ExportSheet
```

### Algorithme de sync (GCC-PHAT) — BESOIN DE DEBUG
1. Extraction audio : AVFoundation → Float32 PCM 48kHz mono (fonctionne)
2. Cross-correlation GCC-PHAT via vDSP : FFT → cross-power spectrum → PHAT whitening → IFFT → pic (fonctionne avec signaux synthetiques, PAS avec vrai audio)
3. Correction de drift : correlation normalisee sur fenetres glissantes + regression lineaire (fonctionne avec signaux synthetiques)

### Pourquoi vDSP
- Precision identique a libfftw3 sur Apple Silicon
- Hardware-accelere (AMX/Neon)
- Zero dependance externe
- Chromaprint rejete : concu pour identification musicale, resolution 512ms, inutile pour sync sub-ms

### Export XML — Decisions cles
- Format FCP 7 XML v4 (pas v5) car c'est ce que Premiere exporte nativement
- Chaque clip video sur son propre `<track>` (pas tous sur un seul track)
- Audio stereo : 2 tracks audio par clip (channel 1 + channel 2) avec `outputchannelindex`
- File element defini une seule fois, puis reference avec `<file id="X"/>`
- `pathurl` avec prefixe `file://localhost/` et URL encoding (%20 pour espaces)
- Offsets normalises : le clip le plus ancien demarre a frame 0 (Premiere refuse start < 0)

### Seuils de confiance
- >= 0.7 : vert (sync OK)
- 0.3-0.7 : jaune (douteux)
- < 0.3 : rouge (echec)

## Ce qu'il reste a faire
- [x] Scaffolding projet
- [x] Modeles de donnees
- [x] Moteur GCC-PHAT (signaux synthetiques)
- [x] Correction de drift
- [x] Extracteur audio (AVFoundation + FFmpeg)
- [x] SyncEngine
- [x] ExportEngine FCP 7 XML (compatible Premiere Pro)
- [x] UI complete (import, timeline, preview, export)
- [x] Fix format XML pour Premiere Pro
- [x] Fix offsets negatifs
- [ ] **PRIORITE 1 : Debugger le moteur de sync avec de vrais fichiers audio** — le GCC-PHAT ne trouve pas les bons offsets. Ecrire un outil de debug qui montre pas-a-pas l'extraction, les waveforms, et les resultats de correlation.
- [ ] Calibrer la confiance avec de vrais fichiers (25% trop bas)
- [ ] Tester avec plusieurs configurations de rushes (2 cam, 3 cam, cam + audio externe)
- [ ] Mute/Solo par piste audio dans le preview
- [ ] Waveform visuelle dans la timeline
- [ ] Distribution (.dmg ou Mac App Store)

## Problemes connus
- **Sync incorrect avec vrai audio** : l'offset calcule par GCC-PHAT est faux avec de vrais fichiers. Les signaux synthetiques passent mais pas le vrai audio. C'est le probleme #1 a resoudre.
- **Confiance trop basse (25%)** : la formule de confiance (coefficient de correlation normalise) n'est probablement pas calibree pour du vrai audio.
- **Pas de detection du framerate reel des fichiers** : on hardcode 30fps/ntsc=TRUE dans l'export XML. Il faudrait detecter le framerate source de chaque clip.

## Notes pour la prochaine session
- L'app se lance via Xcode : ouvrir `Package.swift`, scheme SyncWave, My Mac, Cmd+R
- Les fichiers de test de l'utilisateur sont dans `/Users/florianbonin/Downloads/Nouveau dossier contenant des éléments/` (IMG_1071.MOV, IMG_4105.MOV, ASOA Tennis.mp3)
- Le XML exporte est dans `/Users/florianbonin/Downloads/SyncWave Export1.xml` — format correct, Premiere l'importe bien
- Le coeur du probleme est dans `Sources/SyncWave/DSP/GCCPHATCorrelator.swift` (~200 lignes) — l'algo fonctionne en theorie mais pas en pratique
- Pour debugger : ecrire un script/outil qui extrait l'audio des fichiers de test, les compare, et affiche les resultats de correlation etape par etape
- Fichier de reference Premiere : `Exemples/Premiere.xml` — un vrai export XML Premiere pour reference
- Le design spec est dans `docs/superpowers/specs/2026-03-28-syncwave-design.md`
- Le plan d'implementation est dans `docs/superpowers/plans/2026-03-28-syncwave-implementation.md`
