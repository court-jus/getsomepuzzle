# Get Some Puzzles

Dans ce jeu, votre but est de colorer les cases d'une grille en noir ou blanc.

Pour savoir de quelle couleur chaque case doit être coloriée, vous devez suivre certaines contraintes (leurs règles sont expliquées plus bas).

Pour colorer les cases, cliquez dessus (ou touchez les sur mobile). Une fois pour noir, une deuxième fois pour blanc.

Certaines cases sont déjà remplies et vous ne pouvez pas les modifier. Elles sont indiquées par une bordure plus épaisse.

Il n'y aura pas d'indication si vous faites une erreur mais une fois la grille complète, votre solution sera vérifiée. En cas de victoire, un autre puzzle sera automatiquement sélectionné. En cas d'erreur, la contrainte correspondante sera mise en évidence et vous pourrez modifier votre solution.

Si vous êtes bloqué, un bouton en haut à droite vous permet de recommencer.

Pendant que vous jouez, votre temps est enregistré (voir la section Stats ci-dessous). Le jeu peut être mis en pause si besoin.

Il y a environ 10000 puzzles fournis avec l'application. Ceux que vous avez déjà résolu n'apparaîtront plus. Vous pouvez voir votre progression sous le puzzle.

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

### Nombre de groupes

Un nombre dans un cadre avec une icône de lien indique combien de groupes (composantes connectées) de cette couleur doivent être dans la solution.

### Yeux

Une case contenant un symbole d'œil doit « voir » exactement le nombre indiqué de cases de la couleur de l'œil. Une case voit en ligne droite dans chacune des quatre directions orthogonales jusqu'à atteindre le bord de la grille ou une case de la couleur opposée (qui bloque la vue). La couleur de l'œil est la couleur cible ; la bordure autour de l'œil est la couleur opposée.

## Puzzles personnalisés

### Générer des puzzles

Ouvrez le menu et appuyez sur "Générer" pour accéder au générateur. Vous pouvez choisir la taille de la grille, les types de contraintes à inclure ou exclure, et le nombre de puzzles à générer. Vous pouvez également choisir dans quelle playlist les sauvegarder.

### Créer des puzzles

Ouvrez le menu et appuyez sur "Créer" pour concevoir votre propre puzzle. Vous pouvez définir les dimensions, fixer la couleur de certaines cases, ajouter des contraintes, et l'éditeur vous montrera en temps réel quelles cases sont déductibles. Les bordures vertes indiquent une déduction directe, les bordures oranges indiquent une déduction par élimination.

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

## Stats

Le jeu enregistre le temps passé à résoudre un puzzle ainsi que le nombre d'erreurs. Ces données ne sont pas collectés automatiquement mais j'apprécierai que vous me les envoyiez, j'ai l'intention de m'en servir pour calculer la difficulté des puzzles.

Le jeu envoie automatiquement s'il le peut l'identification des puzzles joués, ainsi que leur appréciation. Ces données sont complètement anonymes mais vous pouvez tout de même refuser leur envoi dans le menu paramètres.

Pour m'envoyer les stats, cliquez sur le choix correspondant dans le menu puis sur le bouton "Partager".

> Merci beaucoup.
