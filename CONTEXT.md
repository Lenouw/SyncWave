# Contexte du projet

## Projet
**SyncWave** (nom de travail) — Clone open-source de PluralEyes, l'app de synchronisation automatique audio/video multi-camera qui a ete abandonnee par Maxon en 2023. L'objectif est de reproduire les fonctionnalites cles de PluralEyes dans une app macOS native, simple d'utilisation.

## Stack technique
- **Langage** : Swift
- **UI** : SwiftUI (macOS natif)
- **DSP/Audio** : Accelerate framework (vDSP pour FFT et cross-correlation, hardware-accelere)
- **Media** : AVFoundation (lecture/extraction audio des fichiers video)
- **FFmpeg** : via process shell pour les formats non supportes par AVFoundation
- **Export** : generation de FCP XML, FCPXML, Premiere XML
- **Plateforme** : macOS uniquement
- **Min OS** : macOS 14+ (Sonoma)

## Derniere mise a jour
2026-03-28 21:15

## Ce qu'on a fait
- [2026-03-28] Initialisation du projet
- [2026-03-28] Recherche approfondie sur PluralEyes : fonctionnalites, UX/workflow, alternatives, libs techniques
- [2026-03-28] Choix de la stack : SwiftUI natif + Accelerate framework

## Ou on en est
Projet vient d'etre initialise. Aucun code encore. La phase de recherche est terminee, on a une vision claire de ce qu'il faut construire.

## Architecture et decisions

### Pourquoi SwiftUI natif plutot qu'Electron/Tauri
- L'app est macOS uniquement, pas besoin de cross-platform
- Accelerate framework (vDSP) est hardware-accelere sur Apple Silicon — ideal pour le DSP audio
- AVFoundation gere nativement la plupart des formats video/audio sans dependance externe
- UX native macOS plus fluide et coherente

### Algorithme de synchronisation (2 phases, comme PluralEyes)
1. **Audio fingerprinting** : extraction de spectrogrammes via FFT, comparaison des empreintes pour trouver les correspondances grossieres (precision ~frame)
2. **Cross-correlation (GCC-PHAT)** : affinage sample-accurate de l'alignement
3. **Correction de drift** : segmentation des longs enregistrements, recalcul du sync a plusieurs points pour compenser le decalage d'horloge entre appareils

### Workflow utilisateur (inspire de PluralEyes)
1. Drag & drop des fichiers media (video + audio)
2. "Smart Start" : detection automatique des sources/appareils
3. Clic sur "Synchroniser"
4. Review : timeline avec code couleur (vert=synced, rouge=probleme), preview video, mute/solo par piste
5. Export vers NLE (Premiere Pro XML, FCPXML, DaVinci Resolve XML, fichiers media)

### Formats supportes (cible)
**Video** : MOV, MP4, MXF, R3D, BRAW, AVCHD, AVI, ProRes
**Audio** : WAV, AIFF, MP3, AAC, M4A
**Export** : FCP 7 XML (Premiere/Resolve), FCPXML 1.10+ (FCP X moderne), fichiers media synces

### Ce qui manquait a PluralEyes (opportunites)
- FCPXML 1.2 obsolete — on supportera 1.10+ des le depart
- Pas de support AAF (Avid) dans v4 — a evaluer plus tard
- Pas de correction de drift dans les NLEs natifs — c'est notre avantage cle
- Pas de feedback visuel de confiance du sync dans les NLEs — on le fera

## Ce qu'il reste a faire
- [ ] Scaffolding du projet Xcode (SwiftUI app macOS)
- [ ] Moteur d'extraction audio (AVFoundation + fallback FFmpeg)
- [ ] Algorithme de fingerprinting audio (FFT via vDSP)
- [ ] Algorithme de cross-correlation sample-accurate (GCC-PHAT via vDSP)
- [ ] Detection et correction du drift d'horloge
- [ ] UI : ecran d'import drag & drop
- [ ] UI : timeline multi-piste avec code couleur sync
- [ ] UI : preview video avec mute/solo par piste
- [ ] UI : ecran d'export (choix NLE, options)
- [ ] Generateur FCP 7 XML (Premiere/Resolve)
- [ ] Generateur FCPXML 1.10 (Final Cut Pro X)
- [ ] Export fichiers media synces
- [ ] Tests avec des rushes multi-camera reels

## Recherche technique (reference)

### Libs/outils de reference identifies
- **Accelerate/vDSP** (Apple) : FFT, cross-correlation hardware-acceleree
- **AVFoundation** (Apple) : extraction audio, lecture media
- **FFmpeg** : fallback pour formats exotiques (R3D, BRAW, MXF)
- **Chromaprint** (C/C++) : fingerprinting audio, bindings Swift possibles
- **SyncSink** (Java, Joren Six) : reference open-source de sync multi-camera
- **audfprint** (Python, Dan Ellis) : fingerprinting avec detection de drift

### Alternatives existantes (concurrence)
- Premiere Pro "Merge Clips" : basique, pas de batch, pas de drift correction
- FCP X multicam auto-sync : correct mais limites sur beaucoup de clips
- DaVinci Resolve auto-sync : idem
- Aucun clone open-source complet de PluralEyes n'existe actuellement
