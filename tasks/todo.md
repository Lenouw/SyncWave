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

## Backlog

- [ ] Pistes audio stéréo dans Premiere (G+D au lieu de mono) — non résolu, plusieurs tentatives infructueuses
- [ ] Précision sub-ms (affinage cross-correlation fine)
- [ ] Détection automatique des sessions par métadonnées
- [ ] Distribution .dmg
- [ ] Tolérance aux erreurs (clip sur mauvaise piste)
