# Recherche PluralEyes -- Rapport complet

## 1. Qu'est-ce que PluralEyes

PluralEyes etait un logiciel de synchronisation audio/video automatique, cree par **Bruce Sharpe** chez **Singular Software** en 2009. Il analysait les formes d'onde audio des clips video et des enregistrements audio externes pour les aligner automatiquement sur une timeline.

**Chronologie de propriete :**
- 2009 : Lancement par Singular Software (presente au NAB)
- 2012 : Acquisition par Red Giant Software
- 2020 : Maxon acquiert Red Giant
- Fev 2023 : Passage en mode maintenance limitee
- Fev 2024 : Fin du support technique et des corrections de bugs

**Derniere version : 4.1.12** (sortie le 29 juin 2022)

---

## 2. Fonctionnalites principales

### Synchronisation automatique
- Analyse les formes d'onde audio de TOUS les clips importes
- Trouve les patterns communs entre les pistes
- Aligne automatiquement les clips sur la timeline
- Un clic pour synchroniser des dizaines de clips multicam

### Correction de derive audio (Audio Drift Correction)
- Detecte et corrige la derive entre audio et video sur les enregistrements longs (30+ minutes)
- Particulierement utile pour les interviews et evenements
- Possibilite de desactiver si la derive est negligeable (ajoutee en v4.1)
- Comparaison avant/apres la correction

### Code couleur des clips
- **Vert** : clip synchronise avec succes
- **Jaune** : sync incertaine / a verifier manuellement
- **Rouge** : sync echouee
- Les clips non synchronises peuvent etre envoyes a la fin de la timeline

### Smart Start
- Configuration automatique a l'import des medias
- Organisation automatique des clips par dossier source en pistes separees (1 dossier = 1 camera = 1 piste)

### Modes de fonctionnement
1. **Application standalone** : glisser-deposer les medias, synchroniser, exporter
2. **Panel Premiere Pro** : synchronisation directe dans Premiere sans quitter l'application
3. **Workflow XML/AAF** : import/export de timelines entre NLEs

### Autres fonctionnalites
- Moniteur de preview integre pour verifier la sync
- Mise a l'echelle verticale des formes d'onde
- Support du spanning GoPro (assemblage auto des fichiers chapitres)
- Selection et suppression multiple de clips
- Raccourcis clavier
- Support de nombreux formats : MP4, MOV, WAV, MP3, BRAW, RED

---

## 3. Workflow typique

### Mode Standalone
1. Ouvrir PluralEyes
2. Glisser-deposer les fichiers media (video + audio externe)
3. PluralEyes cree des fichiers temporaires d'extraction audio
4. Organisation auto par dossier en pistes separees
5. Cliquer "Synchronize"
6. Verifier via le code couleur + moniteur de preview
7. Exporter : XML (pour Premiere/FCP/DaVinci) ou nouveaux fichiers media

### Mode Panel Premiere Pro
1. Ouvrir Premiere Pro, creer une sequence
2. Placer les clips sur la timeline (chaque camera sur une piste video separee)
3. Ouvrir Window > Extensions > PluralEyes
4. Le panel scanne les fichiers automatiquement
5. Cliquer Sync
6. PluralEyes genere une nouvelle timeline synchronisee

### Mode Export/Import XML
1. Dans le NLE, creer une timeline avec les clips organises par piste
2. Exporter en XML (ou AAF pour les anciennes versions avec Avid)
3. Importer le XML dans PluralEyes standalone
4. Synchroniser
5. Exporter un nouveau XML
6. Re-importer dans le NLE = "sync map" prete

---

## 4. Fonctionnement technique

### Algorithme de base : Cross-correlation de formes d'onde

PluralEyes utilise une approche en deux etapes :

#### Etape 1 : Fingerprinting audio (recherche grossiere)
- Extraction de l'audio de chaque clip video/audio
- Creation d'un "fingerprint" base sur le **spectrogramme** (decomposition temps-frequence via FFT/Fourier)
- Le fingerprint capture le contenu spectral, le tempo et le rythme
- Comparaison des fingerprints entre clips pour trouver les correspondances grossieres (precision ~ frame)
- Reduit enormement le cout de calcul vs cross-correlation brute

#### Etape 2 : Cross-correlation (alignement precis)
- Une fois la correspondance grossiere trouvee, application de la **cross-correlation generalisee** (GCC-PHAT / Generalized Cross Correlation with Phase Transform)
- Calcule le decalage temporel exact entre deux signaux audio
- Precision au niveau de l'echantillon audio (sub-frame)
- L'alignement final est au sample pres

#### Correction de derive
- Pour les longs enregistrements, les horloges des differents appareils derivent
- PluralEyes segmente les clips et recalcule la sync sur plusieurs points
- Applique une correction progressive pour maintenir l'alignement sur toute la duree

### Conditions requises
- Le son enregistre par la camera ("scratch audio") DOIT etre present
- Ce scratch audio doit etre suffisamment clair pour l'analyse
- Si l'audio camera est trop bruite, faible ou distordu, la sync echoue
- Pas besoin de clap ou de timecode -- le son ambiant suffit

### Performance observee
- 1h30 de rushes multicam : ~18 secondes de traitement (apres preparation des fichiers)

---

## 5. NLEs supportes

### Version 4.x (derniere generation)
| NLE | Mode | Format d'echange | Notes |
|-----|------|-------------------|-------|
| Adobe Premiere Pro | Panel integre + Standalone | XML | Integration la plus poussee |
| Final Cut Pro X | Standalone | FCPXML | Option de creation de multicam clip |
| DaVinci Resolve | Standalone | XML | Ajoute en v4.1.11 (aout 2020) |
| EDIUS | Standalone | FCP 7 XML | Via import XML compatible |
| Vegas Pro | Standalone | XML | Support historique |

### Supporte dans les versions anterieures mais RETIRE en v4.0
| NLE | Format | Raison du retrait |
|-----|--------|-------------------|
| Avid Media Composer | AAF | Complexite technique trop elevee |

### Fonctionnalites retirees en v4.0
- Support AAF (Avid)
- Bouton "Takes" (workflow clip musical)
- Options "Allow Sync to Change Clip Order" et "Level Audio"

---

## 6. Pourquoi PluralEyes a ete discontinue

### Raison principale : les NLEs ont integre la fonctionnalite
- Premiere Pro : "Merge Clips" / "Synchronize" par waveform
- Final Cut Pro X : Multicam auto par waveform
- DaVinci Resolve : Auto-sync par waveform dans le Media Pool
- Avid Media Composer : Sync par waveform integree

### Limites des outils integres (avantage restant de PluralEyes)
- Les outils NLE natifs echouent souvent sur les shoots multicam complexes
- Pas de correction de derive dans les NLEs
- Moins fiables avec de nombreux clips simultanes
- PluralEyes gerait mieux les situations audio difficiles

### Facteurs additionnels
- L'adoption du timecode (surtout avec les cameras modernes) a reduit le besoin de sync par waveform
- Maxon a recentre ses activites apres l'acquisition de Red Giant
- Marche de niche avec des revenus decroissants

---

## 7. Alternatives actuelles

- **Syncaila** : Alternative standalone la plus directe (Mac/Windows)
- **DaVinci Resolve** : Sync native gratuite
- **Premiere Pro** : Merge Clips / Synchronize
- **Final Cut Pro** : Multicam auto
- **Tentacle Sync** : Solution hardware + software avec timecode

---

## 8. Enseignements pour le clone

### Ce qu'il faut reproduire absolument
1. Sync en un clic sur des dizaines de clips
2. Correction de derive audio
3. Code couleur pour feedback visuel (succes/incertain/echec)
4. Support de multiples cameras + sources audio
5. Export vers les principaux NLEs (XML, FCPXML)
6. Tolerance au bruit / scratch audio de mauvaise qualite

### Ce que les NLEs natifs font MAL (opportunite)
1. Sync par lot de nombreux clips simultanes
2. Correction de derive sur enregistrements longs
3. Gestion robuste des cas edge (audio bruite, clips courts, etc.)
4. Feedback visuel clair sur l'etat de la sync
5. Workflow standalone independant du NLE

### Stack technique a considerer
- **FFT / Spectrogramme** pour le fingerprinting audio
- **Cross-correlation (GCC-PHAT)** pour l'alignement precis
- **Libraries potentielles** : libfftw3, chromaprint, aubio, librosa (Python), ou Web Audio API
- **Formats d'echange** : XML (Premiere/Resolve), FCPXML (FCP), potentiellement AAF (Avid)
