# Contexte du projet

## Projet
**SyncWave** — App macOS native qui synchronise automatiquement des rushes multi-camera (2-4 cameras + micro externe) par analyse de waveform audio, et exporte vers Adobe Premiere Pro via FCP 7 XML. Clone de PluralEyes (abandonne par Maxon en 2023).

## Stack technique
- **Langage** : Swift 5.9+
- **UI** : SwiftUI (macOS 14+ Sonoma)
- **DSP/Audio** : Accelerate/vDSP (FFT, cross-correlation hardware-acceleree sur Apple Silicon)
- **Media** : AVFoundation (extraction audio) + FFmpeg CLI en fallback (MXF, BRAW, R3D)
- **Export** : FCP 7 XML v4 (compatible Premiere Pro, DaVinci Resolve, EDIUS)
- **Preview video** : AVPlayerView via NSViewRepresentable (pas VideoPlayer de SwiftUI — crash SPM)
- **Tests** : XCTest (15 tests)
- **Build** : Swift Package Manager + Xcode

## Derniere mise a jour
2026-03-29 11:30

## Ce qu'on a fait

- [2026-03-29] Ameliorations et corrections :
  - Fix crash .app : remplacement de `VideoPlayer` (SwiftUI AVKit) par `AVPlayerView` natif via `NSViewRepresentable` — le framework `_AVKit_SwiftUI` crashe dans les executables SPM
  - Fix fenetre unique : ajout `NSQuitAlwaysKeepsWindows=false`, `NSWindow.allowsAutomaticWindowTabbing=false`, suppression menu "Nouvelle fenetre", AppDelegate avec `applicationShouldHandleReopen`
  - Fix nom de fichier export : le NSSavePanel respecte maintenant le nom choisi par l'utilisateur (avant c'etait toujours "SyncWave Export.xml")
  - Build release + creation du bundle .app (dans /Applications/SyncWave.app) avec icone, Info.plist, signature ad-hoc
  - Icone app : deux waveforms qui se synchronisent sur fond bleu-teal gradient

- [2026-03-29] Debug et correction du moteur de sync :
  - Investigation avec 3 agents : extraction audio des fichiers test, correlation Python (4 methodes), recherche web sur les algos de sync
  - Decouverte : GCC-PHAT brut echoue avec du vrai audio (amplifie le bruit). La methode qui fonctionne : energy envelope cross-correlation
  - Implementation du preprocessing : DC removal, bandpass 200-4000 Hz (Butterworth biquad), normalisation RMS
  - Implementation sync 2 passes : envelope comme methode principale + fallback GCC-PHAT pour signaux synthetiques
  - Fix bug de signe : l'envelope correlation retournait l'oppose du decalage reel (negation du resultat)
  - Resultat : sync fonctionnel a 97% de confiance avec vrais fichiers de test

- [2026-03-29] Fix export XML Premiere Pro :
  - Reecriture complete de ExportEngine : format FCP 7 XML v4 (calque sur un vrai export Premiere)
  - Chaque clip video sur son propre track, audio stereo (2 tracks par clip), file references, link elements
  - Fix offsets negatifs (normalisation pour que le clip le plus ancien = frame 0)
  - Import teste et valide dans Premiere Pro — tous les clips apparaissent correctement

- [2026-03-28] Implementation complete de l'app (13 taches via subagent-driven development) :
  - Recherche PluralEyes, design spec, plan d'implementation
  - DSP : AudioBuffer, GCCPHATCorrelator, DriftCorrector, AudioExtractor
  - Engine : SyncEngine, ExportEngine
  - UI : MainWindow, ImportDropZone, TimelineView, SyncStatusPanel, PreviewView, ExportSheet

## Ou on en est

### Ce qui FONCTIONNE
- **App macOS native** dans /Applications/SyncWave.app (613 KB, signee ad-hoc)
- **Sync audio** : energy envelope cross-correlation avec preprocessing (DC removal, bandpass, normalisation). Precision ~5ms. Confiance 97% sur fichiers de test.
- **Export XML Premiere Pro** : format FCP 7 v4 correct, importe sans erreur, tous les clips sur la timeline
- **UI complete** : import drag & drop, timeline multi-piste avec code couleur, preview video (AVPlayerView natif), panel de statut sync, export sheet avec NSSavePanel
- **15 tests unitaires** passent

### Ce qui DOIT ETRE AMELIORE
- **Precision du sync** : ~5ms de decalage cree un effet de reverberation quand on ecoute les pistes ensemble. Il faut ajouter une phase d'affinage sub-milliseconde (cross-correlation sur audio brut dans une fenetre etroite autour de l'offset d'envelope)
- **Gestion des framerates** : le XML hardcode 30fps/ntsc=TRUE. Il faudrait detecter le framerate reel de chaque clip
- **Test avec gros fichiers** : pas encore teste avec des enregistrements longs (>1h)

### Bugs mineurs
- Plusieurs fenetres peuvent encore apparaitre dans certains cas malgre les fixes (restauration macOS persistante)

## Architecture et decisions

### Structure du projet
```
Sources/SyncWave/
├── App/      SyncWaveApp.swift (AppDelegate + @main), AppState.swift
├── Models/   MediaClip, SyncResult, Project, ExportSettings
├── DSP/      AudioBuffer, AudioExtractor, GCCPHATCorrelator, DriftCorrector
├── Engine/   SyncEngine, ExportEngine
└── Views/    MainWindow, ImportDropZone, TimelineView, TimelineTrackView,
              SyncStatusPanel, PreviewView (AVPlayerView natif), ExportSheet
```

### Algorithme de sync (2 passes)
1. **Preprocessing** : DC removal → bandpass 200-4000 Hz (Butterworth biquad) → normalisation RMS
2. **Coarse** : energy envelope (20ms window, 5ms hop) → cross-correlation via GCC-PHAT sur les envelopes → offset ±5ms
3. **Fine** (A IMPLEMENTER) : cross-correlation sur audio bandpass-filtre dans une fenetre ±100ms autour de l'offset coarse → precision sub-milliseconde
4. Detection variance d'envelope : si l'envelope est plate (signaux synthetiques), fallback vers GCC-PHAT direct sur signaux bruts

### Pourquoi energy envelope au lieu de GCC-PHAT direct
GCC-PHAT brut amplifie le bruit (whitening donne le meme poids au bruit qu'au signal). L'envelope est robuste aux differences de micros, gain, et bruit ambiant. Teste et confirme avec 4 methodes en Python.

### Export XML — Format Premiere
- FCP 7 XML v4 (pas v5) — c'est ce que Premiere exporte nativement
- Chaque clip video sur son propre `<track>`, audio stereo (2 tracks L/R)
- File element defini une seule fois, puis reference avec `<file id="X"/>`
- `pathurl` avec prefixe `file://localhost/` et URL encoding
- Offsets normalises (min offset = frame 0)

### Preview video — AVPlayerView natif
`VideoPlayer` de SwiftUI (via `_AVKit_SwiftUI`) crashe dans les executables SPM. On utilise `AVPlayerView` wrappee dans `NSViewRepresentable`.

## Ce qu'il reste a faire
- [x] Scaffolding projet
- [x] Modeles de donnees
- [x] Moteur GCC-PHAT (signaux synthetiques)
- [x] Correction de drift
- [x] Extracteur audio (AVFoundation + FFmpeg)
- [x] SyncEngine avec preprocessing
- [x] ExportEngine FCP 7 XML (compatible Premiere Pro)
- [x] UI complete (import, timeline, preview, export)
- [x] Fix format XML pour Premiere Pro
- [x] Fix offsets negatifs
- [x] Fix crash .app (VideoPlayer → AVPlayerView)
- [x] Build .app avec icone
- [ ] **PRIORITE 1 : Affinage sub-milliseconde** — ajouter une phase de cross-correlation fine sur l'audio bandpass-filtre dans une fenetre ±100ms autour de l'offset d'envelope. Objectif : precision ±0.02ms (1 sample a 48kHz)
- [ ] **PRIORITE 2 : Detection framerate reel** — lire le framerate de chaque clip via AVFoundation et l'utiliser dans le XML export au lieu de hardcoder 30fps
- [ ] **PRIORITE 3 : Test avec gros fichiers** — tester avec des enregistrements de 1-2h, verifier performance et precision
- [ ] Drift correction en production (tester avec vrais longs enregistrements)
- [ ] Mute/Solo par piste audio dans le preview
- [ ] Waveform visuelle dans la timeline
- [ ] Distribution (.dmg)

## Problemes connus
- **Precision sync ~5ms** : l'envelope a une resolution de 5ms (200 Hz). Ca cree un leger echo/reverberation quand on ecoute les pistes ensemble. Besoin d'affinage sub-ms.
- **Framerate hardcode** : le XML utilise 30fps/ntsc=TRUE pour tous les clips. Si un clip est a 24fps ou 25fps, les offsets en frames seront imprecis.
- **Fenetres multiples** : malgre Window + AppDelegate + NSQuitAlwaysKeepsWindows, macOS peut encore restaurer des fenetres fantomes dans certains cas.

## Notes pour la prochaine session
- L'app est dans `/Applications/SyncWave.app` — double-clic pour lancer
- Les fichiers de test sont dans `Video et audio pour test/` (IMG_1071.MOV, IMG_4105.MOV, ASOA Tennis.mp3)
- Les offsets corrects (verifies en Python) : IMG_1071=reference, ASOA Tennis=+5.11s, IMG_4105=+6.47s
- Pour builder le .app : `swift build -c release` puis copier `.build/release/SyncWave` dans le bundle + `codesign --force --deep --sign -`
- Le coeur du sync est dans `Sources/SyncWave/Engine/SyncEngine.swift` — c'est la que l'affinage doit etre ajoute
- Le preprocessing est dans `Sources/SyncWave/DSP/AudioBuffer.swift` (bandpass, normalize, envelope)
- Le correlateur est dans `Sources/SyncWave/DSP/GCCPHATCorrelator.swift`
- L'export est dans `Sources/SyncWave/Engine/ExportEngine.swift`
- Le design spec est dans `docs/superpowers/specs/2026-03-28-syncwave-design.md`
- Icone source : `Resources/icon.svg` et `Resources/icon_1024.png`
- Exemple XML Premiere : `Exemples/Premiere.xml`
