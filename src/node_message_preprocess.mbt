///|
fn Node::can_step_down_for_message(self : Node, msg : Message) -> Bool {
  match msg {
    RequestVoteCall(from, _, _) =>
      match self.role {
        Candidate(_) => true
        _ =>
          match self.voted_for {
            Some(id) => id == from
            None => true
          }
      }
    _ => true
  }
}

///|
fn Node::maybe_step_down_for_message(self : Node, msg : Message) -> Bool {
  if self.current_term >= msg.term() {
    return true
  }
  if not(self.can_step_down_for_message(msg)) {
    return false
  }
  self.transition_to_follower(msg.term())
  true
}
