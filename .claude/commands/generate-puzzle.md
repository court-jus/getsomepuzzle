# Generate a puzzle

Generate a puzzle using the Python engine in `src/getsomepuzzle/engine/`.

## Arguments
- $ARGUMENTS: size specification in WxH format (e.g. "5x6"), optionally followed by ratio (e.g. "5x6 0.9")

## Instructions

Parse $ARGUMENTS to extract:
- **width** and **height** from the WxH format (e.g. "5x6" means width=5, height=6)
- **ratio** (optional, default 0.85): float between 0.0 and 1.0 controlling how many cells are pre-filled (higher = fewer pre-filled = harder)

Then run the Python generation script from the `src/` directory. The generation uses `buildapuzzle()` from `getsomepuzzle.engine.generate`.

Run this command (adjust width, height, ratio from parsed arguments):

```bash
cd /home/debian/perso/getsomepuzzle/src && python3 -c "
import random
from getsomepuzzle.engine.generate import buildapuzzle
from getsomepuzzle.engine.utils import line_export

width = {WIDTH}
height = {HEIGHT}
ratio = {RATIO}

max_attempts = 10
for attempt in range(max_attempts):
    pu = buildapuzzle(width, height, ratio, verbose=True, progress=False)
    if pu is not None:
        line = line_export(pu)
        print()
        print('=== GENERATED PUZZLE ===')
        print(line)
        print()
        print(f'Size: {width}x{height}')
        print(f'Constraints: {len(pu.constraints)}')
        for c in pu.constraints:
            print(f'  - {c}')
        break
else:
    print('Failed to generate a puzzle after', max_attempts, 'attempts.')
    print('Try again or use a different size/ratio.')
"
```

Replace `{WIDTH}`, `{HEIGHT}`, and `{RATIO}` with the parsed values.

After the puzzle is generated, display:
1. The puzzle line representation (the `v2_...` string)
2. The grid dimensions
3. The list of constraints

If the user wants to add it to the game, append the line to `assets/default.txt` or a new file.

### Default sizes reference
- Small: 3x3, 4x4
- Medium: 4x5, 5x5, 4x6
- Large: 5x6, 6x6, 5x7
- Extra large: 6x7, 7x7, 6x8, 7x8

### Ratio reference
- Easy (more pre-filled): 0.7 - 0.8
- Medium: 0.8 - 0.9
- Hard (fewer pre-filled): 0.9 - 1.0
