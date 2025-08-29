class Cell {
  int value = 0;
  List<int> domain = [];
  List<int> options = [];
  bool readonly = false;

  Cell(this.value, this.domain, this.readonly) {
    options = domain.toList();
  }

  int setValue(int newValue) {
    if (readonly) return value;
    value = newValue;
    return value;
  }
}
