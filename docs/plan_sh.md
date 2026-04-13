# Plan d'implémentation : Contrainte Shape (SH)

## Résumé

Nouvelle contrainte globale : **"Tous les groupes de cette couleur doivent avoir cette forme"**.

- **Slug** : `SH`
- **Label** : `Shape`
- **Format** : `SH:shape` (ex: `SH:111`, `SH:20.22`)
- **Encodage de la forme** : identique à FM (lignes séparées par `.`, `1` = cellule noire, `2` = cellule blanche, `0` = cellule vide)
- **Rotations & symétries** : la forme est invariante par rotation (0°, 90°, 180°, 270°) et par miroir. `111` = `1.1.1`, `110.011` = `011.110` = `10.11.01`, etc.

## Étape 1 : Utilitaire de normalisation des formes

**Fichier** : `lib/getsomepuzzle/constraints/shape.dart`

Avant toute comparaison, une forme doit être normalisée pour gérer l'invariance par rotation/miroir.

### Algorithme

1. **Représentation canonique** : une forme est une `List<List<int>>` (matrice 2D, valeurs du domaine : `1` = noir, `2` = blanc, `0` = vide). La couleur est portée par les cellules non-nulles de la forme.
2. **Générer les 8 variantes** : 4 rotations × 2 (original + miroir horizontal).
   - Rotation 90° : `(r, c) → (c, rows - 1 - r)`
   - Miroir horizontal : `(r, c) → (r, cols - 1 - c)`
   - Les valeurs non-nulles sont préservées telles quelles lors des transformations.
3. **Normaliser chaque variante** : supprimer les lignes/colonnes vides en bordure (trim).
4. **Choisir la forme canonique** : la plus petite variante en ordre lexicographique (sérialiser chaque variante en string et prendre le min).

**Fonctions exposées** :
- `List<List<int>> normalizeShape(List<List<int>> shape)` → forme canonique
- `List<List<List<int>>> allRotations(List<List<int>> shape)` → les 8 variantes (après trim), dédoublonnées
- `bool shapesAreEquivalent(List<List<int>> a, List<List<int>> b)` → comparaison via formes canoniques
- `int shapeColor(List<List<int>> shape)` → extrait la couleur (la valeur non-nulle unique dans la forme)

## Étape 2 : Classe `ShapeConstraint`

**Fichier** : `lib/getsomepuzzle/constraints/shape.dart`

```
class ShapeConstraint extends Constraint {
  int color;                        // La couleur contrainte, déduite de la forme (1 ou 2)
  List<List<int>> shape;            // La forme canonique normalisée (valeurs du domaine)
  List<List<List<int>>> variants;   // Toutes les rotations/miroirs (pour matching)
  int shapeSize;                    // Nombre de cellules occupées (non-nulles) dans la forme
}
```

### Constructeur `ShapeConstraint(String strParams)`

- Parse `strParams` exactement comme FM : lignes séparées par `.`, chaque caractère est une valeur.
  - `SH:111` → forme=`[[1,1,1]]`, couleur déduite = 1
  - `SH:20.22` → forme=`[[2,0],[2,2]]`, couleur déduite = 2
- Déduit `color` = la valeur non-nulle unique dans la forme (erreur si la forme contient des valeurs non-nulles mixtes, ex: `12`).
- Calcule et stocke les variantes via `allRotations()`.
- Stocke `shapeSize` = nombre de cellules non-nulles dans la forme.

### `String get slug` → `'SH'`

### `String toString()`

Retourne une représentation courte, par ex. la forme sérialisée : `"111"` ou `"20.22"`.

### `String toHuman()`

Retourne une description lisible : `"All black groups must have shape [shape]"` ou `"All white groups must have shape [shape]"`.

### `String serialize()`

Retourne `"SH:shape"` (la forme en format original, pas canonique, pour rester fidèle au puzzle source). Ex: `"SH:111"`, `"SH:20.22"`.

### `bool verify(Puzzle puzzle)`

1. Appeler `puzzle.getGroups()` pour obtenir tous les groupes connectés.
2. Filtrer les groupes de la couleur `color` (en vérifiant `puzzle.cellValues[group.first] == color`).
3. Pour chaque groupe de cette couleur :
   a. Extraire la bounding box du groupe (min/max row/col).
   b. Construire la matrice 2D du groupe dans cette bounding box (`color` pour les cellules du groupe, `0` ailleurs).
   c. Vérifier si cette matrice correspond à une des variantes de la forme (comparaison directe, les valeurs de couleur sont déjà les mêmes).
4. **Puzzle incomplet** — un groupe ouvert (avec voisins libres) peut encore évoluer, mais certaines violations sont déjà détectables :
   a. **Débordement de bounding box** : calculer la bounding box du groupe (hauteur × largeur). Vérifier qu'il existe au moins une variante dont la bounding box peut contenir celle du groupe (i.e. `group_h <= variant_h && group_w <= variant_w`). Les variantes issues de rotations ont des bounding boxes différentes (une forme 2×3 produit aussi une variante 3×2), donc il faut tester toutes les variantes. Si aucune variante ne peut contenir le groupe → `false`. Ex: un groupe en ligne 1×4 ne rentre dans aucune variante d'une forme 2×2.
   b. **Nombre de cellules dépassé** : si `group.length > shapeSize` → `false`. Vérification rapide complémentaire à (a). Ex: groupe de 3 cellules pour contrainte `SH:11` (2 cellules).
   c. **Forme incompatible** : si le groupe ne peut être contenu dans aucune variante de la forme → `false`. C'est-à-dire qu'il n'existe aucun placement (par translation) d'une variante tel que toutes les cellules du groupe correspondent à des cellules occupées de la variante. C'est une vérification plus fine que (a) et (b) : elle vérifie la géométrie exacte, pas seulement les dimensions. Ex: groupe `11.11` (carré 2×2) pour contrainte `SH:10.11` (L) — la bounding box 2×2 rentre, le nombre de cellules est ≤, mais le carré ne correspond à aucune rotation/miroir du L.
   d. Sinon → le groupe est encore potentiellement valide, on l'accepte.
   e. Les groupes fermés (sans voisin libre) doivent correspondre exactement à une variante.
5. **Puzzle complet** : tous les groupes de la couleur doivent correspondre exactement.
6. Retourner `true` si tous les groupes (vérifiés) correspondent.

**Note sur le test de sous-forme (4c)** : c'est le même algorithme "sous-forme compatible" que celui décrit dans `apply()` niveau 4. On peut le factoriser en une méthode utilitaire `bool groupFitsInVariant(Set<int> groupCells, List<List<int>> variant, Puzzle puzzle)` réutilisée par `verify()` et `apply()`. Les vérifications (4a) et (4b) sont des pré-filtres rapides avant la vérification exhaustive (4c).

### `Move? apply(Puzzle puzzle)` — Déduction avancée

L'algo de déduction doit être sophistiqué et bien commenté. Voici les niveaux de déduction :

#### Niveau 1 : Détection d'impossibilité

- Un groupe fermé (sans voisin libre) de la couleur `color` qui ne correspond à aucune variante → `Move(0, 0, this, isImpossible: this)`.
- Un groupe fermé dont la taille ≠ `shapeSize` → impossible.

#### Niveau 2 : Groupe complet → fermer les bordures

- Si un groupe de la couleur `color` correspond déjà exactement à une variante et a la bonne taille → tous ses voisins libres doivent être de la couleur opposée (comme GS quand le groupe atteint sa taille cible).

#### Niveau 3 : Groupe incompatible → impossible

- Un groupe de la couleur `color` qui ne peut être contenu dans aucune variante → impossible. Cela inclut :
  - Nombre de cellules > `shapeSize`
  - Bounding box du groupe ne rentre dans la bounding box d'aucune variante (en tenant compte de toutes les rotations/miroirs)
  - Géométrie exacte incompatible (même si bounding box et nombre de cellules OK)
- Ce sont les mêmes vérifications que `verify()` étape 4a/4b/4c, factorisées dans la méthode utilitaire partagée.

#### Niveau 4 : Extension impossible → bloquer

- Pour chaque voisin libre d'un groupe en cours de construction :
  - Simuler l'ajout de ce voisin au groupe.
  - Si le nouveau sous-ensemble ne peut correspondre au début d'aucune variante (c'est-à-dire que le sous-ensemble n'est contenu dans aucune variante) → ce voisin doit être de la couleur opposée.
- **Algorithme "sous-forme compatible"** : un sous-ensemble de cellules est compatible avec une variante si on peut le placer (par translation) à l'intérieur de la variante de sorte que chaque cellule du sous-ensemble correspond à un `1` de la variante.

#### Niveau 5 : Cellule obligatoire → forcer

- Pour un groupe incomplet, énumérer toutes les façons de le compléter en plaçant les variantes compatibles.
- Si une cellule libre apparaît dans **toutes** les complétions possibles → elle doit être de la couleur `color`.
- Si une cellule libre n'apparaît dans **aucune** complétion possible mais est voisine du groupe → elle doit être de la couleur opposée.

#### Niveau 6 : Voisin de cellule libre qui forcerait une forme impossible

- Si placer la couleur `color` sur une cellule libre créerait un nouveau groupe (ou fusionnerait des groupes existants) dont la forme ne peut pas être complétée en une variante valide → cette cellule doit être de la couleur opposée.

**Complexité** : les niveaux 4-6 nécessitent d'énumérer les placements possibles des variantes. Pour des formes petites (≤5 cellules), c'est rapide. Pour des formes plus grandes, on pourra ajouter des optimisations plus tard.

**Commentaires** : chaque niveau de déduction sera clairement séparé et commenté dans le code avec des exemples.

## Étape 3 : Enregistrement dans le registre

**Fichier** : `lib/getsomepuzzle/constraint_registry.dart`

- Ajouter l'import de `shape.dart`.
- Ajouter l'entrée : `(slug: 'SH', label: 'Shape', fromParams: ShapeConstraint.new)`.

## Étape 4 : Affichage UI — Widget dans la barre du haut

### Comptage top bar

**Fichier** : `lib/widgets/puzzle.dart`

La contrainte SH est globale (pas cell-centric). Il faut l'inclure dans le comptage des contraintes de la barre du haut :

- Ligne ~106-111 : ajouter `ShapeConstraint` au filtre `constraint is Motif || constraint is QuantityConstraint` → `constraint is Motif || constraint is QuantityConstraint || constraint is ShapeConstraint`.
- Ligne ~139-141 : ajouter `ShapeConstraint` au test `constraintIsInTopBar`.

### Rendu du widget

**Fichier** : `lib/widgets/puzzle.dart`

Ajouter un `else if (constraint is ShapeConstraint)` dans le `Wrap` (après le bloc `MotifWidget`, ligne ~193) :

```dart
else if (constraint is ShapeConstraint)
  MotifWidget(
    key: (constraint.isHighlighted && constraintIsInTopBar)
        ? _constraintKey
        : null,
    motif: constraint.shape,  // même encodage que FM, fonctionne directement
    bgColor: shapeColor,      // vert forêt, nouvelle constante
    borderColor: constraint.isHighlighted
        ? highlightColor
        : (constraint.isValid ? Colors.green : Colors.deepOrange),
    isHighlighted: constraint.isHighlighted,
    cellSize: topBarConstraintsSize,
  )
```

### Nouvelle couleur

**Fichier** : `lib/widgets/puzzle.dart`

Ajouter une constante :
```dart
const shapeColor = Color(0xFF228B22);  // Forest green
```

### Compatibilité avec le MotifWidget

**Aucune modification nécessaire** sur `lib/widgets/motif.dart`.

La forme SH utilise le même encodage que FM (`1` = noir, `2` = blanc, `0` = transparent), ce qui correspond exactement au mapping `bgColors` du `MotifWidget`. La forme peut être passée directement en tant que `motif` sans transformation.

## Étape 5 : Localisation

### Fichiers ARB

Ajouter dans les 3 fichiers de localisation :

**`lib/l10n/app_en.arb`** :
```json
"constraintShape": "shape",
"@constraintShape": {
  "description": "Label for the Shape constraint"
}
```

**`lib/l10n/app_fr.arb`** :
```json
"constraintShape": "forme"
```

**`lib/l10n/app_es.arb`** :
```json
"constraintShape": "forma"
```

Puis lancer `flutter gen-l10n` pour régénérer les fichiers Dart.

## Étape 6 : Tests

**Fichier** : `test/shape_constraint_test.dart`

### Tests de normalisation

- `111` et `1.1.1` produisent la même forme canonique (rotation 90°).
- `110.011` et `011.110` et `10.11.01` sont équivalentes (rotation + miroir).
- `222` et `2.2.2` produisent la même forme canonique (rotation 90°, couleur 2).
- Deux formes réellement différentes ne sont PAS équivalentes (ex: `111` vs `11.10`).
- Deux formes de couleurs différentes ne sont PAS équivalentes (ex: `111` vs `222`).

### Tests de verify

- Puzzle complet avec tous les groupes de la bonne forme → `true`.
- Puzzle complet avec un groupe de la bonne taille mais mauvaise forme → `false`.
- Puzzle complet avec un groupe de mauvaise taille → `false`.
- Puzzle incomplet avec groupe ouvert compatible → `true` (tolérance).
- Puzzle incomplet avec groupe fermé de mauvaise forme → `false`.
- Puzzle incomplet avec groupe ouvert dépassant le nombre de cellules → `false` (ex: groupe `1.1.1` pour `SH:11`).
- Puzzle incomplet avec groupe ouvert dont la bounding box ne rentre dans aucune variante → `false` (ex: groupe 1×4 pour une forme 2×2).
- Puzzle incomplet avec groupe ouvert dont la bounding box rentre (grâce à une rotation) → `true` (ex: groupe 2×3 pour une forme 3×2 — la rotation produit une variante 2×3 compatible).
- Puzzle incomplet avec groupe ouvert de forme déjà incompatible malgré bounding box OK → `false` (ex: groupe `11.11` pour `SH:10.11` — bounding box 2×2 rentre, mais le carré ne correspond à aucune variante du L).

### Tests de apply

- Groupe complet → ferme les bordures (niveau 2).
- Groupe trop grand → détecte impossibilité (niveau 3).
- Extension qui rendrait la forme impossible → bloque (niveau 4).
- Cellule obligatoire dans toutes les complétions → force (niveau 5).

### Tests avec puzzles fournis

Le développeur fournira des puzzles de test manuellement.

## Étape 7 : Aide / description

**Fichier** : `lib/getsomepuzzle/constraints/shape.dart` ou help files

Ajouter une description de la contrainte accessible dans l'aide du jeu :
- EN: "All groups of this color must have this shape (rotations and reflections are allowed)"
- FR: "Tous les groupes de cette couleur doivent avoir cette forme (rotations et réflexions autorisées)"
- ES: "Todos los grupos de este color deben tener esta forma (se permiten rotaciones y reflejos)"

## Ordre d'implémentation

1. **Utilitaires de forme** (normalisation, rotations, comparaison) + tests unitaires
2. **Classe ShapeConstraint** : constructeur, slug, serialize, toString, toHuman
3. **verify()** + tests
4. **apply() niveaux 1-3** (détection impossibilité, fermeture bordures, taille dépassée) + tests
5. **apply() niveaux 4-6** (extension impossible, cellule obligatoire, fusion impossible) + tests
6. **Enregistrement dans le registre**
7. **UI** : widget dans la barre du haut avec couleur vert forêt
8. **Localisation** : ARB + gen-l10n
9. **Test intégration** : avec puzzles fournis par le développeur

## Hors scope (pour plus tard)

- Intégration au générateur de puzzles (`generator.dart`)
- Ajout de puzzles SH dans `assets/default.txt` et `assets/tutorial.txt`
- Page de création de puzzles (`create_page.dart`) — support de SH
- Optimisation des restrictions GS ↔ SH (ex: si SH est présent, GS est redondant pour cette couleur)
