/// Shared majority target formula used by [MajorityConstraint],
/// [ColumnMajorityConstraint] and [RowMajorityConstraint].
///
/// Minimum cell count for the target colour to hold a strict majority
/// (more than any other individual colour) in a zone of [zoneSize] cells.
/// floor(zoneSize / 2) + 1 for domain 2, generalises to the same formula
/// for any domain where majority is defined as "strictly more than half".
int majorityTarget(int zoneSize) => (zoneSize ~/ 2) + 1;
