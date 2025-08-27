import toga

from ..engine import constants


def draw_cell(canvas, cell, cell_constraint, readonly, user_note):
    context = canvas.context

    with context.Stroke(
        color="darkgray", line_width=4
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
    if readonly:
        with context.Stroke(
            color="gray", line_width=2
        ) as stroke:
            stroke.rect(
                x=6,
                y=6,
                width=canvas.width - 12,
                height=canvas.height - 12,
            )
    if user_note:
        cell_font = toga.Font("sans-serif", 12)
        tw, th = canvas.measure_text(user_note, cell_font)
        fgcolor = constants.CONSTRAST[bgcolor]
        with context.Fill(color=fgcolor) as fill:
            fill.write_text(
                user_note,
                x=4, y=4,
                baseline=toga.constants.Baseline.TOP,
                font=cell_font,
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