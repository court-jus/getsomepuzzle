class CannotApplyConstraint(ValueError):
    pass


class MaxIterRandomRule(RuntimeError):
    pass


class TooEmpty(RuntimeError):
    pass


class RuleConflictError(ValueError):
    pass