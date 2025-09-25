from .constants import EMPTY

class Cell:
    def __init__(self, domain):
        self.domain = domain
        self.options = domain[:]
        self.value = EMPTY

    def __repr__(self):
        symb = " " if self.value else "_"
        return "".join(
            map(
                str,
                [
                    (
                        v
                        if (v == self.value or (not self.value and v in self.options))
                        else symb
                    )
                    for v in self.domain
                ],
            )
        )

    def free(self):
        return not self.value and self.options

    def is_possible(self):
        return self.value or self.options

    def clone(self):
        c = Cell(self.domain)
        c.value = self.value
        c.options = self.options[:]
        return c

    def set_value(self, val):
        # Set the cell value if needed.
        # Return a boolean indicating if some change have been made.
        if self.value == val and self.options == []:
            return False
        self.value = val
        self.options = []
        return True

    def reset_value(self):
        self.value = EMPTY
        self.options = self.domain[:]
