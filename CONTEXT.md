# Contexte du projet

## Projet
**SyncWave** — App macOS native de synchronisation multi-camera multi-clips pour les tournages podcast. Remplace PluralEyes pour le cas des tournages avec coupures/reprises et micros individuels par invité.

## Stack technique
- **Swift 5.9+ / SwiftUI** : UI, app shell, export XML
- **Python 3 / scipy** : moteur de correlation audio (subprocess via sync_multi.py)
- **Sparkle 2.9** : auto-updater avec signature EdDSA
- **FFmpeg CLI** : extraction audio en raw PCM
- **Export** : FCP 7 XML v4 (Premiere Pro compatible)
- **Distribution** : .app bundle, GitHub Releases avec Sparkle appcast

## Derniere mise a jour
2026-03-29 21:30

## Ce qu'on a fait

- [2026-03-29] Session marathon de developpement :
  - App construite de zero : Swift + Python, ~60 commits
  - Moteur de sync : envelope cross-correlation via Python/scipy
  - Export XML FCP 7 v4 avec mapping pistes (V1→V1+A1, V2→V2+A2, audio→A3+)
  - Mode multi-clips avec groupement par session
  - All-pairs correlation pour gerer les micros individuels
  - Sparkle integre pour les mises a jour automatiques
  - Code review complet : 13 corrections (pipe deadlock, NTSC, UUID matching...)
  - Systeme de logs pour diagnostic
  - GitHub releases v1.0.0 a v1.2.0

## Ou on en est

### Ce qui FONCTIONNE
- **Sync simple** (1 fichier par camera + 1 enregistreur commun) : 81-89% confiance, offsets corrects
- **Export XML** : format correct, pistes bien mappees dans Premiere
- **Sparkle** : auto-updater integre avec EdDSA
- **UI** : timeline NLE, drag & drop par piste, progress visuel
- **Logs** : ~/Library/Logs/SyncWave/SyncWave.log
- **App standalone** : /Applications/SyncWave.app

### Ce qui NE FONCTIONNE PAS — PROBLEME CRITIQUE
- **Sync avec micros individuels** : quand chaque micro capte une personne differente (podcast multi-invites), la correlation envelope entre micros est aleatoire (5-7% confiance). L'algo produit des offsets faux.
- Le cas qui fonctionne : toutes les sources captent le MEME son (cameras + enregistreur commun)
- Le cas qui echoue : chaque micro capte une personne DIFFERENTE (micro JS vs micro Laura vs micro Gaelle)

### Cause racine du probleme
L'envelope cross-correlation compare les MOTIFS D'AMPLITUDE dans le temps. Quand micro A capte "personne qui parle" et micro B capte "silence" au meme instant (parce que la personne B ne parle pas), les envelopes ne correspondent pas → confiance quasi nulle → offset aleatoire.

## Architecture et decisions

### Pipeline
```
Pistes SyncWave (V1, V2, V3, A1, A2, A3)
       ↓
FFmpeg → raw PCM Float32 48kHz mono
       ↓
Python sync_multi.py :
  1. Groupe par session (1er clip de chaque piste = session 1)
  2. ALL-PAIRS correlation entre pistes differentes
  3. Greedy graph : positionne via les meilleures correspondances
       ↓
JSON positions → Swift → ExportEngine → FCP 7 XML
```

### Pourquoi l'algo echoue sur les micros individuels
L'envelope d'un micro solo (1 personne) a une forme TRES differente de l'envelope d'un autre micro solo (autre personne). La cross-correlation mesure la similarite des enveloppes, donc elle echoue quand les enveloppes sont fondamentalement differentes.

**Solution proposee pour la prochaine session :**
1. Utiliser l'audio des CAMERAS (qui capte le mix ambiant de toutes les voix) comme reference pour la correlation
2. Les cameras correleront bien entre elles (elles captent le meme mix)
3. Les micros individuels seront places au meme offset que leur session (pas correles individuellement)
4. Ou : detecter que deux clips sont de la meme session par leurs metadonnees (duree similaire, timestamps de fichier)

### Convention de signe
`timeline_offset = -python_correlation_lag`

### Export XML
- SyncWave V1 → Premiere V1 + A1 (video + audio stereo)
- SyncWave V2 → Premiere V2 + A2
- SyncWave A1 → Premiere A(N+1) (audio standalone)
- Clips d'une meme piste = plusieurs clipitems dans le meme track XML

### Sparkle
- Cle publique EdDSA : `1AvZry8Dl0dM3/B2UjkbZeziG7erROR+03HNyrP8T+E=`
- Appcast : `https://raw.githubusercontent.com/Lenouw/SyncWave/main/appcast.xml`
- `create-release.sh` signe le zip et met a jour l'appcast automatiquement

## Ce qu'il reste a faire
- [ ] **PRIORITE 1 : Fixer la sync multi-micros** — utiliser l'audio des cameras (mix ambiant) comme reference au lieu des micros individuels. Les cameras captent toutes le meme son → bonne correlation. Placer les micros individuels au meme offset que leur session.
- [ ] **PRIORITE 2 : UI pistes audio associees aux videos** — V1 devrait montrer A1 en dessous
- [ ] **PRIORITE 3 : Precision sub-ms** — affinage cross-correlation fine
- [ ] Detection automatique des sessions par metadonnees (timestamps, durees similaires)
- [ ] Tolerance aux erreurs (clip sur la mauvaise piste → detecter et repositionner)
- [ ] Waveform visuelle sur les clips
- [ ] Distribution .dmg

## Problemes connus
- **Sync micros individuels** : l'envelope cross-correlation echoue quand chaque micro capte une personne differente. Confiance 5-7% entre micros solos → offsets aleatoires.
- **Certains WAV illisibles** : les fichiers de certains dossiers du recorder ne sont pas lisibles par FFmpeg
- **Python/scipy requis** : l'app necessite Python 3 + scipy + numpy

## Notes pour la prochaine session
- Repo : https://github.com/Lenouw/SyncWave (v1.2.0)
- App : /Applications/SyncWave.app
- **Moteur de sync** : `Scripts/sync_multi.py` — la section "Syncing session" fait le all-pairs + greedy graph
- **Export XML** : `Sources/SyncWave/Engine/ExportEngine.swift` — mapping correct
- **Fichiers test podcast multi-invites** : dossiers 5160 + 5161 dans le Dropbox du 17 fev 2026
  - 3 cameras (Cam1, Cam2, Cam3) × 2 sessions
  - Micros individuels : Audio JS, Audio Laura, Audio Vanina, Gaelle Audio, js audio, sherazad
- **L'algo qui FONCTIONNE** : quand on correle camera vs camera ou camera vs enregistreur commun (81-89% confiance)
- **L'algo qui ECHOUE** : quand on correle micro solo A vs micro solo B (5-7% confiance)
- **Approche PluralEyes** : PluralEyes ne correlait pas les micros individuels entre eux. Il utilisait les cameras comme pont, car elles captent le mix ambiant.
