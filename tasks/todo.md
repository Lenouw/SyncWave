# Todo — SyncWave

## Statut actuel
**v1.5.0 — tout fonctionne, aucune tâche en cours**

## Tout ce qui est DONE

- [x] Sync multi-caméras (78-90% confiance, 3 cam × 2 sessions validé)
- [x] Sync micros individuels via caméras comme pont (clustering auto)
- [x] Export FCP 7 XML v4 — 6 pistes propres dans Premiere (V1/V2/V3 + A1/A2/A3)
- [x] Résolution vidéo dynamique dans le XML (4K si fichiers 4K)
- [x] Waveforms sur les clips audio (WaveformGenerator via AVAssetReader + vDSP)
- [x] Sous-pistes audio (ch1/ch2) sous chaque piste vidéo dans la timeline
- [x] Piste V3 par défaut
- [x] Notification de fin de sync (NSSound + UNUserNotification)
- [x] Auto-updater Sparkle (EdDSA)
- [x] UI timeline NLE (drag & drop par piste, progress visuel)

## PRIORITÉ — v1.6.0 (retours bêta test)

- [ ] **Bundler sync_multi.py en binaire standalone via PyInstaller** — zéro dépendance Python/numpy/scipy pour l'utilisateur. L'app doit fonctionner out-of-the-box sans rien installer.
  - Contexte : pip3 install échoue sur macOS récent (PEP 668 "externally-managed-environment"), numpy installé pour Python 3.9 mais SyncWave utilise Python 3.14 Homebrew → incompatibilité totale
  - Solution : `pyinstaller --onefile sync_multi.py` → binaire `dist/sync_multi` bundlé dans `Resources/`
  - SyncEngine.swift : utiliser le binaire bundlé en priorité, fallback python3 si absent
- [ ] **Bundler FFmpeg dans l'app** — télécharger le binaire statique FFmpeg (~80MB) et le mettre dans `Resources/`. Même problème : FFmpeg Homebrew invisible pour les apps GUI macOS.

## Backlog

- [ ] Pistes audio stéréo dans Premiere (G+D au lieu de mono) — non résolu, plusieurs tentatives infructueuses
- [ ] Précision sub-ms (affinage cross-correlation fine)
- [ ] Détection automatique des sessions par métadonnées
- [ ] Distribution .dmg
- [ ] Tolérance aux erreurs (clip sur mauvaise piste)
