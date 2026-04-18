# TODO: Group count constraint

New constraint type "Group Count" (slug GC).

Serialized as `GC:2.5` (slug:color.value), it means that the solution contains
"value" groups of color "color".

The example above means there are 5 white groups.

This constraint is represented in the top bar, with the ForbiddenMotif, Quantity, ...
widgets.

Visually, it contains a link icon (to represent the fact that the cells that form
the group are connected), and the numeric value, with a text color matching the
constraint's color.
