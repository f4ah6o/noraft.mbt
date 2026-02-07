test "PBT: Term next increments value" {
  @qc.quick_check_fn(fn(term : Term) {
    let next = term.next()
    next.get() == term.get() + 1
  })
}

test "PBT: LogIndex next increments value" {
  @qc.quick_check_fn(fn(index : LogIndex) {
    let next = index.next()
    next.get() == index.get() + 1
  })
}

test "PBT: LogPosition next preserves term and increments index" {
  @qc.quick_check_fn(fn(pos : LogPosition) {
    let next = pos.next()
    next.get_term() == pos.get_term() &&
    next.get_index().get() == pos.get_index().get() + 1
  })
}
