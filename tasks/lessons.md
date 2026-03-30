# Lessons Learned

## RÈGLE CRITIQUE — NE PAS TOUCHER AU PIPELINE DE SYNC

**Date : 2026-03-29 | Validé avec 3 caméras + 3 micros RodeCaster × 2 sessions**

Les fichiers suivants constituent le pipeline de synchronisation validé. **NE PAS LES MODIFIER** sauf si un scénario de test échoue :

### Fichiers verrouillés

1. **`Scripts/sync_multi.py`** — Moteur de corrélation Python/scipy
   - Clustering automatique par Union-Find (corrélation audio entre caméras)
   - Sync cameras-first, puis audio vs caméras
   - Greedy graph pour positionner les clips
   - Convention de signe : `timeline_offset = -correlation_lag`

2. **`Scripts/sync_correlate.py`** — Corrélation simple (paire de fichiers)
   - Preprocessing : DC removal, bandpass 200-4000Hz, normalisation RMS
   - Envelope cross-correlation (20ms window, 5ms hop)
   - FFT-based plain cross-correlation sur enveloppes normalisées

3. **`Sources/SyncWave/Engine/SyncEngine.swift`** — Orchestrateur Swift
   - Extraction audio via FFmpeg → raw PCM Float32 48kHz mono
   - Manifest JSON avec structure par tracks
   - Appel Python subprocess + parsing JSON résultat
   - Pipe read AVANT waitUntilExit (anti-deadlock)

4. **`Sources/SyncWave/Engine/ExportEngine.swift`** — Export FCP 7 XML v4
   - Mapping : SyncWave V1 → Premiere V1 + A1/A2, etc.
   - Clips triés par offset (ordre chronologique)
   - clipindex correct pour les liens vidéo/audio multi-sessions
   - Vidéo et audio d'un même MP4 toujours liés (même masterclipid, même start)

### Pourquoi ces fichiers sont verrouillés

Le pipeline a été validé sur :
- 3 caméras (Cam1, Cam2, Cam3) × 2 sessions (stop/restart)
- 3 micros individuels RodeCaster × 2 sessions
- Confiance 78-90%
- Export XML importé correctement dans Premiere Pro
- Vidéo et audio liés dans Premiere
- Clustering automatique correct (pas de tri par nom)

Chaque modification précédente du pipeline a cassé quelque chose. Ne modifier que si un nouveau scénario de test échoue.

### Ce qu'on PEUT modifier sans risque
- L'UI (SwiftUI views) — MainWindow, TrackRowView, MultiTrackTimelineView, etc.
- Les modèles de données (MediaClip, Project, Track) — tant que les champs existants ne changent pas
- Les préférences, l'auto-updater, les logs
- Le build script, les releases GitHub
- Ajouter de NOUVELLES fonctionnalités qui n'interfèrent pas avec le pipeline

---

## 2026-03-29 | Confidence 0% sur fichiers 37min (podcast)

**Ce qui a mal tourné:** `plainCrossCorrelation` calculait la confidence comme `maxVal / sqrt(refEnergy * tgtEnergy)`. Après normalisation des enveloppes (mean=0, RMS=1), l'énergie de chaque enveloppe = N samples (~445383). Le `maxVal` lui-même est scalé par `1/fftSize` (~9.5e-7). Résultat: confidence = 0.33 / 428581 ≈ 0.0000008 → arrondi à 0%.

**Règle:** Pour des enveloppes normalisées (RMS=1), utiliser le peak-to-mean ratio comme confidence. Ne jamais utiliser `maxVal / sqrt(E1*E2)` quand les signaux sont normalisés ET que maxVal inclut un facteur d'échelle `1/fftSize`.

## 2026-03-29 | Convention de signe des offsets

**Ce qui a mal tourné:** Python `S2 * conj(S1)` retourne un lag négatif quand le target démarre APRÈS la reference. Pour le timeline, il faut l'opposé.

**Règle:** `timeline_offset = -python_correlation_lag`

## 2026-03-29 | Micros individuels ne corrèlent pas entre eux

**Ce qui a mal tourné:** La corrélation entre micro A (personne 1) et micro B (personne 2) donne 5-7% de confiance car ils captent des voix différentes.

**Règle:** Toujours corréler via les CAMÉRAS (qui captent le mix ambiant). Ne jamais corréler audio solo ↔ audio solo directement.

## 2026-03-29 | Clips dans le XML doivent être en ordre chronologique

**Ce qui a mal tourné:** Premiere ignore les clips qui ne sont pas dans l'ordre `start` croissant sur une même piste.

**Règle:** Toujours trier les clips par offset avant de les écrire dans le XML.

## 2026-03-29 | clipindex doit correspondre à la position sur la piste

**Ce qui a mal tourné:** Tous les clips avaient clipindex=1. Le 2ème clip d'une piste perdait son lien vidéo/audio.

**Règle:** clipindex = position du clip sur la piste (1, 2, 3...).

## 2026-03-30 | Bumper la version avant de committer les features

**Ce qui a mal tourné:** Commit des features sans bumper la version. L'utilisateur a dû demander explicitement.

**Règle:** Toute release de features → bumper le fichier VERSION + rebuilder + committer en même temps. Ne jamais laisser la version en retard sur le code.
