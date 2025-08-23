import functools


@functools.total_ordering
class Constraint:
    def __init__(self, **parameters):
        self.parameters = parameters
        self.ui_widget = None

    def __repr__(self):
        return f"{self.__class__.__name__}({self.parameters})"

    def __eq__(self, other):
        # Two constraints are identical if they are of the same class
        # and the same parameters
        return type(self) == type(other) and self.parameters == other.parameters

    def __lt__(self, other):
        if type(self) != type(other):
            return type(self).__name__ < type(other).__name__
        if (
            "idx" in self.parameters
            and "idx" in other.parameters
            and self.parameters["idx"] != other.parameters["idx"]
        ):
            return self.parameters["idx"] < other.parameters["idx"]
        if (
            "val" in self.parameters
            and "val" in other.parameters
            and self.parameters["val"] != other.parameters["val"]
        ):
            return self.parameters["val"] < other.parameters["val"]
        return True

    def conflicts(self, _other):
        return False

    def check(self, puzzle, debug=False):
        raise NotImplementedError("Should be implemented by subclass")

    def line_export(self):
        raise NotImplementedError("Should be implemented by subclass")

    def line_import(self):
        raise NotImplementedError("Should be implemented by subclass")


class CellCentricConstraint(Constraint):

    def check(self, puzzle, debug=False):
        result = self._check(puzzle, debug)
        if self.ui_widget is not None:
            self.ui_widget.color = "green" if result else "red"
        return result

    def conflicts(self, other):
        if not isinstance(other, CellCentricConstraint):
            return False

        return self.parameters["idx"] == other.parameters["idx"]
