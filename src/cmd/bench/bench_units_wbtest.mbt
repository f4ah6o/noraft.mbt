///|
test "bench micros_to_secs converts units correctly" {
  assert_eq(micros_to_secs(1_000_000.0), 1.0)
  assert_eq(micros_to_secs(500.0), 0.0005)
}

///|
test "bench calc_ns_per_iter matches expected relation" {
  assert_eq(calc_ns_per_iter(0.001, 1000), 1000.0)
  assert_eq(calc_ns_per_iter(1.5, 0), 0.0)
  assert_eq(calc_ns_per_iter(1.5, -10), 0.0)
}
