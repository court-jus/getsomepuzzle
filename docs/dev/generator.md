# Génération de puzzles — exploration

Document de brainstorming pour explorer différentes approches de génération de puzzles, au-delà de l'algorithme actuel.

## 1. L'algorithme actuel

Implémenté dans `lib/getsomepuzzle/generator/generator.dart`. L'approche est **grille → contraintes** : on part d'une solution concrète, puis on cherche les contraintes qui la caractérisent le mieux.

### 1.1. Principe

1. **Construire une grille solution aléatoire.** Chaque cellule reçoit une valeur tirée au hasard dans le domaine `{1, 2}` (noir/blanc). Cas particulier pour la contrainte `SH` (Shape) : la grille est amorcée en plaçant un motif cible, puis complétée avec la couleur opposée, de façon à garantir qu'une contrainte Shape sera satisfaite.

2. **Pré-remplir un peu.** Un ratio aléatoire dans `[0.8, 1.0]` détermine quelle fraction de cellules reste à deviner ; les autres sont verrouillées (readonly) à leur valeur cible. Autrement dit, 0 % à 20 % de la grille est donnée au joueur comme indice.

3. **Énumérer toutes les contraintes candidates.** Pour chaque type (`FM`, `PA`, `GS`, `LT`, `QA`, `SY`, `DF`, `SH`, `CC`, `GC`), on génère toutes les instances paramétriques possibles pour les dimensions du plateau, puis on ne garde que celles qui sont **vérifiées par la grille solution**. C'est l'ensemble des contraintes « vraies » pour cette solution.

4. **Trier les candidates.** Mélange aléatoire, puis tri par statistiques d'usage globales : les slugs peu représentés dans la collection existante passent en tête (levier de diversité). Les règles marquées `required` passent devant tout le reste.

5. **Cherry-picking glouton.** Tant que la grille n'est pas entièrement déterminée :
   - On prend la prochaine candidate.
   - On clone le puzzle courant et on le résout (`solve()` : propagation + force, **sans backtracking**) pour obtenir `ratio_before` (fraction de cellules encore libres).
   - On ajoute la candidate au clone et on résout à nouveau pour obtenir `ratio_after`.
   - Si `ratio_after < ratio_before`, la contrainte est « utile » : on la garde.
   - Après chaque ajout, on re-mélange les candidates restantes et on re-trie par usage **local** (favorise la diversité au sein du puzzle).

6. **Finaliser.**
   - Si ratio résiduel ≤ 0.25 : on bouche les cellules restantes avec la solution connue (pré-remplissage forcé).
   - Sinon : on jette le puzzle.
   - Dernier filtre : `isDeductivelyUnique()` — `solve()` (propagation+force) doit atteindre `ratio == 0` à partir des cellules readonly. Si ce n'est pas le cas, le puzzle est rejeté. Cette convention remplace l'ancien `countSolutions() == 1` (qui s'appuyait sur du backtracking) par un test plus strict mais aligné sur le solveur in-game : tout puzzle publié est garanti résolvable par les hints du joueur, sans deviner.

### 1.2. Avantages

- **Solution connue par construction.** La grille solution est l'entrée, donc chaque contrainte ajoutée est trivialement satisfaisable ; pas besoin de résoudre pour vérifier la cohérence globale.
- **Utilise le solveur comme métrique.** L'« utilité » d'une contrainte est mesurée par la réduction de ratio que le solveur (propagation + force) obtient en la rajoutant — ça couple directement génération et expérience de résolution, et garantit l'alignement avec le solveur in-game.
- **Diversité par design.** Le double tri (global : rareté dans la collection ; local : rareté dans le puzzle) pousse vers des puzzles variés, plutôt que toujours les mêmes contraintes « bon marché ».
- **Simple et robuste.** Algo glouton, peu de paramètres, **aucun backtracking** : ni dans la sélection des contraintes, ni dans le check final d'unicité (`isDeductivelyUnique()` se contente de `solve()` = propagation+force). Facile à débuguer, facile à paralléliser (chaque tentative est indépendante).
- **Facile à contraindre.** Les `requiredRules` / `bannedRules` s'expriment naturellement comme un filtre en amont de l'énumération.

### 1.3. Inconvénients

- **La grille aléatoire décide de tout.** L'espace des contraintes intéressantes est entièrement conditionné par la solution tirée au sort dès le départ. Une grille « banale » (50/50 uniforme, aucune symétrie, aucune structure) ne produira jamais un puzzle élégant basé sur `SY` ou `SH`, même si un tel puzzle existe à ces dimensions.
- **La métrique d'utilité est grossière.** Compter la réduction de `ratio` ne fait pas la différence entre :
  - une contrainte qui débloque **une** cellule triviale,
  - une contrainte qui déclenche une **cascade** de déductions,
  - une contrainte qui n'aide qu'en combinaison avec une autre.
  Résultat : le solveur peut écarter une contrainte « pivot » parce qu'elle ne paie pas immédiatement, et en garder une banale qui rogne une cellule.
- **Glouton local, sans retour arrière.** L'ordre d'essai détermine le résultat. Une contrainte acceptée tôt peut rendre inutiles des contraintes plus élégantes qu'on aurait préférées — il n'y a pas de mécanisme pour reconsidérer.
- **Pas de contrôle sur la difficulté.** La complexité émerge ; on ne peut pas demander « un puzzle easy avec 3 force rounds ». Il faut générer en masse et filtrer a posteriori.
- **Le seuil 0.25 est un pis-aller.** Quand les contraintes ne suffisent pas à tout déterminer, on comble en pré-remplissant — ce qui donne des puzzles visuellement plus chargés et perçus (à raison) comme moins « purs ». Beaucoup de puzzles finaux doivent leur unicité à ces indices ajoutés, pas à leurs contraintes.
- **Contraintes redondantes possibles.** Deux contraintes peuvent chacune réduire le ratio indépendamment, mais être équivalentes ou subsumées l'une par l'autre une fois combinées. Le test `ratio_after < ratio_before` ne le voit pas.
- **Coût d'énumération.** Sur des grilles plus grandes, `generateAllParameters` pour les types riches (FM, SH) devient coûteux, et chaque candidate implique un solve complet.
- **Biais vers les solutions « molles ».** Les grilles aléatoires à 50/50 n'ont typiquement pas de structure notable (pas de gros groupes connexes, pas de symétrie). Ce sont les moins intéressantes pour les contraintes structurelles (`GS`, `SY`, `SH`, `GC`).

## 2. Questions avant d'explorer d'autres pistes

Avant de proposer des alternatives, j'ai besoin de clarifier quelques choix de design :

1. **Objectif principal.** Vise-t-on (a) **générer beaucoup** de puzzles rapidement (batch qui remplace `default.txt`), (b) **générer à la demande** dans l'app avec une UX fluide (< quelques secondes), ou (c) **générer de la qualité** (peu de puzzles, mais jolis/élégants/surprenants), quitte à ce que ce soit lent ? Les trois cibles orientent vers des algos très différents.

> Réponse : on cherche à générer des puzzles plus intéressants, avec un "haha" moment ou avec des
> déductions élégantes de type "je ne sais pas directement l'étape suivante mais je sais quelle
> sera celle d'après". Un bon exemple est la combinaison de contraintes FM:112 et FM:122 qui implique
> par déduction FM:102

2. **Contrôle de la difficulté.** Tu veux pouvoir **cibler** une difficulté (« génère-moi un puzzle medium ») ou seulement garantir un **spectre varié** (et laisser le scoring trier après coup) ? Si on veut cibler, il faut un algo qui sait lâcher des candidates trop faciles / trop dures, pas juste les accepter parce qu'elles réduisent le ratio.

> Réponse : plutôt un cercle varié, on peut laisser le scoring trier après coup

3. **Esthétique / minimalisme.** Est-ce qu'un puzzle avec **peu de contraintes** (2–3) mais forçant du raisonnement fin est préférable à un puzzle avec **beaucoup de contraintes** (6–8) qui tombe par propagation ? Autrement dit, est-ce qu'on cherche l'**économie de moyens** ?

> Réponse : on veut éviter une ou deux contraintes qui vont résoudre tout le puzzle par propagation
> bête et méchante. C'est souvent le cas avec les FM:12 qui propagent fort ou bien la combinaison
> de FM:11 et FM:1.1. En tout cas ce qui est sûr c'est qu'on aimerait trouver plus de puzzles avec
> des utilisations plus pertinentes des contraintes de symétrie par exemple qui actuellement se
> résument très souvent à des groupes de taille 1. En particulier les symétries centrales.

4. **Rôle des cellules pré-remplies.** Le `readonly` / indice est-il (a) une **feature** assumée (variété visuelle, points d'ancrage pour le joueur débutant), (b) un **pis-aller** à minimiser (les puzzles les plus élégants sont ceux à grille vide), ou (c) quelque chose à **calibrer par niveau de difficulté** (beaucoup d'indices pour easy, aucun pour expert) ?

> Réponse : c'est bien de garder quelques cellules pré-remplies pour donner un point de départ. Par
> contre, je trouve que c'est plus intéressant d'avoir une contrainte GS:1 combinée avec une FM:121
> qui permet de déduire que la couleur du groupe doit être 1 car il sera entouré à droite et à gauche.
> Pour résumer, ce qui est sûr c'est qu'il faut un ou deux points de départ assez évidents pour tous
> les puzzles, même les plus difficiles. On ne veut pas laisser le joueur face à une page blanche
> pour laquelle il devra déduire par backtracking dès le début.

5. **Types de contraintes privilégiées.** Certaines contraintes (`FM`, `PA`, `DF`) sont « locales/techniques », d'autres (`SH`, `SY`, `GC`, `GS`) sont « structurelles/visuelles ». Y a-t-il un axe préféré, ou un équilibre visé entre les deux ?

> Réponse : pas de privilège mais probablement que les contraintes locales doivent servir plutôt à
> finaliser ou à résoudre une cellule isolée plutôt qu'à faire tout le puzzle

6. **Thématique / cohérence.** Est-il intéressant de générer des puzzles **mono-thème** (ex: un puzzle « pur FM », un puzzle « pur SH »), ou on veut toujours du multi-contraintes ?

> Réponse : oui, très intéresant d'avoir des puzzles mono-thème

7. **Taille du plateau.** Les dimensions cibles sont-elles plutôt petites (≤ 5×5), moyennes (6×8), ou est-ce qu'on veut scaler vers du 10×10+ ? Ça change drastiquement ce qui est calculable en temps raisonnable.

> Réponse : pour l'instant restons sur 10x10 comme maximum. Je pense que la moyenne devra tourner autour de 6x6 ou 6x8

8. **Budget algorithmique.** Est-ce qu'on s'autorise des techniques lourdes type **SAT solver**, **recherche locale** (simulated annealing, MCTS), **apprentissage** (scorer neuronal sur « puzzle joli »), ou on veut rester sur du Dart vanilla sans dépendance externe ?

> Réponse : idéalement rester sur du Dart vanilla mais tu peux me proposer d'autres approches

Les trois chapitres suivants décrivent chacun une approche alternative. Elles ne sont pas mutuellement exclusives : on peut imaginer un algo de production qui en combine plusieurs (ex: amorcer en thème-first, affiner par recherche locale, scorer avec la trace de résolution).

## 3. Approche A — Génération guidée par la trace de résolution

Idée-clé : au lieu de scorer chaque contrainte candidate par la **quantité** de cellules qu'elle déverrouille (métrique actuelle), on la score par la **qualité** du pas de raisonnement qu'elle offre au joueur. On pilote la génération par la **trajectoire de résolution** souhaitée.

### 3.1. Principe

1. **Instrumenter le solveur.** Chaque déduction produite par `solve()` est étiquetée par son « type » :
   - `P1` : propagation d'une seule contrainte, sur une cellule (ex: FM qui interdit une unique valeur ici).
   - `P2+` : propagation mono-contrainte en cascade (même contrainte qui débloque plusieurs cellules d'affilée à partir d'un état donné).
   - `C2` : combo inter-contraintes — la cellule n'est déductible que si deux contraintes sont considérées ensemble (ex: GS:1 + FM:121 ⇒ couleur forcée).
   - `M` : méta-inférence — une contrainte nouvelle se déduit de l'ensemble de contraintes existant, indépendamment de la grille (ex: FM:112 + FM:122 ⇒ FM:102 devient actif). À traiter comme une extension du solveur.
   - `F` : force / raisonnement par contradiction.
   - `B` : backtracking. Conservé ici comme étiquette historique : avec la convention « puzzle valide ⇔ déductif » désormais en vigueur, aucun puzzle publié n'atteint ce niveau — `B` reste utile pour disqualifier d'éventuelles régressions.

2. **Définir un score de trace.** Une trace de résolution est bonne si elle :
   - contient au moins 1–2 cellules déductibles en `P1` **au tout début** (points de départ),
   - contient une proportion significative de `C2` et idéalement quelques `M` (c'est là que vit l'aha-moment),
   - évite les longues cascades `P2+` issues d'une seule contrainte « foudroyante » (c'est le cas FM:12 que tu veux justement écarter),
   - ne nécessite pas de `B`, et tolère `F` en petit nombre vers la fin.

   Concrètement :
   ```
   score = +N_debut     * w_debut      (points de départ)
         + N_C2         * w_combo      (+++)
         + N_M          * w_meta       (++++ bonus aha)
         − N_cascade    * w_cascade    (pénalité propagation massive)
         − N_F          * w_force
         − ∞ si B
   ```

3. **Remplacer le critère de sélection de contrainte.** Au lieu de comparer `ratio_before` / `ratio_after`, on veut privilégier les contraintes qui améliorent la *qualité* de la trace, pas juste qui réduisent le ratio. **Attention : le score de trace n'est bien défini que sur une trace complète** (un puzzle uniquement résolvable). En cours de génération le puzzle est souvent multi-solution ; la section 8 détaille les stratégies pour contourner ce problème (filtre a posteriori, phase de polish, scoring partiel, lookahead).

4. **Partir d'un ensemble de contraintes déjà « garnissant ».** Le filtrage sur la trace a besoin d'un puzzle déjà à peu près déterminé pour évaluer la qualité — on peut amorcer avec l'algo glouton actuel, puis itérer des swaps pour remonter le score.

### 3.2. Avantages

- **Cible directement les aha-moments.** Le score `C2`/`M` est une définition opérationnelle de ce que tu cherches, pas une proxy.
- **Pénalise la propagation foudroyante.** Une FM:12 qui débloque 8 cellules d'un coup est détectée comme une cascade et pondérée négativement.
- **Réutilise l'infrastructure existante.** Solveur, énumération, registre de contraintes : rien à réécrire. L'instrumentation s'ajoute comme un flag dans `apply()`.
- **Score tunable.** Pour explorer (privilégier les traces riches), ou produire (privilégier les traces fiables) : mêmes briques, pondérations différentes.
- **Contribue au scoring a posteriori.** Le même score de trace peut servir à filtrer la collection générée et remplacer ou enrichir la complexité actuelle.

### 3.3. Inconvénients

- **Il faut étiqueter le solveur.** C2 est simple à détecter (on propage une contrainte à la fois et on regarde laquelle débloque quoi). M est plus coûteux : il demande de raisonner sur l'espace des contraintes (détecter que FM:112 + FM:122 ⇒ FM:102 revient à faire de la subsumption/implication entre contraintes, pas trivial).
- **La détection M est peut-être hors de portée** sans un mini-moteur d'inférence dédié. Première version : se contenter de P1/P2+/C2/F/B et traiter M comme un stretch goal.
- **Coût : chaque candidate exige une trace complète.** Plus lourd que l'algo actuel (qui demande juste deux `solve()`). À mitiger en limitant les candidates évaluées, ou en cachant les traces partielles.
- **Définir les poids est un sous-problème en soi.** Il faudra playtester pour calibrer (comme pour la formule de complexité).
- **Reste glouton localement.** Si on veut explorer largement, il faut le coupler avec la recherche locale (Approche C).

## 4. Approche B — Génération par thème / ossature de contraintes

Idée-clé : **inverser** l'approche actuelle. Au lieu de partir d'une grille et de chercher les contraintes qui vont avec, on part d'une **ossature de contraintes** choisie pour sa qualité (structurelle, thématique) et on cherche une grille qui la rend uniquement résoluble.

### 4.1. Principe

1. **Choisir un thème.** Quelques exemples :
   - *« Symétrie centrale »* : skeleton = `SY(central)` + éventuellement `GC` ou `GS`.
   - *« Pur FM »* : skeleton = 2–3 FM choisis pour leur interaction (typiquement deux FM dont la conjonction déduit un troisième motif — l'aha-moment FM:112 + FM:122 ⇒ FM:102).
   - *« Formes »* : skeleton = `SH(motif)` + `QA`.
   - *« Comptage »* : skeleton = `CC` + `GC`.

   Le thème peut être tiré aléatoirement ou imposé (mode « génère-moi un puzzle symétrie »).

2. **Générer une grille compatible avec le skeleton.** C'est l'étape clé et dépend du thème :
   - Pour `SY` : échantillonner parmi les grilles respectant la symétrie (on ne tire que la moitié de la grille, l'autre moitié est imposée). Ça garantit que SY « mord » sur autre chose que des groupes triviaux de taille 1.
   - Pour `SH` : reprendre la stratégie `_preFillSh` actuelle (déjà theme-first pour ce cas).
   - Pour les thèmes FM : contraindre la grille à contenir/exclure certains motifs dès le tirage (rejet ou placement dirigé).
   - Générique : backtracking sur les valeurs de cellules, en propageant le skeleton à chaque pas pour élaguer.

3. **Vérifier l'unicité.** Résoudre le puzzle (grille + skeleton seul). Trois cas :
   - **Unique** : parfait, on a un puzzle thématiquement pur.
   - **Multi-solution** : il manque de la contrainte. On ajoute **des contraintes locales minimales** (FM, DF) une à une pour tuer les solutions alternatives, en privilégiant celles qui ferment le plus de solutions par contrainte ajoutée. Si le skeleton est un SY, on évite d'ajouter une contrainte qui casse la symétrie ; si c'est un FM-duo, on refuse d'ajouter d'autres types.
   - **Insoluble sans pré-remplissage** : on ajoute 1–2 cellules readonly aux endroits « stratégiques » (ceux qui maximisent la propagation initiale, pour garantir les points de départ demandés).

4. **Filtrer par qualité.** Réutiliser le score de trace de l'Approche A pour ne garder que les puzzles où le skeleton porte réellement la résolution.

### 4.2. Avantages

- **Mono-thème natif.** C'est la raison d'être de l'approche. Un puzzle « pur SY » est un objectif bien défini.
- **Les contraintes structurelles portent le puzzle.** SY n'est plus un cache-sexe sur des groupes de taille 1 ; elle est l'axe de résolution par construction.
- **Évite les grilles banales.** La grille est tirée *conditionnellement* au thème (ex: symétrique), donc elle a de la structure.
- **Ergonomie pour le joueur.** Un puzzle mono-thème est plus « lisible » : le joueur comprend quelle règle il va devoir mobiliser, l'aha-moment est concentré.
- **Permet de résoudre le biais « symétries faibles ».** Directement adressé par les thèmes SY.

### 4.3. Inconvénients

- **Taux d'échec élevé sur certains thèmes.** Toutes les dimensions / skeletons ne permettent pas de puzzle unique. Il faut une stratégie de relance propre.
- **L'échantillonnage conditionnel est non-trivial pour certains skeletons.** SY et SH c'est OK ; « deux FM qui s'entre-déduisent » demande soit une énumération (faisable pour de petites tailles), soit de la chance pure.
- **Risque de dérive vers le multi-contraintes.** Si on doit ajouter trop de contraintes locales pour atteindre l'unicité, le thème se dilue. Besoin d'un seuil (« au max 2 contraintes locales additionnelles »).
- **Backtracking sur les valeurs de cellules.** Pour un skeleton générique, c'est l'équivalent d'un mini-solveur de CSP. Faisable en Dart vanilla à 10×10 max, pas au-delà.
- **Plus d'ingénierie.** Chaque thème demande sa propre stratégie d'amorce. Moins générique que l'algo actuel.

## 5. Approche C — Recherche locale sur (grille, ensemble de contraintes)

Idée-clé : traiter la génération comme un **problème d'optimisation** sur l'espace joint (grille, contraintes). On définit une fonction de qualité, on part d'une solution initiale (par ex. la sortie de l'algo actuel), et on itère des mutations en acceptant celles qui améliorent le score.

### 5.1. Principe

1. **Fonction de qualité Q(puzzle).** Agrège plusieurs critères :
   - **Unicité** : contrainte dure. `isDeductivelyUnique()` ou rejet.
   - **Points de départ** : `Q += 1` par cellule déductible par `P1` dans les premiers pas ; `Q -= ∞` si aucune.
   - **Qualité de trace** : score importé de l'Approche A (combos, méta, cascade, force).
   - **Parcimonie de contraintes** : `Q -= α * nb_contraintes` — pénalise les puzzles qui cumulent 7 contraintes pour rien.
   - **Parcimonie d'indices** : `Q -= β * nb_readonly` — préfère les grilles « vides ».
   - **Rôle des structurelles** : `Q += bonus` si au moins une SY/SH/GC participe à un C2 ; `Q -= malus` si elle n'est utilisée que pour un groupe trivial.

2. **État initial.** Plusieurs graines possibles :
   - Sortie de l'algo actuel (tiède : on améliore par raffinage).
   - Sortie de l'Approche B (mono-thème : on finalise).
   - Tirage totalement aléatoire (froid : converge plus lentement mais explore mieux).

3. **Mutations.** À chaque itération, tirer aléatoirement une action :
   - Retirer une contrainte.
   - Ajouter une contrainte de l'ensemble des candidates valides.
   - Remplacer une contrainte par une autre (swap).
   - Ajouter/retirer une cellule readonly.
   - Modifier légèrement la grille solution : flip d'une cellule + re-validation de toutes les contraintes existantes (celles qui cassent sont retirées).

4. **Critère d'acceptation.** Deux modes possibles :
   - **Hill-climbing** : accepter uniquement si `Q` augmente. Rapide, tombe en optimum local.
   - **Recuit simulé** (*simulated annealing*) : accepter parfois les mutations qui dégradent `Q`, avec une probabilité qui décroît dans le temps (température). Plus lent mais explore mieux. Reste implémentable en Dart vanilla (juste une boucle + un `exp()`).

5. **Arrêt.** Budget en nombre d'itérations, ou plateau de `Q` sur N itérations consécutives.

### 5.2. Avantages

- **Corrige le défaut glouton/sans-regret de l'algo actuel.** Mutation swap = retour arrière implicite.
- **Totalement tunable par Q.** Toutes les préférences (aha-moments, parcimonie, thème) s'expriment comme des termes dans la fonction de qualité.
- **Compatible avec tout le reste.** Peut être appliqué en post-processing à la sortie de A ou B.
- **Élimine naturellement les contraintes redondantes.** Une mutation qui retire une contrainte redondante ne baisse pas `Q` (le puzzle reste résoluble), elle peut même l'augmenter via la pénalité de parcimonie → elle est acceptée.
- **Permet l'exploration batch.** Plusieurs instances en parallèle avec des graines différentes → diversité.

### 5.3. Inconvénients

- **Calibrer Q est un exercice délicat.** Toute la qualité du résultat dépend des poids. Risque fort de « reward hacking » : l'algo trouve des puzzles qui maximisent Q sans être intéressants pour un humain.
- **Coût par itération élevé.** Chaque mutation demande un `solve()` complet (qui fait office de `isDeductivelyUnique()`). À 1000 itérations, ça monte vite.
- **Pas de garantie structurelle.** Contrairement à B, rien ne garantit un puzzle mono-thème ou piloté par SY — sauf à encoder ça dans Q, ce qui revient à B.
- **Dépend de l'état initial.** Un hill-climbing mal amorcé reste piégé ; le recuit simulé règle ça partiellement au prix du temps.
- **Ajoute un paramètre utilisateur caché.** Le budget d'itérations / la température initiale sont des knobs de plus à tuner.

## 6. Synthèse et pistes de combinaison

Mon intuition sur le match avec tes objectifs :

- **Approche A (trace)** répond directement à l'aha-moment et au problème de propagation foudroyante. Elle demande de l'instrumentation du solveur mais peu de refonte structurelle.
- **Approche B (thème)** est celle qui valorise le mieux les contraintes structurelles (SY, SH) et qui permet les puzzles mono-thème explicitement demandés.
- **Approche C (recherche locale)** est la plus générique mais aussi la plus dépendante d'une bonne fonction de qualité — elle est un bon **méta-algo** par-dessus A ou B.

Une implémentation pragmatique pourrait être : **B pour amorcer un squelette thématique, A pour scorer les candidates de complément, C pour raffiner en swapant les contraintes faibles**. Chaque brique est implémentable en Dart vanilla, et on peut commencer par instrumenter le solveur (travail commun aux trois) avant de choisir laquelle pousser en priorité.

## 7. Prototype du score de trace (Approche A, v1)

Première version implémentée et testée. Pas d'instrumentation du solveur nécessaire : `Puzzle.solveExplained()` renvoie déjà une liste de `SolveStep` étiquetés (méthode `propagation` / `force`, contrainte responsable).

### 7.1. Formule retenue

À partir de la trace, on calcule par puzzle :

| Métrique | Définition |
|---|---|
| `switch_ratio` | Fraction de transitions prop→prop où la contrainte change (récompense l'entrelacement, proxy du C2 / aha-chaîné). |
| `cascade_ratio` | Longueur max d'une cascade mono-contrainte ÷ nb total d'étapes de propagation (pénalise la contrainte foudroyante type FM:12). |
| `force_ratio` | Nb d'étapes force ÷ nb total d'étapes. |
| `diversity` | Contraintes ayant contribué au moins une fois ÷ contraintes totales du puzzle. |
| `start_ok` | 1 si au moins 1 étape de propagation précède la 1ʳᵉ force, 0 sinon (garantit un point de départ). |
| `needs_backtrack` | 1 si le puzzle n'est pas résolu par propagation+force → disqualification (score −100). Étiquette historique : avec la convention déductive, un puzzle qui passe `isDeductivelyUnique()` a forcément `needs_backtrack = 0`. |

Score combiné (v1, pondérations à calibrer) :

```
score = 40 · switch_ratio
      − 40 · cascade_ratio
      − 20 · force_ratio
      + 20 · diversity
      + 20 · start_ok
```

Implémentation : `bin/trace_score.dart` (fonction `scorePuzzle` + CLI d'analyse). ~55 ms par puzzle sur les tailles courantes (3x4–6x7), compatible avec un usage en boucle de sélection de contraintes pendant la génération.

### 7.2. Résultats sur un échantillon de `assets/default.txt`

200 puzzles tirés avec `seed=42`. Temps total : 11 s.

- Médiane 47.8, moyenne 43.6, max 75, min −3. Distribution quasi-gaussienne centrée sur 50.
- 4 % nécessitent backtracking (disqualifiés). Compatible avec l'observation que la majorité de la collection est résoluble en prop+force.
- Composantes moyennes : switch 0.51, cascade 0.27, force 0.13, diversity 0.93, start_ok 0.90.

**Tops (score ≥ 65)** : puzzles avec contraintes entrelacées, y compris un exemple contenant explicitement **FM:112** (l'aha-moment de référence). Le top #1 a `switches=7` sur 8 étapes, cascade_max = 1 (alternance stricte).

**Bottoms (score ≤ 10)** : exactement les pathologies attendues.
- `FM:12` qui propage 10 cellules sur 11 (cascade=9).
- `SH:222` qui fait 16 pas sur 19, les SY/GS ne servent à rien.
- `LT` trivial sur grilles presque résolues (1–2 étapes, trace trop courte pour exprimer un pattern).

Le score sépare donc proprement les puzzles « interessants » des cas « une contrainte fait tout ».

### 7.3. Validation sur données joueur : corrélation avec les ratings

Le fichier `stats/stats.txt` contient 1277 puzzles joués, annotés liked (`_L_`, 404), neutral (`___`, 858) ou disliked (`__D`, 15). Résultats (`bin/rating_correlation.dart`) :

| Rating | n | score moyen | médiane | cascade_ratio | switch_ratio |
|---|---|---|---|---|---|
| **Liked** | 404 | **48.9** | 50.7 | **0.22** | **0.59** |
| Neutral | 858 | 46.3 | 48.2 | 0.26 | 0.57 |
| **Disliked** | 15 | **34.7** | 33.1 | **0.47** | **0.38** |

**Delta liked − disliked = +14.2 points sur le score.** Signal clair malgré le petit échantillon disliked.

Distribution cumulative (fraction des puzzles dont le score ≥ seuil) :

| Seuil | Liked | Neutral | Disliked |
|---|---|---|---|
| ≥ 30 | 90 % | 85 % | **53 %** |
| ≥ 40 | 79 % | 70 % | **27 %** |
| ≥ 50 | 54 % | 45 % | **20 %** |

Un filtre simple « score ≥ 40 » garderait 79 % des liked et éliminerait 73 % des disliked — utile comme *garde-fou final* de la génération.

### 7.4. Enseignements pour la calibration

- **`cascade_ratio` est le meilleur signal en v1.** Écart × 2 entre liked (0.22) et disliked (0.47). Son poids (40) mériterait peut-être d'être augmenté, ou d'être utilisé comme *garde-fou dur* (disqualifier si > 0.5).
- **12 des 15 disliked sont dominés par FM:12 ou FM:21** avec une cascade max ≥ 8. Le diagnostic initial (« les FM fortes écrasent le puzzle ») est chiffré ; ces contraintes mériteraient un traitement particulier dans la génération (ex: les rendre disponibles seulement en post-finition, pas comme squelette).
- **Les liked ont plus d'étapes de force (2.18) que les disliked (1.47).** Contre-intuitif au départ, mais cohérent avec l'hypothèse que le joueur apprécie un peu de raisonnement par contradiction. La pénalité `force_ratio` (poids −20) est probablement trop forte et pourrait être réduite, voire retournée en récompense au-delà d'un seuil minimal.
- **Le score ne capture pas tout.** 3 disliked sur 15 ont un score ≥ 60 (trace propre, mais le joueur n'aime pas). Suggère des facteurs orthogonaux : taille de grille trop petite / trop grande, thématique peu lisible, ennui. Le score de trace est un composant nécessaire mais pas suffisant d'une fonction de qualité globale.
- **`start_ok` est déjà bon par construction** (90 % de la collection) ; peut rester un garde-fou binaire plutôt qu'un gros poids.
- **La disqualification par backtracking est rare et corrélée au rating** : 1.2 % des liked, 0.2 % des neutral, 0 % des disliked. Cohérent — les puzzles demandant du vrai backtracking sont rarement joués jusqu'à la notation.

### 7.5. Pistes v2

Classées par effort croissant :

1. **Ajuster les poids.** Augmenter le poids de `cascade_ratio` (ou en faire un garde-fou), réduire celui de `force_ratio`. Valider sur la même comparaison ratings.
2. **Disqualifier les cascades extrêmes.** Tout puzzle avec cascade ≥ `0.5 × prop_steps` est rejeté d'office. Empirique : élimine la plus grosse part des disliked.
3. **Seuil de longueur.** Les puzzles à trace ≤ 2 étapes (LT triviaux) sont trop courts pour être notés équitablement ; les exclure.
4. **Distinguer vraies C2 des switches fortuits.** Pour chaque prop step `n`, vérifier si la contrainte aurait pu fire à l'étape `n−1` (dans ce cas c'est un switch fortuit, pas une vraie chaîne). Demande une seconde passe du solveur mais c'est plus fidèle à l'intention initiale.
5. **Détection M (méta-inférence).** Stretch goal : détecter quand une contrainte nouvelle est logiquement impliquée par celles déjà posées, indépendamment de la grille. Coûteux, à ne tenter qu'après les étapes 1–4.

## 8. Utiliser le score de trace pour *générer* (pas juste noter)

Limite fondamentale : `solveExplained()` ne produit une trace complète et bien définie que sur un puzzle **uniquement résolvable** (prop + force suffisent). En cours de génération, le puzzle-en-construction a typiquement plusieurs solutions — la trace s'arrête dès que plus aucune déduction n'est possible, elle est *partielle*. On ne peut donc pas remplacer brutalement `ratio_before`/`ratio_after` par `score_before`/`score_after` : ces deux scores ne portent pas sur le même ensemble de cellules et ne sont pas comparables.

Voici quatre stratégies concrètes pour intégrer le score malgré ça, par effort croissant.

### 8.1. Stratégie 1 — Filtre post-génération (rejection sampling)

Le plus simple : on ne touche pas à l'algo glouton actuel. Chaque fois qu'il produit un puzzle, on calcule son score de trace complète, et on rejette sous un seuil (ex: score < 40, calibré sur l'analyse des ratings — seuil qui garde 79 % des liked et écarte 73 % des disliked).

**Avantages :** zéro refonte, implémentable en 10 lignes, validable immédiatement sur le batch `bin/generate.dart`.

**Inconvénients :** si la proportion de puzzles qui passent le filtre est faible, on fait tourner l'algo beaucoup plus longtemps pour le même rendement. À mesurer avant d'investir plus.

### 8.2. Stratégie 2 — Phase de *polish* après convergence

L'algo actuel s'arrête dès que `currentRatio == 0` (puzzle uniquement résolvable). Mais un puzzle « juste résolvable » peut être moche : une longue chaîne de force, une cascade FM:12 foudroyante. À ce point-là, **on a une trace complète** — donc le score est bien défini.

On ajoute alors une phase de polish :

```
tant que currentRatio == 0 et allConstraints.isNotEmpty et budget non épuisé :
    choisir une candidate C
    cloned = pu.clone() + C
    si cloned.isDeductivelyUnique() :
        si trace_score(cloned) > trace_score(pu) :
            pu.constraints.add(C)
    (sinon, on écarte C)
```

Inversement, on peut aussi tenter de *retirer* des contraintes qui ne participent pas aux étapes les plus élégantes, tant que l'unicité est préservée : ça nettoie les contraintes parasites que le glouton a cumulées.

**Avantages :** la trace est toujours complète en phase de polish → score bien défini. Agit sur le défaut « glouton sans regret » sans refonte. Se combine très bien avec le filtre S1.

**Inconvénients :** n'empêche pas l'algo d'avoir déjà pris une FM:12 dominante à l'étape 1 — les contraintes foudroyantes prises tôt sont difficiles à déboulonner après coup (elles suppriment le besoin des autres). Besoin de mécanismes de swap, pas juste d'ajout.

### 8.3. Stratégie 3 — Scoring sur trace partielle + terme de progression

Pendant la sélection gloutonne, pour chaque candidate C :

1. Cloner le puzzle, ajouter C, appeler `solveExplained` (qui peut s'arrêter partiellement).
2. Calculer :
   - `progress` = (cellules libres avant C) − (cellules libres après trace) ; proxy de « cette contrainte avance le puzzle ».
   - `partial_quality` = score de trace partielle — certaines métriques restent significatives sur partiel :
     - `cascade_ratio` : oui (la pire cascade observée est un mauvais signe quelle que soit la longueur totale).
     - `switch_ratio` : oui (entrelacement des contraintes utilisées, indépendant de la complétude).
     - `diversity` : oui (rapport contraintes utilisées / posées).
     - `force_ratio` / `start_ok` : oui mais biaisées par la troncature — à utiliser avec prudence.
3. Score combiné : `combined = α · progress + β · partial_quality`.
4. Prendre la candidate qui maximise `combined`.

**Avantages :** la qualité influence la sélection dès la première itération, pas seulement en polish. Détecte et écarte les contraintes qui feraient cascade dès le départ.

**Inconvénients :** le score partiel est plus bruité (moins d'observations). Les pondérations `α`, `β` sont un nouveau knob à calibrer. Plus coûteux : une trace par candidate, pas juste un `solve()`.

### 8.4. Stratégie 4 — Lookahead : scorer en complétant chaque candidate

Le plus rigoureux. Pour évaluer une candidate C, on ne se contente pas de regarder la trace partielle immédiate : on **continue l'algo glouton jusqu'au bout** à partir de `(puzzle + C)`, avec une heuristique simple pour les choix suivants, puis on score la **trace complète** du puzzle résultant.

Coût : O(candidates × profondeur_greedy × coût_solve). Rédhibitoire sans élagage, mais faisable si on :
- Limite le lookahead aux K meilleures candidates (par `ratio_after`, comme aujourd'hui).
- Mémoïse les traces partielles communes.
- N'applique le lookahead qu'aux premières itérations (les choix tôt sont ceux qui plombent le plus le reste).

**Avantages :** score toujours bien défini (trace complète). Vraie mesure de « cette contrainte mène à un bon puzzle ». Élimine les pièges gloutons.

**Inconvénients :** complexité algorithmique, perd le côté « léger » de la génération actuelle. À réserver pour un mode « qualité » batch, pas pour la génération à la demande dans l'app.

### 8.5. Recommandation

Ordre d'implémentation proposé :

1. **S1 d'abord** (filtre post-gen). Ça donne tout de suite un garde-fou chiffrable et mesure le coût du filtrage réel.
2. **S2 ensuite** (polish), en ajoutant swap+remove. C'est là que la majorité du gain qualité devrait venir sans trop de refonte.
3. **S3 si S1+S2 ne suffisent pas**, en particulier pour éviter les FM:12 prises tôt. Commencer par intégrer `cascade_ratio` comme *garde-fou dur* pendant la sélection (rejeter toute candidate qui crée une cascade ≥ 0.5 sur sa trace partielle) avant de passer à un score combiné pondéré.
4. **S4 en stretch goal**, seulement pour une génération batch « qualité » hors-ligne.

Le score de trace devient alors un composant utilisé à plusieurs endroits (pendant, après, en validation), pas juste une métrique de rating.
