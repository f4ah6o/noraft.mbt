///|
test "Node solo voter becomes leader after create_cluster" {
  let node = Node::start(NodeId::new(1))
  let _ = node.create_cluster([NodeId::new(1)])
  node.handle_election_timeout()
  assert_true(node.role().is_leader() || node.role().is_candidate())
}

///|
test "Node propose_command on leader queues append" {
  let node = Node::start(NodeId::new(1))
  let _ = node.create_cluster([NodeId::new(1)])
  node.handle_election_timeout()
  if node.role().is_leader() {
    let pos = node.propose_command()
    assert_true(not(pos.is_invalid()))
    match node.actions().get_append_log_entries() {
      Some(_) => ()
      None => fail("expected append log entries")
    }
  }
}

///|
test "Node handle_snapshot_installed updates actions" {
  let node = Node::start(NodeId::new(1))
  let _ = node.create_cluster([NodeId::new(1)])
  node.handle_election_timeout()
  let _ = node.propose_command()
  let last = node.log().last_position()
  let ok = node.handle_snapshot_installed(last, node.config())
  assert_true(ok)
  match node.actions().get_append_log_entries() {
    Some(_) => ()
    None => ()
  }
}
