# Todo

## En cours
- [ ] **UI sub-tracks audio sous les videos** — voir design ci-dessous

## Fait (cette feature)
- [x] Ajout `audioChannelCount` a MediaClip + detection FFprobe a l'import (AppState)
- [x] Creation `WaveformGenerator.swift` (DSP/vDSP, peaks par canal)

## Reste a faire (cette feature)
- [ ] Ajouter appel WaveformGenerator dans AppState.importToTrack (generer waveforms a l'import)
- [ ] Creer `AudioSubTrackView.swift` — sous-piste audio (hauteur 16px, label ch1/ch2, waveform)
- [ ] Creer `WaveformView.swift` — view SwiftUI pour dessiner les peaks
- [ ] Modifier `MultiTrackTimelineView` — rendre les sous-pistes sous chaque video track
- [ ] Ajouter waveforms aussi sur les clips des pistes audio standalone
- [ ] Ajouter waveforms sur les clips video (dans le clipBlock de TrackRowView)
- [ ] Build + test visuel

## Design valide
- Approche A : sub-tracks integres (comme NLE)
- Chaque video montre ses canaux audio en dessous, toujours visibles
- Nombre de canaux dynamique selon le fichier (mono=1, stereo=2, etc.)
- Sous-pistes : hauteur 16px, indentees, label "ch1"/"ch2", couleur verte
- Pistes standalone inchangees
- Separateur pointille entre videos et audio standalone
- Waveforms sur TOUS les clips (video + audio sub-tracks + standalone)

## Backlog (autres features)
- [ ] Precision sub-ms (affinage cross-correlation fine)
- [ ] Detection automatique des sessions par metadonnees
- [ ] Waveform visuelle sur les clips ← EN COURS avec la feature sub-tracks
- [ ] Distribution .dmg
- [ ] Tolerance aux erreurs (clip sur mauvaise piste)
