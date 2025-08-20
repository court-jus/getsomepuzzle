import toga

from ..engine.constraints.parity import ParityConstraint
from ..engine.constraints.motif import ForbiddenMotif
from ..engine import constants


def draw_constraint(constraint, canvas):
    if isinstance(constraint, ForbiddenMotif):
        return draw_forbiddenmotif(constraint, canvas)


def draw_forbiddenmotif(constraint, canvas):
    motif = constraint.parameters["motif"]
    context = canvas.context
    square_size = 10
    motif_width = max(len(row) for row in motif) * square_size
    motif_height = len(motif) * square_size
    rectangles = {}
    for ridx, row in enumerate(motif):
        for cidx, val in enumerate(row):
            ival = int(val)
            rectangles.setdefault(ival, []).append(
                {"x": cidx * square_size, "y": ridx * square_size}
            )
    left_margin = int((canvas.width - motif_width) / 2)
    top_margin = int((canvas.height - motif_height) / 2)
    for val, data in rectangles.items():
        bgcolor = constants.VALUE_BGCOLORS[val]
        fgcolor = "gray"
        with context.Fill(color=bgcolor) as fill:
            for item in data:
                rect = fill.rect(
                    x=item["x"] + left_margin,
                    y=item["y"] + top_margin,
                    width=square_size,
                    height=square_size,
                )
        with context.Stroke(color=fgcolor, line_width=1) as stroke:
            for item in data:
                rect = stroke.rect(
                    x=item["x"] + left_margin,
                    y=item["y"] + top_margin,
                    width=square_size,
                    height=square_size,
                )
