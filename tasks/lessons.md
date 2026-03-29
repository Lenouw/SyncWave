# Lessons Learned

*(Rempli au fil du projet)*

## 2026-03-29 | Confidence 0% sur fichiers 37min (podcast)

**Ce qui a mal tourné:** `plainCrossCorrelation` calculait la confidence comme `maxVal / sqrt(refEnergy * tgtEnergy)`. Après normalisation des enveloppes (mean=0, RMS=1), l'énergie de chaque enveloppe = N samples (~445383). Le `maxVal` lui-même est scalé par `1/fftSize` (~9.5e-7). Résultat: confidence = 0.33 / 428581 ≈ 0.0000008 → arrondi à 0%.

**La corrélation et l'offset étaient pourtant corrects** (offset -159.090s pour CAM2, -156.510s pour CAM3, pic/mean ratio > 76). Le bug était uniquement dans la formule de confidence.

**Règle:** Pour des enveloppes normalisées (RMS=1), utiliser le peak-to-mean ratio comme confidence (même formule que `gccphatPeakConfidence`): `confidence = min(1, (ratio - 1) / 9)`. Ne jamais utiliser `maxVal / sqrt(E1*E2)` quand les signaux sont normalisés ET que maxVal inclut un facteur d'échelle `1/fftSize`.
