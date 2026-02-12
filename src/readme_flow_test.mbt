///|
test "README flow: create cluster and propose command" {
  // Start a node.
  let node = Node::start(NodeId::new(0))

  // Create a single-node cluster.
  let commit_position = node.create_cluster([NodeId::new(0)])
  assert_true(not(commit_position.is_invalid()))

  // Execute pending actions (simulate user-side I/O handling).
  let mut saw_append = false
  for action in node.actions_mut().to_array() {
    match action {
      AppendLogEntries(_) => saw_append = true
      AppendSingleLogEntry(_, _) => saw_append = true
      _ => ()
    }
  }
  assert_true(saw_append)

  // If still in progress, drive election timeout once.
  if node.get_commit_status(commit_position).is_in_progress() {
    node.handle_election_timeout()
  }
  assert_true(node.get_commit_status(commit_position).is_committed())

  // Propose a command once leader.
  if node.role().is_leader() {
    let pos = node.propose_command()
    assert_true(not(pos.is_invalid()))
  }
}
