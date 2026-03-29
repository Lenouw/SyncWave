# Contexte du projet

## Projet
**SyncWave** — App macOS native de synchronisation multi-camera multi-clips. Remplace PluralEyes pour les tournages avec coupures/reprises (plusieurs fichiers par camera + enregistreur externe). L'app detecte quels clips se chevauchent, les synchronise par session, et exporte vers Premiere Pro.

## Stack technique
- **Swift 5.9+ / SwiftUI** : UI, app shell, export XML
- **Python 3 / scipy** : moteur de correlation audio (subprocess via sync_multi.py)
- **FFmpeg CLI** : extraction audio en raw PCM (subprocess)
- **Export** : FCP 7 XML v4 (Premiere Pro compatible)
- **Distribution** : .app bundle, GitHub Releases, auto-updater integre

## Derniere mise a jour
2026-03-29 16:30

## Ce qu'on a fait

- [2026-03-29] Session complete de developpement :
  - Construction de l'app de zero (Swift + Python)
  - Moteur de sync : envelope cross-correlation via Python/scipy (valide : 81% confiance, -159s offset sur 37min)
  - Export XML FCP 7 v4 : reecrit pour mapper les pistes SyncWave → Premiere (V1→V1+A1, V2→V2+A2, A1→A3...)
  - Mode multi-clips : pistes V1/V2/A1/A2, drag & drop, sync par session
  - Sync par session : 1er clip de chaque piste = session 1, 2eme = session 2, gap de 2min entre sessions
  - Timeline visuelle NLE : clips positionnes par offset, feedback grise→colore, regle temporelle
  - UI : auto-updater, icone, preferences, progress detaille
  - GitHub : repo Lenouw/SyncWave, releases v1.0.0 et v1.0.1
  - ~50 commits, 15 tests unitaires

## Ou on en est

### Ce qui FONCTIONNE
- **Structure des pistes dans l'export XML** : les clips d'une meme piste SyncWave sont sur la meme piste Premiere. V1→V1+A1, V2→V2+A2, audio standalone→A3, A4...
- **Groupement par session** : 1er clip = session 1, 2eme = session 2, chainés avec gap
- **Pas de crash** : export XML stable, extraction audio non-bloquante
- **App standalone** : /Applications/SyncWave.app
- **Auto-updater** : verifie GitHub Releases

### Ce qui NE FONCTIONNE PAS — PROBLEME CRITIQUE
- **La synchronisation produit des offsets incorrects dans le mode multi-clips**. Les clips d'une meme session ne sont PAS alignes verticalement dans Premiere. Ils sont decales de plusieurs minutes les uns par rapport aux autres. L'utilisateur a montre ce que le resultat DEVRAIT etre (screenshot de reference : tous les clips d'une session commencent au meme moment).
- **L'UI ne montre pas les pistes audio associees aux videos** — une piste video V1 devrait montrer son audio A1 en dessous, comme dans Premiere

### Resultat attendu (screenshot de reference)
```
V2  │ ████ Cam2-2752 ████            │ gap │ ████ Cam2-2753 ████████████████ │
V1  │ ████ Cam3-1728 ████            │ gap │ ████ Cam3-1729 ████████████████ │
────┼─────────────────────────────────┼─────┼─────────────────────────────────┤
A1  │ ████ cam3 audio L ████         │ gap │ ████ cam3 audio L ████████████ │
A2  │ ████ cam3 audio R ████         │ gap │ ████ cam3 audio R ████████████ │
A3  │ ████ cam2 audio L ████         │ gap │ ████ cam2 audio L ████████████ │
A4  │ ████ cam2 audio R ████         │ gap │ ████ cam2 audio R ████████████ │
A5  │ ████ Track1-Mic L ████████████ │ gap │ ████ Track1-Mic L ████████████ │
A6  │ ████ Track1-Mic R ████████████ │ gap │ ████ Track1-Mic R ████████████ │
A7  │ ████ Stereo Mix L █████████    │ gap │ ████ Stereo Mix L ████████████ │
A8  │ ████ Stereo Mix R █████████    │ gap │ ████ Stereo Mix R ████████████ │
```
**TOUS les clips d'une meme session doivent commencer au meme moment** (a quelques secondes pres).

## Architecture et decisions

### Pipeline actuel
```
Pistes SyncWave (V1, V2, A1, A2) avec clips groupes par piste
       ↓
FFmpeg → raw PCM Float32 48kHz mono (par clip)
       ↓
Python sync_multi.py :
  - Groupe les clips par session (1er de chaque piste = session 1)
  - Dans chaque session : anchor = clip le plus long
  - Correle chaque clip contre l'anchor (envelope cross-correlation)
  - Chaine les sessions avec gap de 2min
       ↓
JSON positions → Swift SyncEngine → ExportEngine → FCP 7 XML
```

### Le bug de sync (cause probable)
L'envelope cross-correlation renvoie des offsets incorrects pour certaines paires de fichiers (camera vs enregistreur externe). Le meme algorithme fonctionne en mode simple (prouve avec 81% confiance) mais echoue en multi-clips. Hypotheses :
1. Les fichiers audio du recorder (WAV) ne sont pas tous lisibles par FFmpeg (dossiers 5176/5177 corrompus, seul 5178 fonctionne)
2. Le signe de l'offset est peut-etre inverse pour certaines paires
3. L'anchor (clip le plus long) n'est pas toujours le bon choix
4. La correlation entre des sources tres differentes (camera vs micro externe) est naturellement faible

### Convention de signe
`timeline_offset = -python_correlation_lag` (documente dans tasks/lessons.md)

### Export XML — Mapping des pistes
- SyncWave V1 → Premiere V1 (video) + A1 (audio stereo L+R)
- SyncWave V2 → Premiere V2 (video) + A2 (audio stereo L+R)
- SyncWave A1 → Premiere A3 (audio standalone stereo)
- SyncWave A2 → Premiere A4 (audio standalone stereo)
- Les clips d'une meme piste SyncWave sont des `<clipitem>` dans le meme `<track>` XML

## Ce qu'il reste a faire
- [ ] **PRIORITE 1 : Fixer la synchronisation multi-clips** — les offsets sont incorrects. Debug approche : executer sync_multi.py manuellement avec logs stderr, comparer les offsets produits avec ceux attendus (reference : screenshot Premiere montre tous les clips d'une session alignes).
- [ ] **PRIORITE 2 : UI pistes audio associees aux videos** — V1 devrait montrer A1 en dessous dans la timeline SyncWave
- [ ] **PRIORITE 3 : Precision sub-ms** — affinage cross-correlation fine apres l'envelope coarse
- [ ] Support des WAV proprietaires (certains fichiers de l'enregistreur ne sont pas lisibles par FFmpeg)
- [ ] Waveform visuelle sur les clips
- [ ] Distribution .dmg

## Problemes connus
- **Sync multi-clips incorrect** : les offsets produits par sync_multi.py sont faux. Les clips d'une meme session ne sont pas alignes dans Premiere.
- **Certains WAV illisibles** : les fichiers des dossiers 5176 et 5177 de l'enregistreur ne sont pas lisibles par FFmpeg ("Invalid data found when processing input"). Seul le dossier 5178 fonctionne.
- **Python/scipy requis** : l'app necessite Python 3 + scipy + numpy

## Notes pour la prochaine session
- Repo : https://github.com/Lenouw/SyncWave
- App : /Applications/SyncWave.app
- **Le moteur de sync** est `Scripts/sync_multi.py` — c'est LA qu'il faut debugger
- **L'export XML** est `Sources/SyncWave/Engine/ExportEngine.swift` — le mapping est CORRECT
- **Le SyncEngine Swift** est `Sources/SyncWave/Engine/SyncEngine.swift` — appelle Python
- **Fichiers de test** : Dropbox `2026-Rushs Tournage Podcast/03 - Mars 2026/2026-03-17 Akalai Yanis/`
  - CAM 2 : 20260317_Cam2-2752.MP4, 20260317_Cam2-2753.MP4
  - CAM 3 : 20260317_Cam3-1728.MP4, 20260317_Cam3-1729.MP4
  - AUDIO : dossier 5178 (Track1-Mic 1.wav, Stereo Mix.wav) — seul dossier lisible par FFmpeg
- **Screenshot de reference** : l'utilisateur a montre le resultat correct de Premiere (tous clips alignes par session)
- Pour builder : `swift build -c release && bash Scripts/build-release.sh`
- **Approche de debug** : executer `python3 Scripts/sync_multi.py /tmp/manifest.json 2>/dev/null` et lire stderr pour voir exactement quels offsets sont produits pour chaque paire
