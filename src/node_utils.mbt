///|
fn sets_disjoint(
  a : @sorted_set.SortedSet[NodeId],
  b : @sorted_set.SortedSet[NodeId]
) -> Bool {
  for id in a {
    if b.contains(id) {
      return false
    }
  }
  true
}
