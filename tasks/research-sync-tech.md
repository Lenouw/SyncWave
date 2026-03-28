# Recherche technique : Remplacement PluralEyes

Date : 2026-03-28

---

## 1. Etat de PluralEyes et alternatives commerciales

PluralEyes (Red Giant / Maxon) est en **maintenance limitee** -- plus de mises a jour actives. Le produit reste fonctionnel mais stagne.

### Alternatives commerciales
- **Syncaila** -- Sync automatique cloud, drift correction, bruit. Abonnement payant. Gere les sequences multi-heures, multi-cameras.
- **Woowave DreamSync** -- Drag & drop, sync + trim + transcodage. Interface simple.
- **Tentacle Sync** -- Surtout hardware (timecode), mais a un logiciel de sync.
- **AudioSyncR (Happy Otter)** -- Trial 30 jours, rapporte comme plus precis que PluralEyes dans certains cas.
- **Descript Overdub** -- Oriente audio/voiceover, pas multi-cam a proprement parler.
- **Adobe Premiere Pro** -- Multi-cam sequence integree avec sync par audio waveform.
- **DaVinci Resolve** -- Sync multi-cam integre.
- **Shotcut** -- Gratuit, open-source, sync multi-cam basique avec visualisation waveform.

---

## 2. Projets open-source de sync audio/video

### Projets directement pertinents

| Projet | Langage | Description | Lien |
|--------|---------|-------------|------|
| **SyncSink** | Java | Sync de fichiers media via audio partage. Determine les offsets en secondes. Concu pour multi-camera. | https://github.com/JorenSix/SyncSink |
| **AudioAlign** | C# (.NET) | Outil de recherche pour sync automatique d'enregistrements audio/video paralleles. Licence AGPL. | https://github.com/protyposis/AudioAlign |
| **auto-sound-sync (ASS)** | C# (.NET) | Fork de auxmic, utilise SoundFingerprinting + ffmpeg. Remplace le clap/clapperboard. | https://github.com/kerryland/auto-sound-sync |
| **sync-audio-tracks** | Rust | CLI pour synchroniser des pistes audio, destine aux editeurs video sans support natif. | https://github.com/alopatindev/sync-audio-tracks |
| **audio-sync-kit** | Python | Librairie Google pour comparer deux signaux audio et obtenir la latence/delai. | https://github.com/google/audio-sync-kit |
| **VideoSync** | Python | Sync automatique de videos de concert crowd-sourced via audio. | https://github.com/allisonnicoledeal/VideoSync |
| **Video-Audio-Sync-for-FFMPEG** | C++ | Lecture de fichiers MTS + MP3, affichage waveforms pour alignement. | https://github.com/jhpark16/Video-Audio-Sync-for-FFMPEG |

### Le plus proche d'un clone PluralEyes : **SyncSink**
- Ecrit en Java par Joren Six (chercheur audio)
- Utilise l'audio partage pour determiner les offsets
- Multi-camera natif
- Algorithme base sur le fingerprinting audio

---

## 3. Librairies de fingerprinting et analyse audio

### Audio Fingerprinting

| Librairie | Langage | Description |
|-----------|---------|-------------|
| **Chromaprint** | C/C++ | Coeur d'AcoustID. Algorithme custom pour extraire des fingerprints. API C simple. Bindings Python via `pyacoustid`. |
| **SoundFingerprinting** | C# (.NET) | Framework complet fingerprinting audio ET video. MIT license. NuGet v13. Detect position exacte dans un track. |
| **Dejavu** | Python | Fingerprinting + reconnaissance audio. Memorise via DB, puis match en temps reel. |
| **audfprint** | Python | Fingerprinting acoustique par landmarks (Dan Ellis, Columbia). Supporte l'alignement d'offset et la detection de clock skew. Depend de librosa. |

### Analyse audio / DSP

| Librairie | Langage | Description |
|-----------|---------|-------------|
| **librosa** | Python | Analyse audio complete : onset detection, beat tracking, spectrogrammes, MFCC, chroma. Standard de facto en Python. |
| **scipy.signal.correlate** | Python | Cross-correlation via FFT. Fonction cle pour detecter l'offset entre deux signaux. |
| **numpy.correlate** | Python | Cross-correlation basique (lent sur gros arrays, preferer scipy avec FFT). |
| **FFmpeg** | C | Extraction audio de tout format video. Peut generer des fingerprints Chromaprint si compile avec `--enable-chromaprint`. |
| **dasp** | Rust | Fondamentaux du DSP : PCM, sampling, conversion. Crate RustAudio. |
| **spectrum-analyzer** | Rust | FFT spectral, fenetre Hann/Hamming. no_std compatible. |
| **sonogram** | Rust | Spectrogramme depuis waveform ou .wav. Export PNG/CSV. |
| **hound** | Rust | Lecture/ecriture WAV pure Rust. |

---

## 4. Approches techniques pour la synchronisation

### Approche 1 : Cross-correlation (la plus simple)

**Principe** : Comparer deux signaux audio en calculant leur correlation croisee. Le pic de correlation indique le decalage temporel.

**Implementation** :
1. Extraire l'audio de chaque fichier video (ffmpeg)
2. Charger les samples en float32 (librosa ou ffmpeg)
3. Calculer la cross-correlation via FFT (scipy.signal.correlate)
4. Trouver le pic = offset en samples
5. Convertir en secondes (offset / sample_rate)

**Avantages** : Simple, precis au sample pres, robuste au bruit non-correle.
**Inconvenients** : O(N log N) par paire, mal adapte si les enregistrements sont tres differents (forte reverb, sources tres eloignees). Ne scale pas bien avec beaucoup de fichiers.

### Approche 2 : Audio Fingerprinting (la plus scalable)

**Principe** : Generer des "empreintes" compactes de l'audio, puis matcher les empreintes entre fichiers pour trouver les offsets.

**Implementation** :
1. Extraire l'audio
2. Generer des fingerprints (Chromaprint, audfprint, ou SoundFingerprinting)
3. Stocker dans un index
4. Query chaque fichier contre l'index
5. Les matches avec offsets temporels coherents donnent le decalage

**Avantages** : Scale bien (N fichiers = N queries contre un index). Robuste aux differences de qualite/microphone. Gere le clock skew.
**Inconvenients** : Resolution temporelle plus faible (~20-50ms selon l'algo). Plus complexe a implementer.

### Approche 3 : Hybride (recommandee pour un clone PluralEyes)

**Principe** : Fingerprinting pour le matching grossier + cross-correlation pour l'alignement precis.

1. **Phase 1 - Groupement** : Fingerprinting pour determiner quels fichiers couvrent la meme scene/moment
2. **Phase 2 - Alignement grossier** : Offsets approximatifs via fingerprint matching (~50ms)
3. **Phase 3 - Alignement fin** : Cross-correlation sur une fenetre reduite autour de l'offset grossier (precision au sample)
4. **Phase 4 - Drift correction** : Detecter et corriger le clock skew entre appareils (resampling)

### Approche 4 : Dynamic Time Warping (DTW)

Utile si les signaux ont des variations de tempo (rare en video mais possible avec des devices a horloge imprecise). Plus couteux en calcul que cross-correlation.

---

## 5. Architecture recommandee pour le projet

### Stack technique suggeree

**Moteur de sync (backend/core)** :
- **Rust** ou **Python** pour le moteur de sync
  - Rust : performance native, crates audio dispo, ideal pour du traitement lourd
  - Python : prototypage rapide, librosa/scipy/audfprint pretes a l'emploi
  - Option hybride : core en Rust, bindings Python via PyO3

**Extraction audio** :
- **FFmpeg** (via CLI ou bindings) -- incontournable, lit tous les formats

**Algorithme de sync** :
- scipy.signal.correlate (cross-correlation FFT) pour le prototype
- Chromaprint ou audfprint pour le fingerprinting si scaling necessaire
- Combiner les deux pour precision + scalabilite

**GUI** :
- **Tauri** (Rust + WebView) -- leger, natif, moderne
- **Electron** (JS/TS) -- plus lourd mais ecosysteme riche
- **Qt** (C++/Python) -- robuste, natif

**Format de sortie** :
- XML/EDL pour import dans Premiere, Resolve, FCPX
- Fichiers video re-muxes avec offset corrige

---

## 6. Estimation de complexite

| Composant | Complexite | Notes |
|-----------|-----------|-------|
| Extraction audio (ffmpeg) | Faible | CLI wrapper suffit |
| Cross-correlation basique | Faible | ~50 lignes scipy |
| Fingerprinting | Moyenne | Integration Chromaprint ou audfprint |
| Multi-fichier matching | Moyenne | Logique de groupement |
| Drift/clock skew correction | Elevee | Resampling + detection |
| GUI avec waveform display | Elevee | Rendu waveform, drag & drop |
| Export NLE (Premiere, Resolve) | Moyenne | Formats XML/EDL documentes |

---

## Sources

- https://github.com/JorenSix/SyncSink
- https://github.com/protyposis/AudioAlign
- https://github.com/kerryland/auto-sound-sync
- https://github.com/alopatindev/sync-audio-tracks
- https://github.com/google/audio-sync-kit
- https://github.com/allisonnicoledeal/VideoSync
- https://github.com/AddictedCS/soundfingerprinting
- https://github.com/worldveil/dejavu
- https://acoustid.org/chromaprint
- https://github.com/dpwe/audfprint
- https://github.com/RustAudio/dasp
- https://librosa.org
- https://alternativeto.net/software/pluraleyes/
- https://discuss.pixls.us/t/is-there-a-foss-alternative-to-pluraleyes/14355
