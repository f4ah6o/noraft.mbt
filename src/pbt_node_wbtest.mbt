///| PBT for Node.

test "PBT: Node::start initializes state" {
  @qc.quick_check(
    @qc.forall(gen_node_id(), fn(id) {
      let node = Node::start(id)
      node.id() == id &&
      node.current_term() == term_zero &&
      node.commit_index() == log_index_zero &&
      node.role().is_follower() &&
      node.voted_for() is None &&
      node.actions().is_empty()
    })
  )
}

test "PBT: Node::create_cluster rejects empty voters" {
  @qc.quick_check(
    @qc.forall(gen_node_id(), fn(id) {
      let node = Node::start(id)
      node.create_cluster([]) == log_position_invalid
    })
  )
}

test "PBT: Node::create_cluster emits append log entries" {
  @qc.quick_check(
    @qc.forall(@qc.tuple(gen_node_id(), gen_non_empty_array(6, gen_node_id())), fn(pair) {
      let (id, voters) = pair
      let node = Node::start(id)
      let pos = node.create_cluster(voters)
      let has_append =
        match node.actions().get_append_log_entries() {
          Some(_) => true
          None => false
        }
      not(pos.is_invalid()) && has_append
    })
  )
}

test "PBT: Node::handle_message ignores self messages" {
  @qc.quick_check(
    @qc.forall(gen_node_id(), fn(id) {
      let node = Node::start(id)
      let msg = Message::request_vote_call(term_zero, id, log_position_zero)
      let term_before = node.current_term()
      let role_before = node.role()
      node.handle_message(msg)
      node.current_term() == term_before && node.role() == role_before
    })
  )
}

test "PBT: Node::handle_message updates term on higher term" {
  @qc.quick_check(
    @qc.forall(gen_node_id(), fn(id) {
      let node = Node::start(id)
      @qc.forall(gen_node_id().such_that(fn(other) { other != id }), fn(other) {
        let higher = Term::new(1)
        let msg = Message::request_vote_reply(higher, other, true)
        node.handle_message(msg)
        node.current_term() == higher &&
        node.role().is_follower() &&
        node.voted_for() is None &&
        node.actions().get_set_election_timeout()
      })
    })
  )
}
