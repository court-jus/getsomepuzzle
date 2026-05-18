# Get Some Puzzles

Dans ce jeu, votre but est de colorer les cases d'une grille en noir ou blanc.

Pour savoir de quelle couleur chaque case doit être coloriée, vous devez suivre certaines contraintes (leurs règles sont expliquées plus bas).

Pour colorer les cases, cliquez dessus (ou touchez les sur mobile). Une fois pour noir, une deuxième fois pour blanc. Vous pouvez aussi faire glisser le doigt (ou la souris) sur plusieurs cases pour les peindre d'un seul geste.

Certaines cases sont déjà remplies et vous ne pouvez pas les modifier. Elles sont indiquées par une bordure plus épaisse.

Il n'y aura pas d'indication si vous faites une erreur mais une fois la grille complète, votre solution sera vérifiée. En cas de victoire, un autre puzzle sera automatiquement sélectionné. En cas d'erreur, la contrainte correspondante sera mise en évidence et vous pourrez modifier votre solution.

Si vous êtes bloqué, un bouton en haut à droite vous permet de recommencer.

Pendant que vous jouez, votre temps est enregistré (voir la section Stats ci-dessous). Le jeu peut être mis en pause si besoin.

Il y a environ 25000 puzzles fournis avec l'application. Ceux que vous avez déjà résolu n'apparaîtront plus. Vous pouvez voir votre progression sous le puzzle.

## Apprentissage

À votre premier lancement du jeu, une séquence d'apprentissage présente les contraintes une par une. Chaque nouvelle règle apparaît dans une petite fenêtre d'explication la première fois que vous la rencontrez, et le jeu vous propose ensuite des puzzles centrés sur cette règle jusqu'à ce que vous en ayez joué suffisamment (5 puzzles par défaut) pour passer à la suivante. Vous pouvez ignorer la séquence à tout moment avec le bouton "Ignorer l'apprentissage" dans la fenêtre d'explication, ou la redémarrer depuis le début dans la page Paramètres.

La page **Apprentissage**, accessible depuis le menu principal, liste toutes les contraintes avec leur description et la date à laquelle vous les avez rencontrées pour la première fois. Le bouton "Me rafraîchir la mémoire" à côté de chaque règle lance une courte playlist de puzzles centrés sur cette règle — pratique pour revoir une contrainte que vous n'avez pas vue depuis un moment.

## Contraintes

### Motif interdit

Si vous voyez un motif au dessus de la grille qui a un fond violet, vous devez remplir votre grille sans que ce motif n'apparaisse dans la grille.

### Contrainte de forme

Si vous voyez un motif au dessus de la grille qui a un fond bleu clair et qui est incliné à 45°, tous les groupes de cette couleur doivent avoir cette forme exacte (les rotations et symétries sont autorisées).

### Taille du groupe

Si une case contient un nombre, elle doit faire partie d'un groupe de cases de la même couleur, adjacentes orthogonalement et la taille de ce groupe doit correspondre au nombre.

### Parité

Si une case contient une flèche, il doit y avoir le même nombre de cases noires et de cases blanches devant la flèche. Si c'est une double flèche, cette règle vaut pour les deux côtés.

### Groupes de lettres

Les lettres identiques doivent faire partie du même groupe. Un groupe ne doit pas contenir de lettres différentes.

### Quantité

Un indice numérique sur fond bleu au dessus du puzzle indique que le nombre total de cases de cette couleur doit être égal à ce nombre.

### Symétrie (⟍, |, ⟋, ― et 🞋)

Lorsqu'une case contient l'un de ces symboles, le groupe dont elle fait partie (cases de la même couleur) doit respecter une symétrie le long de l'axe représenté.

La symétrie centrale (🞋) est équivalente à une rotation d'un demi-tour.

### Différent de (≠)

Lorsque deux cellules sont séparées par le symbole ≠, elles doivent être de couleurs différentes.

### Nombre par colonne

Un nombre dans un cercle au dessus d'une colonne indique combien de cellules de cette couleur doivent être dans cette colonne spécifique.

### Nombre par ligne

Un nombre dans un cercle à gauche d'une ligne indique combien de cellules de cette couleur doivent se trouver dans cette ligne. C'est le pendant horizontal du Nombre par colonne.

### Nombre de groupes

Un nombre dans un cadre avec une icône de lien indique combien de groupes (composantes connectées) de cette couleur doivent être dans la solution.

### Nombre de voisins

Une cellule marquée d'une petite croix contenant un nombre doit avoir exactement ce nombre de voisins orthogonaux de la couleur de la croix. La cellule elle-même n'est pas comptée — seules les quatre cellules directement au-dessus, en dessous, à gauche et à droite le sont.

### Yeux

Une case contenant un symbole d'œil doit « voir » exactement le nombre indiqué de cases de la couleur de l'œil. Une case voit en ligne droite dans chacune des quatre directions orthogonales jusqu'à atteindre le bord de la grille ou une case de la couleur opposée (qui bloque la vue). La couleur de l'œil est la couleur cible ; la bordure autour de l'œil est la couleur opposée.

## La page Ouvrir

La page Ouvrir est l'endroit où vous choisissez quoi jouer. En haut, le menu *Collection* liste les niveaux de difficulté (Facile → Fou), suivis de vos puzzles personnels et des playlists que vous avez créées. À côté, le bouton `+` crée une nouvelle playlist, le bouton fichier importe des puzzles depuis un fichier, et l'icône corbeille supprime la playlist en cours si elle vous appartient.

L'option *Mélanger* propose les puzzles dans un ordre aléatoire. En dessous, des filtres permettent d'affiner la liste : taille de la grille, contraintes que vous voulez voir ou éviter, et puzzles déjà joués ou passés. Le nombre affiché au-dessus du bouton Jouer indique combien de puzzles correspondent aux filtres actifs, et un petit bouton à côté de chaque filtre rétablit la valeur par défaut.

## Puzzles personnalisés

### Générer des puzzles

Ouvrez le menu et appuyez sur "Générer" pour fabriquer de nouveaux puzzles à la volée. Choisissez les dimensions de la grille, les types de contraintes à inclure ou exclure, une limite de temps par puzzle, et le nombre de puzzles à fabriquer. Choisissez la playlist de destination, puis appuyez sur "Générer" — la barre de progression montre combien ont déjà été faits. La génération tourne en arrière-plan ; vous pouvez l'arrêter à tout moment et garder ce qui a déjà été produit.

### Créer des puzzles

Ouvrez le menu et appuyez sur "Créer" pour concevoir votre propre puzzle. Choisissez les dimensions et appuyez sur "Démarrer" pour entrer dans l'éditeur. Touchez les cases pour les fixer en noir ou en blanc, et utilisez la barre supérieure pour ajouter des contraintes ; les cases à bordure verte se trouvent par raisonnement direct, celles à bordure orange par élimination. La barre inférieure affiche les dimensions, le nombre de contraintes et un score indicatif de difficulté. "Tester" vous laisse jouer le puzzle pour vérifier qu'il fonctionne, "Sauvegarder" l'enregistre dans la playlist choisie.

### Playlists

Les puzzles générés et créés sont sauvegardés dans des playlists. La playlist par défaut est "Mes puzzles", mais vous pouvez en créer de nouvelles depuis la page Ouvrir. Vous pouvez aussi importer des puzzles depuis un fichier.

## Astuces

Si vous êtes bloqué, le bouton d'astuce vous donne un coup de pouce progressif — chaque appui révèle un peu plus d'information. Dans le menu paramètres, vous pouvez choisir le type d'aide.

Le premier appui est le même quel que soit le mode :

- Si vous avez fait une erreur, il met en évidence la contrainte violée, ou la cellule fausse quand aucune contrainte ne le détecte directement.
- Si tout ce que vous avez rempli jusqu'ici est correct, il vous le confirme.

Les appuis suivants dépendent du mode choisi.

### Cellule déductible

Le mode par défaut. Après le diagnostic d'erreurs, les appuis suivants vous guident vers une déduction précise :

- Deuxième appui : met en évidence une case que vous pouvez déduire.
- Troisième appui : met aussi en évidence la contrainte qui justifie la déduction, avec une flèche reliant les deux.
- Quatrième appui : colorie la case à votre place.

Pratique quand vous voulez un petit indice sans tout vous gâcher : arrêtez-vous au deuxième appui si vous préférez trouver la justification par vous-même.

### Ajout de contrainte

Au lieu de désigner une case, le deuxième appui ajoute une nouvelle contrainte au puzzle. Cette règle est cohérente avec la solution et vous donne une information supplémentaire pour avancer — le puzzle devient plus simple sans qu'on vous dise quelle case remplir.

Après l'ajout d'une contrainte, le cycle reprend au diagnostic d'erreurs sur l'appui suivant.

## Paramètres

La page Paramètres règle la façon dont le jeu vérifie votre travail et vous aide.

**Langue** : choisissez la langue d'affichage (Anglais, Français ou Espagnol).

**Validation** : choisissez si la grille est vérifiée manuellement (vous appuyez sur un bouton) ou automatiquement (dès qu'elle est entièrement remplie).

**Vérification en direct** : comment les erreurs sont signalées pendant que vous jouez — toutes les cases fausses, juste le nombre d'erreurs, ou aucune indication jusqu'à ce que la grille soit complète.

**Afficher la notation** : si l'écran de notation apparaît entre les puzzles pour que vous puissiez aimer ou ne pas aimer ce que vous venez de jouer.

**Type d'astuce** : comment le bouton astuce vous aide — en pointant une case déductible ("Cellule déductible") ou en ajoutant une nouvelle contrainte qui simplifie le puzzle ("Ajout de contrainte"). Voir la section Astuces ci-dessus pour les détails.

**Délai d'inactivité** : si aucune interaction n'a lieu pendant le délai choisi (ou si l'application perd le focus), le chronomètre se met automatiquement en pause pour ne pas continuer à tourner pendant votre absence.

**Niveau du joueur** (0-100) : oriente les puzzles qui vous sont proposés vers votre vitesse de raisonnement. Plus c'est élevé, plus c'est difficile.

**Niveau automatique** : quand activé, votre niveau s'ajuste tout seul à partir de vos temps de résolution. Désactivez-le pour régler le niveau à la main.

**Rejouer l'onboarding** : redémarre la séquence d'introduction depuis la phase 0 — utile pour revoir les fenêtres de présentation des règles.

**Effacer les stats** : supprime les statistiques par puzzle stockées localement. L'action est irréversible et demande une confirmation.

## Stats

Le jeu enregistre le temps passé à résoudre un puzzle ainsi que le nombre d'erreurs. Ces données restent sur votre appareil — rien n'est collecté automatiquement. Si vous résolvez beaucoup de puzzles, je serai ravi que vous me les envoyiez : je m'en sers pour calculer la difficulté des puzzles.

Pour m'envoyer les stats, cliquez sur le choix correspondant dans le menu puis sur le bouton "Partager".

> Merci beaucoup.
