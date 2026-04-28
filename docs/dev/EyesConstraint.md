# Eyes

This constraint indicates is inside a cell and indicates that this cells "sees" a
given number of cells of a given color.

Seeing a cell means that there is a direct line of sight of same colored cells in
any number of directions around the cell.

It is represented by an "eye" symbol that contains the number of cells seen. The
color of the eye matches the target color. The eye is bordered with the opposite
color.

## Examples

### Example 1

```
1 2 1
1 2 1
X 1 2
```

The "X" cell sees no cell of color "2" and 3 cells of color "1".

### Example 2

```
1 1 1 1
2 2 1 1
1 2 1 2
X 2 2 2
```

The "X" cell sees 3 cells of color "2" and 1 cell of color "1".

### Example 3

```
1 1 1 1
2 2 1 1
1 2 X 2
1 2 2 2
```

The "X" cell sees 3 cells of color "2" and 2 cells of color "1".