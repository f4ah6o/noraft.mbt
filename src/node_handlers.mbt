fn Node::handle_request_vote_call(
  self : Node,
  from : NodeId,
  term : Term,
  last_position : LogPosition
) -> Unit {
  if term.get() < self.current_term.get() {
    let reply = Message::request_vote_reply(self.current_term, self.id, false)
    self.actions.set(SendMessage(from, reply))
    return
  }
  if self.log.last_position().get_index().get() > last_position.get_index().get() {
    return
  }
  if self.voted_for is None {
    self.set_voted_for(Some(from))
  }
  if self.voted_for != Some(from) {
    return
  }
  let reply = Message::request_vote_reply(self.current_term, self.id, true)
  self.actions.set(SendMessage(from, reply))
  self.actions.set(SetElectionTimeout)
}

///|
fn Node::handle_request_vote_reply(
  self : Node,
  from : NodeId,
  term : Term,
  vote_granted : Bool
) -> Unit {
  match self.role {
    Candidate(granted_votes) => {
      if not(vote_granted) {
        return
      }
      if term.get() < self.current_term.get() {
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
  voters : @sorted_set.SortedSet[NodeId]
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
  entries : LogEntries
) -> Unit {
  if term.get() < self.current_term.get() {
    self.reply_append_entries(from)
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
    let next_commit_index =
      if leader_commit.get() < last_index.get() { leader_commit } else { last_index }
    if self.commit_index.get() < next_commit_index.get() {
      self.commit_index = next_commit_index
    }
  }
  self.reply_append_entries(from)
  self.actions.set(SetElectionTimeout)
}

///|
fn Node::handle_append_entries_reply(
  self : Node,
  from : NodeId,
  term : Term,
  generation : NodeGeneration,
  follower_last_position : LogPosition
) -> Unit {
  if term.get() < self.current_term.get() {
    return
  }
  match self.role {
    Leader(followers, quorum, solo_voter) => {
      let maybe_follower = followers.get(from)
      if maybe_follower is None {
        return
      }
      let follower = maybe_follower.unwrap()
      if generation.get() < follower.generation.get() ||
        (generation.get() == follower.generation.get() &&
          follower_last_position.get_index().get() < follower.match_index.get()) {
        return
      }
      let mut should_rebuild_quorum = false
      if generation.get() > follower.generation.get() {
        follower.generation = generation
        if follower_last_position.get_index().get() < follower.match_index.get() {
          follower.match_index = follower_last_position.get_index()
          should_rebuild_quorum = true
        }
      }
      followers[from] = follower
      if should_rebuild_quorum {
        let new_quorum = Node::rebuild_quorum_inner(
          quorum,
          followers,
          self.log.latest_config(),
          self.id,
          self.log.last_position().get_index(),
        )
        self.role = Leader(followers, new_quorum, solo_voter)
      }
      match self.role {
        Leader(followers2, quorum2, _) => {
          let follower = followers2.get(from).unwrap()
          if not(self.log.get_entries().contains(follower_last_position)) {
            match self.log.get_entries().get_term(follower_last_position.get_index()) {
              Some(t) => {
                let index = follower_last_position.get_index()
                let call = Message::append_entries_call(
                  self.current_term,
                  self.id,
                  self.commit_index,
                  LogEntries::new(LogPosition::new(t, index)),
                )
                self.actions.set(SendMessage(from, call))
              }
              None => {
                if self.log.last_position().get_index().get() <
                  follower_last_position.get_index().get() {
                  ()
                } else {
                  self.actions.set(InstallSnapshot(from))
                }
              }
            }
            return
          }
          let is_follower_up_to_date =
            follower_last_position.get_index().get() == self.log.last_position().get_index().get()
          if follower.match_index.get() < follower_last_position.get_index().get() {
            let old_match_index = follower.match_index
            follower.match_index = follower_last_position.get_index()
            quorum2.update_match_index(
              self.log.latest_config(),
              from,
              old_match_index,
              follower.match_index,
            )
            followers2[from] = follower
            if self.commit_index.get() < follower.match_index.get() {
              self.update_commit_index_if_possible()
            }
          }
          if is_follower_up_to_date {
            return
          }
          match self.log.get_entries().since(follower_last_position) {
            Some(delta) => {
              let call = Message::append_entries_call(
                self.current_term,
                self.id,
                self.commit_index,
                delta,
              )
              self.actions.set(SendMessage(from, call))
            }
            None => ()
          }
        }
        _ => ()
      }
    }
    _ => ()
  }
}

///|
fn Node::reply_append_entries(self : Node, to : NodeId) -> Unit {
  let reply = Message::append_entries_reply(
    self.current_term,
    self.id,
    self.generation,
    self.log.last_position(),
  )
  self.actions.set(SendMessage(to, reply))
}

///|
fn Node::is_valid_snapshot(
  self : Node,
  last_included_config : ClusterConfig,
  last_included_position : LogPosition
) -> Bool {
  if self.commit_index.get() < last_included_position.get_index().get() {
    return not(self.role().is_leader())
  }
  if not(self.log.get_entries().contains(last_included_position)) {
    return false
  }
  self.log.get_config(last_included_position.get_index()) == Some(last_included_config)
}
