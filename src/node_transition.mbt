///|
fn Node::transition_to_leader(self : Node) -> Unit {
  if self.voted_for != Some(self.id) {
    panic()
  }
  let quorum = Quorum::new(self.config())
  let followers = Map::new()
  let solo_voter = self.config().unique_voters().length() == 1 &&
    self.config().voters.contains(self.id)
  self.role = Leader(followers, quorum, solo_voter)
  self.rebuild_followers()
  self.rebuild_quorum()
  let _ = self.propose(Term(self.current_term))
}

///|
fn Node::transition_to_candidate(self : Node) -> Unit {
  if not(self.log.latest_config().is_voter(self.id)) {
    return
  }
  self.set_current_term(self.current_term.next())
  self.set_voted_for(Some(self.id))
  let solo_voter = self.config().unique_voters().length() == 1 &&
    self.config().voters.contains(self.id)
  if solo_voter {
    self.transition_to_leader()
    return
  }
  let granted_votes : Map[NodeId, Unit] = Map::new()
  granted_votes[self.id] = ()
  self.role = Candidate(granted_votes)
  self.actions.set(
    BroadcastMessage(
      Message::request_vote_call(
        self.current_term,
        self.id,
        self.log.last_position(),
      ),
    ),
  )
  self.actions.set(SetElectionTimeout)
}

///|
fn Node::transition_to_follower(self : Node, term : Term) -> Unit {
  self.set_current_term(term)
  self.set_voted_for(None)
  self.role = Follower
  self.actions.set(SetElectionTimeout)
}

///|
fn Node::propose(self : Node, entry : LogEntry) -> LogPosition {
  let old_last_position = self.log.last_position()
  self.append_proposed_log_entry(entry)
  match self.leader_state() {
    Some((followers, _quorum, _solo_voter)) =>
      if not(followers.is_empty()) {
        self.broadcast_append_entries(
          LogEntries::from_entry(old_last_position, entry),
        )
      }
    None => ()
  }
  self.actions.set(SetElectionTimeout)
  self.log.last_position()
}

///|
fn Node::rebuild_followers(self : Node) -> Unit {
  match self.leader_state() {
    Some((followers, _quorum, _solo_voter)) => {
      let config = self.log.latest_config()
      for id in config.unique_nodes() {
        if id == self.id || followers.get(id) is Some(_) {
          continue
        }
        followers[id] = Follower::new()
      }
      let remove_ids = []
      for id, _ in followers {
        if not(config.contains(id)) {
          remove_ids.push(id)
        }
      }
      for id in remove_ids {
        followers.remove(id)
      }
    }
    None => ()
  }
}

///|
fn Node::rebuild_quorum(self : Node) -> Unit {
  match self.leader_state() {
    Some((followers, _quorum, solo_voter)) => {
      let config = self.log.latest_config()
      let new_quorum = Node::rebuild_quorum_inner(
        Quorum::new(config),
        followers,
        config,
        self.id,
        self.log.last_position().get_index(),
      )
      self.role = Leader(followers, new_quorum, solo_voter)
    }
    None => ()
  }
}

///|
fn Node::rebuild_quorum_inner(
  _quorum : Quorum,
  followers : Map[NodeId, Follower],
  config : ClusterConfig,
  self_id : NodeId,
  self_last : LogIndex,
) -> Quorum {
  let new_quorum = Quorum::new(config)
  new_quorum.update_match_index(config, self_id, log_index_zero, self_last)
  for id, follower in followers {
    new_quorum.update_match_index(
      config,
      id,
      log_index_zero,
      follower.match_index,
    )
  }
  new_quorum
}

///|
fn Node::update_commit_index_if_possible(self : Node) -> Unit {
  match self.leader_state() {
    Some((_followers, quorum, solo_voter)) => {
      let new_commit_index = if solo_voter {
        self.log.last_position().get_index()
      } else {
        quorum.smallest_majority_index()
      }
      if new_commit_index <= self.commit_index ||
        self.log.get_entries().get_term(new_commit_index) !=
        Some(self.current_term) {
        return
      }
      self.commit_index = new_commit_index
      if new_commit_index < self.log.latest_config_index() {
        return
      }
      if self.log.latest_config().is_joint_consensus() {
        self.finalize_joint_consensus()
      } else if not(self.log.latest_config().voters.contains(self.id)) {
        self.transition_to_follower(self.current_term)
      }
    }
    None => ()
  }
}

///|
fn Node::finalize_joint_consensus(self : Node) -> Unit {
  let current = self.log.latest_config()
  let new_config = ClusterConfig::{
    voters: current.new_voters.copy(),
    new_voters: @sorted_set.SortedSet::new(),
    non_voters: current.non_voters.copy(),
  }
  let _ = self.propose(ClusterConfig(new_config))
}

///|
fn Node::append_proposed_log_entry(self : Node, entry : LogEntry) -> Unit {
  match self.leader_state() {
    Some((_followers, quorum, solo_voter)) => {
      let prev_position = self.log.last_position()
      let old_last_index = prev_position.get_index()
      self.actions.set(AppendSingleLogEntry(prev_position, entry))
      self.log.entries_mut().push(entry)
      let new_last_index = self.log.last_position().get_index()
      quorum.update_match_index(
        self.log.latest_config(),
        self.id,
        old_last_index,
        new_last_index,
      )
      let mut is_cluster_config = false
      match entry {
        ClusterConfig(_) => {
          is_cluster_config = true
          self.rebuild_followers()
          self.rebuild_quorum()
        }
        _ => ()
      }
      if solo_voter {
        if self.commit_index < new_last_index {
          self.commit_index = new_last_index
        }
        if is_cluster_config {
          if self.log.latest_config().is_joint_consensus() {
            self.finalize_joint_consensus()
          } else if not(self.log.latest_config().voters.contains(self.id)) {
            self.transition_to_follower(self.current_term)
          }
        }
      }
    }
    None => ()
  }
}

///|
fn Node::leader_state(self : Node) -> (Map[NodeId, Follower], Quorum, Bool)? {
  match self.role {
    Leader(followers, quorum, solo_voter) =>
      Some((followers, quorum, solo_voter))
    _ => None
  }
}

///|
fn Node::append_log_entries_from_leader(
  self : Node,
  entries : LogEntries,
) -> Bool {
  if self.log.get_entries().contains(entries.last_position()) {
    return self.log.last_position() == entries.last_position()
  }
  if not(self.log.get_entries().contains(entries.prev_position())) {
    if self.log
      .get_entries()
      .contains_index(entries.prev_position().get_index()) {
      let snapshot_index = self.log.snapshot_position().get_index().get()
      let prev_index = entries.prev_position().get_index().get()
      if prev_index >= snapshot_index + 1 {
        let new_len = prev_index - (snapshot_index + 1)
        self.log.entries_mut().truncate(new_len)
      } else {
        self.log = Log::new(
          ClusterConfig::new(),
          LogEntries::new(log_position_zero),
        )
      }
    }
    return false
  }
  let delta = entries.strip_common_prefix(self.log.get_entries())
  self.log.entries_mut().append(delta)
  self.actions.set(AppendLogEntries(delta))
  true
}

///|
fn Node::set_current_term(self : Node, term : Term) -> Unit {
  self.current_term = term
  self.actions.set(SaveCurrentTerm)
}

///|
fn Node::set_voted_for(self : Node, voted_for : NodeId?) -> Unit {
  self.voted_for = voted_for
  self.actions.set(SaveVotedFor)
}
