import random
from .base import Constraint
from .parity import ParityConstraint
from .all_different import AllDifferentConstraint
from .motif import ForbiddenMotif, RequiredMotif
from .fixed import FixedValueConstraint
from .groups import GroupSize
from .lettergroup import LetterGroup
from .quantity import QuantityAllConstraint
from ..utils import to_rows, to_columns, to_grid


AVAILABLE_RULES = [
    # AllDifferentConstraint,
    # FixedValueConstraint,
    ParityConstraint,
    ForbiddenMotif,
    # RequiredMotif,
    GroupSize,
    LetterGroup,
    QuantityAllConstraint,
]
