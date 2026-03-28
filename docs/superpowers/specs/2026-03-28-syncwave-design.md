# SyncWave — Design Spec

## Vue d'ensemble

SyncWave est une application macOS native qui synchronise automatiquement des clips audio/vidéo multi-caméra par analyse de waveform. C'est un clone de PluralEyes (abandonné par Maxon en 2023), destiné aux monteurs vidéo qui filment des interviews multi-caméra avec enregistreur audio externe.

**Cas d'usage principal** : interview multi-cam (2–4 caméras + 1 micro externe type Zoom H6), enregistrements de 30 min à 2h, export vers Adobe Premiere Pro.

## Stack technique

| Composant | Technologie | Justification |
|-----------|-------------|---------------|
| UI | SwiftUI (macOS 14+) | App native macOS, pas d'Electron, UX fluide |
| DSP | Accelerate/vDSP | FFT et cross-correlation hardware-accélérés sur Apple Silicon (AMX). Précision identique à libfftw3, zéro dépendance externe |
| Extraction audio | AVFoundation | Décode nativement MOV, MP4, ProRes, WAV, AIFF, AAC, MP3. Zéro overhead |
| Fallback formats | FFmpeg CLI (subprocess) | Pour MXF, BRAW (Blackmagic), R3D (RED). Binaire dans le bundle, pas de linkage dynamique |
| Export | FCP 7 XML | Format natif importé par Premiere Pro, DaVinci Resolve, et EDIUS |

### Pourquoi pas d'autres libs

- **libfftw3** : aucun gain de précision sur Apple Silicon. vDSP est optimisé pour AMX/Neon. Ajouterait une dépendance C sans bénéfice.
- **Chromaprint** : conçu pour l'identification musicale (type Shazam), résolution temporelle de 512ms. Inutilisable pour du sync sub-milliseconde. Mauvais outil pour le problème.
- **Python/scipy** : performances inférieures, packaging cauchemardesque sur macOS, pas "natif".

## Architecture

```
┌─────────────────────────────────────────────┐
│  UI Layer (SwiftUI)                          │
│  MainWindow · TimelineView · PreviewView     │
│  ImportView · ExportSheet                    │
├─────────────────────────────────────────────┤
│  App Layer (Swift)                           │
│  ProjectManager · MediaImporter              │
│  SyncEngine · ExportEngine                   │
├─────────────────────────────────────────────┤
│  DSP Layer (Swift + vDSP)                    │
│  AudioExtractor · GCCPHATCorrelator          │
│  DriftCorrector                              │
└─────────────────────────────────────────────┘
         ↕ fallback
    FFmpeg CLI (formats exotiques)
```

### Couche UI (SwiftUI)

- **MainWindow** : fenêtre principale avec toolbar, preview, status panel, timeline
- **TimelineView** : multi-piste horizontal, clips positionnés à leur offset, code couleur (vert = sync OK, rouge = échec, jaune = confiance basse)
- **PreviewView** : lecteur vidéo AVPlayer avec contrôles mute/solo par piste
- **ImportView** : zone drag & drop intégrée au centre (quand pas de clips chargés)
- **ExportSheet** : modal de configuration export (NLE cible, options audio)

### Couche App (Swift)

- **ProjectManager** : gère l'état du projet courant (liste de clips, résultats de sync, settings)
- **MediaImporter** : analyse les fichiers déposés, crée des `MediaClip`, détecte les pistes audio
- **SyncEngine** : orchestre le pipeline de sync (extraction → GCC-PHAT → drift → résultats)
- **ExportEngine** : génère le fichier XML à partir des résultats de sync

### Couche DSP (Swift + vDSP)

- **AudioExtractor** : AVAssetReader → Float32 PCM 48kHz mono. Fallback FFmpeg si AVFoundation échoue.
- **GCCPHATCorrelator** : implémentation de GCC-PHAT via vDSP (FFT, cross-power spectrum, PHAT whitening, IFFT, argmax). ~100 lignes de Swift.
- **DriftCorrector** : segmente les longs enregistrements, calcule l'offset par fenêtre, ajuste par régression linéaire.

## Modèles de données

```swift
struct MediaClip: Identifiable {
    let id: UUID
    let url: URL
    let filename: String
    let duration: TimeInterval         // durée en secondes
    let hasAudioTrack: Bool
    let audioSampleRate: Double        // ex: 48000
    let isVideo: Bool                  // true = vidéo, false = audio seul
    var syncStatus: SyncStatus         // .pending, .synced, .failed, .lowConfidence
    var offset: TimeInterval?          // décalage par rapport à la référence (secondes)
    var driftPPM: Double?              // dérive d'horloge en PPM
    var confidence: Double?            // 0.0 à 1.0
}

enum SyncStatus {
    case pending        // pas encore synchronisé
    case synced         // sync OK (confiance >= 0.7)
    case lowConfidence  // sync douteux (0.3 < confiance < 0.7)
    case failed         // sync impossible
}

struct SyncResult {
    let referenceClip: MediaClip
    let alignedClips: [(clip: MediaClip, offset: TimeInterval, driftPPM: Double, confidence: Double)]
    let processingTime: TimeInterval   // temps de traitement
}

struct Project {
    var clips: [MediaClip]
    var syncResult: SyncResult?
    var exportSettings: ExportSettings
}

struct ExportSettings {
    var format: ExportFormat            // .fcpXML pour Premiere
    var replaceAudioInVideo: Bool       // remplacer l'audio caméra par l'audio externe
    var includeUnsyncedClips: Bool      // inclure les clips non synchronisés
    var outputDirectory: URL
}

enum ExportFormat {
    case fcp7XML        // Premiere Pro, Resolve, EDIUS
}
```

## Algorithme de synchronisation

### Phase 1 — Extraction audio

Pour chaque clip importé :
1. Tenter `AVAssetReader` avec output settings : Float32, 48kHz, mono
2. Si échec (format non supporté) → `ffmpeg -i clip -vn -ac 1 -ar 48000 -f f32le output.raw`
3. Stocker le buffer PCM en mémoire (2h @ 48kHz mono Float32 = ~660 MB — acceptable sur Mac)

### Phase 2 — Sélection de la référence

- Automatique : le clip le plus long est la référence
- L'utilisateur peut surcharger manuellement (clic droit → "Définir comme référence")

### Phase 3 — GCC-PHAT par paires

Pour chaque clip (sauf la référence) :

**Étape 3a — Correspondance grossière :**
1. Downsample référence et clip à 4kHz (via `AVAudioConverter` ou décimation vDSP)
2. GCC-PHAT sur le signal entier downsamplé :
   - FFT des deux signaux (zero-pad à la puissance de 2 supérieure)
   - Cross-power spectrum : `X = FFT(A) × conj(FFT(B))`
   - PHAT whitening : `X_norm = X / |X|`
   - IFFT → pic = offset grossier
3. Résolution : ±125ms (1 sample @ 4kHz = 0.25ms)

**Étape 3b — Alignement précis :**
1. Extraire une fenêtre de 10 secondes autour de l'offset grossier, à 48kHz
2. GCC-PHAT sur cette fenêtre
3. Parabolic interpolation autour du pic pour précision sub-sample
4. Résolution : **±20µs** (sub-sample @ 48kHz)

**Étape 3c — Score de confiance :**
- `confiance = pic_max / énergie_moyenne_du_spectre`
- Seuils : ≥ 0.7 = vert (sync OK), 0.3–0.7 = jaune (douteux), < 0.3 = rouge (échec)

### Phase 4 — Correction de drift

Pour les enregistrements > 5 minutes :
1. Découper en fenêtres de 30 secondes avec overlap 50%
2. GCC-PHAT (phase 3a+3b) sur chaque fenêtre → série d'offsets
3. Régression linéaire : `offset(t) = base_offset + drift_rate × t`
4. `drift_rate` converti en PPM : `PPM = drift_rate × 1_000_000`
5. Drift typique entre caméras : 10–100 PPM (< 720ms sur 2h)
6. Si drift > 200 PPM → alerte "horloge potentiellement défaillante"

### Parallélisme

- Chaque paire (clip, référence) est traitée en parallèle via Swift `TaskGroup`
- Les fenêtres de drift sont aussi traitées en parallèle
- Sur M2 : traitement d'un projet 4 clips × 2h ≈ 2–5 secondes

## Interface utilisateur

### Layout principal

La fenêtre est divisée en 4 zones :

```
┌──────────────────────────────────────────────┐
│  Toolbar : [+ Importer] [▶ Synchroniser] ... [Exporter XML ↗] │
├────────────────────────┬─────────────────────┤
│                        │  État de sync        │
│  Aperçu vidéo          │  ● Clip A: référence │
│  (AVPlayer)            │  ● Clip B: +2.3s     │
│  Mute/Solo par piste   │  ● Audio: +0.9s      │
│                        │  ● Clip C: ⚠ échec   │
│                        │  Confiance: 87%       │
├────────────────────────┴─────────────────────┤
│  Timeline multi-piste                         │
│  Camera A   ████████████████████████████████  │
│  Camera B      ██████████████████████████ ⚠█  │
│  Audio ext. █████████████████████████████████  │
├──────────────────────────────────────────────┤
│  ✓ Sync terminée en 2.3s   Précision: ±0.02ms│
└──────────────────────────────────────────────┘
```

### Flux utilisateur

1. **Import** : drag & drop de fichiers (ou bouton "Importer"). Les clips apparaissent dans la timeline, non alignés. Le clip le plus long est auto-sélectionné comme référence.
2. **Sync** : clic sur "Synchroniser". Barre de progression pendant le traitement. Les clips se déplacent visuellement vers leur position alignée. Code couleur appliqué.
3. **Review** : lecture dans le preview, mute/solo par piste pour vérifier l'alignement. Les clips douteux (jaune/rouge) sont identifiés dans le panel de statut.
4. **Export** : clic sur "Exporter XML". Modal avec options (remplacer audio, inclure les clips non synchronisés). Génère un fichier `.xml` importable dans Premiere Pro.

### Écran d'état initial (pas de clips)

Zone de drop centrale avec icône et texte "Glissez vos fichiers vidéo et audio ici". Bouton "Importer des fichiers" en dessous.

### Code couleur sync

- **Vert** (confiance ≥ 0.7) : sync fiable
- **Jaune** (confiance 0.3–0.7) : sync douteux, vérification recommandée
- **Rouge** (confiance < 0.3 ou échec) : sync échoué

## Export Premiere Pro

### Format : FCP 7 XML

Le fichier XML contient :
- Une séquence avec le framerate du clip de référence
- Chaque clip positionné à son offset calculé sur sa propre piste vidéo/audio
- Les timecodes source préservés
- Si "Remplacer l'audio" activé : les pistes audio des clips vidéo sont remplacées par les pistes de l'enregistreur externe

### Structure XML simplifiée

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xmeml>
<xmeml version="5">
  <sequence>
    <name>SyncWave Export</name>
    <rate><timebase>25</timebase></rate>
    <media>
      <video>
        <track>
          <clipitem>
            <name>Camera_A_001</name>
            <start>[offset en frames]</start>
            <file id="file-1"><pathurl>file:///path/to/Camera_A_001.MOV</pathurl></file>
          </clipitem>
        </track>
        <!-- ... autres pistes -->
      </video>
      <audio>
        <!-- pistes audio alignées -->
      </audio>
    </media>
  </sequence>
</xmeml>
```

### Workflow Premiere Pro

1. L'utilisateur ouvre Premiere Pro
2. File → Import → sélectionne le `.xml` généré par SyncWave
3. Premiere crée une séquence avec tous les clips alignés
4. Le monteur peut immédiatement commencer le multicam edit

## Gestion des erreurs

| Situation | Comportement |
|-----------|-------------|
| Clip sans piste audio | Marqué rouge dans le status panel, exclu du sync, notification à l'utilisateur |
| Audio trop bruité | Confiance basse, marqué jaune, l'utilisateur décide de garder ou exclure |
| Format non supporté par AVFoundation | Fallback FFmpeg automatique et transparent |
| FFmpeg absent du système | Message clair : "Format non supporté. Installer FFmpeg via `brew install ffmpeg` pour ouvrir ce type de fichier." |
| Drift excessif (> 200 PPM) | Alerte : "Horloge défaillante détectée — la synchronisation peut être imprécise sur les dernières minutes." |
| Mémoire insuffisante | Traitement par chunks au lieu de charger tout en mémoire. Fallback automatique. |
| Fichier corrompu | AVAssetReader/FFmpeg renvoient une erreur → clip marqué rouge avec message descriptif |

## Formats supportés

### Entrée

**Vidéo (via AVFoundation)** : MOV, MP4, M4V (H.264, H.265, ProRes)
**Vidéo (via FFmpeg fallback)** : MXF, BRAW, R3D, AVI, AVCHD (.MTS)
**Audio** : WAV, AIFF, MP3, AAC, M4A, ALAC

### Sortie

**Export** : FCP 7 XML v5 (compatible Premiere Pro, DaVinci Resolve, EDIUS)

## Hors scope (v1)

- Export FCPXML 1.10 (Final Cut Pro X) — v2
- Export AAF (Avid Media Composer) — v2
- Plugin intégré dans Premiere Pro — v2
- Export de fichiers média re-synchronisés — v2
- Support de plus de 8 clips simultanés — à évaluer selon les retours
- Waveform visuelle dans la timeline (v1 = blocs colorés, v2 = waveform)
