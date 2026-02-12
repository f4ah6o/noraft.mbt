///|
fn Node::handle_request_vote_call(
  self : Node,
  from : NodeId,
  term : Term,
  last_position : LogPosition,
) -> Unit {
  if term < self.current_term {
    self.send_request_vote_reply(from, false)
    return
  }
  if self.log.last_position().get_index() > last_position.get_index() {
    return
  }
  if self.voted_for is None {
    self.set_voted_for(Some(from))
  }
  if self.voted_for != Some(from) {
    return
  }
  self.send_request_vote_reply(from, true)
  self.actions.set(SetElectionTimeout)
}

///|
fn Node::handle_request_vote_reply(
  self : Node,
  from : NodeId,
  term : Term,
  vote_granted : Bool,
) -> Unit {
  match self.role {
    Candidate(granted_votes) => {
      if not(vote_granted) {
        return
      }
      if term < self.current_term {
        return
      }
      granted_votes[from] = ()
      let config = self.log.latest_config()
      let n = count_granted_votes(granted_votes, config.voters)
      if n < config.voter_majority_count() {
        return
      }
      let n2 = count_granted_votes(granted_votes, config.new_voters)
      if n2 < config.new_voter_majority_count() {
        return
      }
      self.transition_to_leader()
    }
    _ => ()
  }
}

///|
fn count_granted_votes(
  granted_votes : Map[NodeId, Unit],
  voters : @sorted_set.SortedSet[NodeId],
) -> UInt64 {
  let mut count : UInt64 = 0
  for v in voters {
    if granted_votes.get(v) is Some(_) {
      count = count + 1
    }
  }
  count
}

///|
fn Node::handle_append_entries_call(
  self : Node,
  from : NodeId,
  term : Term,
  leader_commit : LogIndex,
  entries : LogEntries,
) -> Unit {
  if term < self.current_term {
    self.send_append_entries_reply(from)
    return
  }
  if not(self.role().is_follower()) {
    return
  }
  if self.voted_for is None {
    self.set_voted_for(Some(from))
  }
  if self.voted_for != Some(from) {
    return
  }
  let no_divergence = self.append_log_entries_from_leader(entries)
  if no_divergence {
    let last_index = self.log.last_position().get_index()
    let next_commit_index = if leader_commit < last_index {
      leader_commit
    } else {
      last_index
    }
    if self.commit_index < next_commit_index {
      self.commit_index = next_commit_index
    }
  }
  self.send_append_entries_reply(from)
  self.actions.set(SetElectionTimeout)
}

///|
fn Node::handle_append_entries_reply(
  self : Node,
  from : NodeId,
  term : Term,
  generation : NodeGeneration,
  follower_last_position : LogPosition,
) -> Unit {
  if term < self.current_term {
    return
  }
  match self.leader_state() {
    Some((followers, quorum, solo_voter)) => {
      let maybe_follower = resolve_follower_for_append_entries_reply(
        from, generation, follower_last_position, followers,
      )
      if maybe_follower is None {
        return
      }
      let follower = maybe_follower.unwrap()
      let should_rebuild_quorum = update_follower_for_append_entries_reply(
        follower, generation, follower_last_position,
      )
      followers[from] = follower
      self.maybe_rebuild_quorum_after_follower_update(
        followers, quorum, solo_voter, should_rebuild_quorum,
      )
      let is_follower_up_to_date = follower_last_position.get_index() ==
        self.log.last_position().get_index()
      self.advance_follower_match_index(from, follower_last_position)
      if is_follower_up_to_date {
        return
      }
      self.replicate_to_follower_if_needed(from, follower_last_position)
    }
    None => ()
  }
}

///|
fn resolve_follower_for_append_entries_reply(
  from : NodeId,
  generation : NodeGeneration,
  follower_last_position : LogPosition,
  followers : Map[NodeId, Follower],
) -> Follower? {
  let maybe_follower = followers.get(from)
  if maybe_follower is None {
    return None
  }
  let follower = maybe_follower.unwrap()
  if generation < follower.generation ||
    (
      generation == follower.generation &&
      follower_last_position.get_index() < follower.match_index
    ) {
    return None
  }
  Some(follower)
}

///|
fn update_follower_for_append_entries_reply(
  follower : Follower,
  generation : NodeGeneration,
  follower_last_position : LogPosition,
) -> Bool {
  let mut should_rebuild_quorum = false
  if generation > follower.generation {
    follower.generation = generation
    if follower_last_position.get_index() < follower.match_index {
      follower.match_index = follower_last_position.get_index()
      should_rebuild_quorum = true
    }
  }
  should_rebuild_quorum
}

///|
fn Node::maybe_rebuild_quorum_after_follower_update(
  self : Node,
  followers : Map[NodeId, Follower],
  quorum : Quorum,
  solo_voter : Bool,
  should_rebuild_quorum : Bool,
) -> Unit {
  if not(should_rebuild_quorum) {
    return
  }
  let new_quorum = Node::rebuild_quorum_inner(
    quorum,
    followers,
    self.log.latest_config(),
    self.id,
    self.log.last_position().get_index(),
  )
  self.role = Leader(followers, new_quorum, solo_voter)
}

///|
fn Node::repair_follower_gap(
  self : Node,
  from : NodeId,
  follower_last_position : LogPosition,
) -> Bool {
  if self.log.get_entries().contains(follower_last_position) {
    return false
  }
  match self.log.get_entries().get_term(follower_last_position.get_index()) {
    Some(t) => {
      let index = follower_last_position.get_index()
      self.send_append_entries(
        from,
        LogEntries::new(LogPosition::new(t, index)),
      )
    }
    None =>
      if self.log.last_position().get_index() <
        follower_last_position.get_index() {
        ()
      } else {
        self.actions.set(InstallSnapshot(from))
      }
  }
  true
}

///|
fn Node::advance_follower_match_index(
  self : Node,
  from : NodeId,
  follower_last_position : LogPosition,
) -> Unit {
  match self.leader_state() {
    Some((followers, quorum, _solo_voter)) => {
      let follower = followers.get(from).unwrap()
      if follower.match_index >= follower_last_position.get_index() {
        return
      }
      let old_match_index = follower.match_index
      follower.match_index = follower_last_position.get_index()
      quorum.update_match_index(
        self.log.latest_config(),
        from,
        old_match_index,
        follower.match_index,
      )
      followers[from] = follower
      if self.commit_index < follower.match_index {
        self.update_commit_index_if_possible()
      }
    }
    None => ()
  }
}

///|
fn Node::replicate_to_follower_if_needed(
  self : Node,
  from : NodeId,
  follower_last_position : LogPosition,
) -> Unit {
  if self.repair_follower_gap(from, follower_last_position) {
    return
  }
  match self.log.get_entries().since(follower_last_position) {
    Some(delta) => self.send_append_entries(from, delta)
    None => ()
  }
}

///|
fn Node::send_append_entries_reply(self : Node, to : NodeId) -> Unit {
  let reply = Message::append_entries_reply(
    self.current_term,
    self.id,
    self.generation,
    self.log.last_position(),
  )
  self.actions.set(SendMessage(to, reply))
}

///|
fn Node::send_request_vote_reply(
  self : Node,
  to : NodeId,
  vote_granted : Bool,
) -> Unit {
  let reply = Message::request_vote_reply(
    self.current_term,
    self.id,
    vote_granted,
  )
  self.actions.set(SendMessage(to, reply))
}

///|
fn Node::is_valid_snapshot(
  self : Node,
  last_included_config : ClusterConfig,
  last_included_position : LogPosition,
) -> Bool {
  if self.commit_index < last_included_position.get_index() {
    return not(self.role().is_leader())
  }
  if not(self.log.get_entries().contains(last_included_position)) {
    return false
  }
  self.log.get_config(last_included_position.get_index()) ==
  Some(last_included_config)
}
