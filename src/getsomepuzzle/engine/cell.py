class Cell:
    def __init__(self, domain):
        self.domain = domain
        self.options = domain[:]
        self.value = 0

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
