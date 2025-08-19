from ..engine.constraints.parity import ParityConstraint
from ..engine.constraints.motif import ForbiddenMotif

def draw_constraint(constraint, canvas):
    if isinstance(constraint, ForbiddenMotif):
        return draw_forbiddenmotif(constraint, canvas)


def draw_forbiddenmotif(constraint, canvas):
    motif = constraint.parameters["motif"]
    