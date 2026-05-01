# Niveaux de difficulté des puzzles

Un classement à 6 paliers (Débutant → Fou furieux) qui regroupe les
puzzles selon le **type de raisonnement** que leur résolution exige.
La cible : pouvoir composer une playlist progressive où chaque palier
introduit une nouvelle compétence cognitive — propagation simple,
puis difficile, puis complicités, puis force.

Le script de classification batch est `bin/classify_difficulty.dart`,
qui consomme la trace `solveExplained()` enrichie (`SolveStep` porte
`complexity` et `isComplicity` depuis le commit `7c3020b`).

## Critères structurels

Cascade descendante, mutuellement exclusifs (un puzzle est rangé dans
la catégorie la plus haute qu'il satisfait) :

| Catégorie       | Critères                                                                |
|-----------------|-------------------------------------------------------------------------|
| **Débutant**    | 0 force, 0 complicité, max propagation ≤ 2                              |
| **Joueur**      | 0 force, 0 complicité, max propagation ≥ 3                              |
| **Avancé**      | 0 force, ≥ 1 complicité, complexité max des complicités ≤ 3             |
| **Balaise**     | 0 force, ≥ 1 complicité de complexité ≥ 4                               |
| **Expert**      | 1 move FORCE, `forceDepth ≤ 5`                                          |
| **Fou furieux** | ≥ 2 moves FORCE, ou 1 move FORCE de `forceDepth > 5`                    |
| Indéterminé     | trace incomplète (timeout / contradiction)                              |

Échelle `Move.complexity` ∈ 0..5, voir `lib/getsomepuzzle/model/cell.dart:74`
et `docs/dev/complexity.md`. Détection complicité = `Move.givenBy is
Complicity`.

L'intention derrière le palier Expert : **"il a fallu poser une
hypothèse pour voir qu'elle est fausse"**. Cette déduction par
contradiction (la "force") est qualitativement différente d'une chaîne
de propagation difficile mais directe ; les deux paliers (Joueur et
Expert) sont donc séparés.

### Décisions de design

- **La durée de résolution n'est pas un critère de palier.** Un
  débutant peut très bien aimer une grande grille à sa portée, un
  expert peut buter sur une petite grille complexe. La taille de
  grille module le ressenti mais ne change pas le palier cognitif.
- **Pas de filtre "emptiness" intégré aux catégories.** À la place :
  expurger du corpus les puzzles trop pré-remplis (qui ne sont pas
  intéressants à jouer indépendamment du palier), puis classifier ce
  qui reste. Voir section suivante.

## Seuil de pré-remplissage

Le générateur (`lib/getsomepuzzle/generator/generator.dart:103`)
choisit `ratio` aléatoirement dans `[0.75, 1.0]` — `ratio` étant la
fraction de cellules **laissée vide** au joueur. Donc le
pré-remplissage initial est borné à **25 %**.

> Note : le `0.25` qu'on retrouve ligne 257 (`if (currentRatio > 0.25)
> return null;`) est un autre concept — le ratio résiduel après solve
> avec contraintes, utilisé pour rejeter les puzzles "trop ouverts" en
> sortie de génération. Sans rapport avec le pré-remplissage initial.

Le script `bin/classify_difficulty.dart` accepte `--max-prefill F`
(défaut `0.30`) ; les puzzles dont `readonly/total > F` tombent dans
la catégorie supplémentaire `Pre-rempli` (et sont écrits dans
`overfilled.txt` quand `--split-out` est utilisé).

**Seuil retenu : 0.30** — légèrement plus permissif que le contrat
du générateur (0.25), pour conserver davantage de puzzles legacy
sans intégrer la queue pathologique. La distribution observée
justifie ce choix (cf. histogramme ci-dessous).

### Histogramme du pré-remplissage

Distribution sur les 12 210 puzzles du corpus (bins de 5 %) :

```
[0.00-0.05)    459   3.76%  █████████
[0.05-0.10)  1 164   9.53%  ███████████████████████
[0.10-0.15)  1 831  15.00%  ████████████████████████████████████
[0.15-0.20)  2 062  16.89%  █████████████████████████████████████████
[0.20-0.25)  1 851  15.16%  █████████████████████████████████████
[0.25-0.30)  1 135   9.30%  ██████████████████████
[0.30-0.35)    827   6.77%  ████████████████
[0.35-0.40)    559   4.58%  ███████████
[0.40-0.45)    636   5.21%  ████████████
[0.45-0.50)    290   2.38%  █████
[0.50-0.55)    430   3.52%  ████████
[0.55-0.60)    272   2.23%  █████
[0.60-0.65)    266   2.18%  █████
[0.65-0.70)    186   1.52%  ███
[0.70-0.75)    103   0.84%  ██
[0.75+]        252   2.07%  (queue jusqu'à 0.96)
```

Cumulatif aux seuils ronds :

| Seuil ≤ | Conservés | %       |
|---------|----------:|--------:|
| 0.20    |     5 516 |  45.2 % |
| 0.25    |     7 367 |  60.3 % |
| 0.30    |     8 502 |  69.6 % |
| 0.40    |     9 888 |  81.0 % |
| 0.50    |    10 814 |  88.6 % |

**Distribution unimodale**, mode à `[0.15-0.20)`. La distribution est
continue ; ni 0.20 ni 0.25 ne sont des points de rupture naturels.
Pour conserver davantage de puzzles legacy on retient **0.30** comme
seuil pratique : 8 502 puzzles passent (69.6 %) contre 7 367 à 0.25
(60.3 %). Au-delà de 0.50 la queue (~11 %, 1 396 puzzles) regroupe
les cas pathologiques type `LT:A.8.23` à 88 % de pré-remplissage —
clairement à expurger.

### Cas d'école

`v2_12_5x5_1222121202211112210121202_LT:A.8.23_..._11` a 22 cellules
readonly sur 25 = **88 %** de pré-remplissage. Pas un puzzle généré
récemment ; à sortir du corpus.

### Tutorial

Sur 23 puzzles de `tutorial.txt`, 8 (35 %) dépassent le seuil 0.25.
C'est **attendu et voulu** : les puzzles d'apprentissage sont
volontairement très pré-remplis pour guider le joueur sur la règle
qu'on lui apprend. Ils ne participeront pas à la classification de
difficulté mais restent dans la collection.

## Distribution sur 100 % du corpus

Run sur les 12 187 puzzles de `assets/default.txt` (collection2 et
collection3 mergées dedans), filtre `--max-prefill 0.30` :

| Catégorie         | Fichier généré      | Total  | % global | % filtré |
|-------------------|---------------------|-------:|---------:|---------:|
| Débutant          | `1-easy.txt`        |  1 750 |   14.4 % |   20.3 % |
| Joueur            | `2-player.txt`      |  1 147 |    9.4 % |   13.3 % |
| Avancé            | `3-advanced.txt`    |  1 749 |   14.4 % |   20.2 % |
| Balaise           | `4-strong.txt`      |  2 291 |   18.8 % |   26.5 % |
| Expert            | `5-expert.txt`      |    728 |    6.0 % |    8.4 % |
| Fou furieux       | `6-mad.txt`         |    975 |    8.0 % |   11.3 % |
| Pré-rempli > 30 % | `overfilled.txt`    |  3 542 |   29.1 % |        — |
| Indéterminé       | `undetermined.txt`  |      5 |    0.0 % |   0.06 % |
| **Total**         |                     | 12 187 |    100 % |    100 % |

```
Débutant     ████████████████          20.3 %
Joueur       ██████████                13.3 %
Avancé       ████████████████          20.2 %
Balaise      █████████████████████     26.5 %
Expert       ██████                     8.4 %
Fou furieux  █████████                 11.3 %
```

## Bilan

La distribution reflète **une progression cognitive monotonique** :

| Palier         | Compétence requise                                     | % filtré |
|----------------|--------------------------------------------------------|---------:|
| Débutant       | propagation simple (saturation, comptage local)        |   20.3 % |
| Joueur         | propagation difficile (articulation, énumération)      |   13.3 % |
| Avancé         | complicités simples (interactions à 2 contraintes)     |   20.2 % |
| Balaise        | complicités difficiles (énumération multi-contraintes) |   26.5 % |
| Expert         | hypothèse + contradiction (force, depth ≤ 5)           |    8.4 % |
| Fou furieux    | force lourde (chaînes longues ou multiples hypothèses) |   11.3 % |

Le palier Expert est volontairement plus étroit que les autres car il
correspond à un saut qualitatif majeur dans le raisonnement (hypothèse
vs. déduction). Sa rareté est attendue, pas une anomalie.

29 % du corpus est pré-rempli > 30 % et donc isolé dans
`overfilled.txt`. Ces puzzles ne respectent pas le contrat du
générateur (`ratio` ∈ [0.75, 1.0], donc max 25 % de pré-remplissage)
et sont candidats à un cleanup ultérieur.

## Intégration dans le générateur

Le calcul du niveau est intégré directement dans
`PuzzleGenerator.generateOne` (`lib/getsomepuzzle/generator/generator.dart`)
qui retourne désormais `(line, level)` au lieu de `String?`. Aucun
solve supplémentaire n'est requis : le `solveExplained()` qui valide
la déductibilité du puzzle est aussi celui qui sert à classifier.

Le palier voyage jusqu'à `bin/generate.dart` via le champ `level` de
`GeneratorPuzzleMessage`. Le CLI a deux modes :

- `--output FILE` : tous les puzzles ajoutés au fichier (legacy).
- *sans `--output`* : routage automatique par palier vers
  `assets/<level>.txt` (`1-easy.txt` … `6-mad.txt`). Les paliers
  out-of-cascade `Pre-rempli` et `Indeterminé` ne sont jamais émis
  par le générateur en live, donc pas de fichier ouvert pour eux
  dans ce mode.

## Intégration UI

Côté joueur, les six fichiers de palier remplacent les anciennes
collections `default` / `collection2` / `collection3` (mergées puis
re-splittées en début 2026-05). Les changements :

- **`pubspec.yaml`** : les six `assets/<level>.txt` + `tutorial.txt`
  + `overfilled.txt` (gardé pour audits futurs) sont déclarés.
- **`Database._builtInCollectionKeys`** (`lib/getsomepuzzle/model/database.dart`)
  liste les nouvelles clés : `tutorial`, `1-easy`, `2-player`,
  `3-advanced`, `4-strong`, `5-expert`, `6-mad`, `custom`.
- **`Database.entryCollectionKey = '1-easy'`** est utilisée comme
  cible par défaut dans `open_page.dart` (fin de tutoriel) et
  `main.dart` (bouton primaire "Start playing").
- **Migration legacy** : si `SharedPreferences` contient encore
  `collectionToLoad = "default"` (ou `collection2`/`collection3`),
  `loadPuzzlesFile` redirige automatiquement vers `1-easy` plutôt
  que de retomber sur `tutorial`.
- **Labels traduits** dans `lib/l10n/app_{en,fr,es}.arb` :
  `collectionTutorial`, `collectionEasy`, `collectionPlayer`,
  `collectionAdvanced`, `collectionStrong`, `collectionExpert`,
  `collectionMad`. Bundle exposé via la classe `CollectionLabels`
  pour ne pas coupler `Database` au l10n.
- **Icônes** (`UniconsLine`) suivent une progression cognitive :
  `smile` → `brain` → `graduation_cap` → `medal` → `trophy` →
  `fire`. Tutorial garde `baby_carriage` et `custom` garde
  `Icons.build`.

### Adaptation au joueur

Les six paliers sont reliés au système d'adaptation décrit dans
`docs/dev/adapt_to_player.md` :

- **Cap de batch** : `preparePlaylist()` tronque chaque playlist de
  palier à 20 puzzles (`Database.playlistBatchSize`). `tutorial`,
  `custom` et les playlists utilisateurs ne sont pas capés.
- **Recommandation** : `Database.recommendedCollectionKey` mappe
  `playerLevel` (0..100, anchored à 50) vers un palier via des seuils
  fixes (`recommendedLevelFor` dans `level.dart`). Surfacée comme une
  étoile dans le dropdown de `open_page` et comme bouton "Essayer X"
  dans `EndOfPlaylist`.
- **Continuer / Changer** : à chaque fin de batch, `EndOfPlaylist`
  propose au joueur de continuer dans la collection courante (nouveau
  batch de 20) ou de basculer vers la collection recommandée. Le
  joueur garde la main, l'app ne change jamais de palier toute seule.
