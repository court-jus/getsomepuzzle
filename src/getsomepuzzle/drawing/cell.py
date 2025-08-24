import toga

from ..engine import constants


def draw_cell(canvas, cell, cell_constraint):
    value = cell.value if cell.value else None
    readonly = value is not None
    context = canvas.context

    with context.Stroke(
        color="gray" if readonly else "darkgray", line_width=4
    ) as stroke:
        stroke.rect(
            x=2,
            y=2,
            width=canvas.width - 4,
            height=canvas.height - 4,
        )
    bgcolor = constants.VALUE_BGCOLORS[cell.value]
    with context.Fill(color=bgcolor) as fill:
        fill.rect(
            x=4,
            y=4,
            width=canvas.width - 8,
            height=canvas.height - 8,
        )
    if not cell_constraint:
        return
    cell_font = toga.Font("sans-serif", constants.FONT_SIZE)
    constraint_text = cell_constraint["text"]
    tw, th = canvas.measure_text(constraint_text, cell_font)
    fgcolor = constants.CONSTRAST[bgcolor]
    with context.Fill(color=fgcolor) as fill:
        x = int((canvas.width - tw) / 2)
        y = int(canvas.height / 2)
        fill.write_text(
            constraint_text,
            x=x, y=y,
            baseline=toga.constants.Baseline.MIDDLE,
            font=cell_font,
        )