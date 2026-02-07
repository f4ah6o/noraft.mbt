///| Internal follower state for leader.
priv struct Follower {
  mut match_index : LogIndex
  mut generation : NodeGeneration
}

///|
fn Follower::new() -> Follower {
  Follower::{ match_index: log_index_zero, generation: node_generation_zero }
}

///| Internal role state.
enum RoleState {
  Follower
  Candidate(Map[NodeId, Unit])
  Leader(Map[NodeId, Follower], Quorum, Bool)
}

///| Raft node.
pub struct Node {
  id : NodeId
  generation : NodeGeneration
  mut voted_for : NodeId?
  mut current_term : Term
  mut log : Log
  mut commit_index : LogIndex
  actions : Actions
  mut role : RoleState
}

///| Starts a new node.
pub fn Node::start(id : NodeId) -> Node {
  Node::new(id, node_generation_zero)
}

///| Restarts a node.
pub fn Node::restart(
  id : NodeId,
  generation : NodeGeneration,
  current_term : Term,
  voted_for : NodeId?,
  log : Log
) -> Node {
  let node = Node::new(id, generation)
  node.current_term = current_term
  node.voted_for = voted_for
  node.log = log
  node.commit_index = node.log.snapshot_position().get_index()
  node.actions.set(SetElectionTimeout)
  node
}

///|
fn Node::new(id : NodeId, generation : NodeGeneration) -> Node {
  let config = ClusterConfig::new()
  Node::{
    id,
    generation,
    voted_for: None,
    current_term: term_zero,
    log: Log::new(config, LogEntries::new(log_position_zero)),
    commit_index: log_index_zero,
    actions: Actions::new(),
    role: Follower,
  }
}

///| Returns the identifier of this node.
pub fn Node::id(self : Node) -> NodeId {
  self.id
}

///| Returns the generation of this node.
pub fn Node::generation(self : Node) -> NodeGeneration {
  self.generation
}

///| Returns the role of this node.
pub fn Node::role(self : Node) -> Role {
  match self.role {
    Follower => Role::Follower
    Candidate(_) => Role::Candidate
    Leader(_, _, _) => Role::Leader
  }
}

///| Returns the current term of this node.
pub fn Node::current_term(self : Node) -> Term {
  self.current_term
}

///| Returns the voted for node.
pub fn Node::voted_for(self : Node) -> NodeId? {
  self.voted_for
}

///| Returns the log.
pub fn Node::log(self : Node) -> Log {
  self.log
}

///| Returns the commit index.
pub fn Node::commit_index(self : Node) -> LogIndex {
  self.commit_index
}

///| Returns the config.
pub fn Node::config(self : Node) -> ClusterConfig {
  self.log.latest_config()
}

///| Returns peer node IDs.
pub fn Node::peers(self : Node) -> Array[NodeId] {
  let nodes = self.config().unique_nodes()
  nodes.filter(fn(id) { id != self.id })
}

///| Returns the actions.
pub fn Node::actions(self : Node) -> Actions {
  self.actions
}

///| Returns mutable actions.
pub fn Node::actions_mut(self : Node) -> Actions {
  self.actions
}

///| Creates a new cluster.
pub fn Node::create_cluster(
  self : Node,
  initial_voters : Array[NodeId]
) -> LogPosition {
  if self.log.last_position() != log_position_zero {
    return log_position_invalid
  }
  if not(self.config().voters.is_empty()) {
    return log_position_invalid
  }
  if initial_voters.is_empty() {
    return log_position_invalid
  }
  let config = ClusterConfig::new()
  for id in initial_voters {
    config.add_voter(id)
  }
  let entry = ClusterConfig(config)
  let entries = LogEntries::from_array(log_position_zero, [entry])
  self.actions.set(AppendLogEntries(entries))
  self.log.entries_mut().push(entry)
  self.transition_to_candidate()
  self.log.last_position()
}

///| Proposes a command.
pub fn Node::propose_command(self : Node) -> LogPosition {
  match self.role {
    Leader(_, _, _) => self.propose(Command)
    _ => log_position_invalid
  }
}

///| Proposes config change.
pub fn Node::propose_config(
  self : Node,
  new_config : ClusterConfig
) -> LogPosition {
  if not(self.role().is_leader()) {
    return log_position_invalid
  }
  if self.log.latest_config().voters != new_config.voters {
    return log_position_invalid
  }
  if not(sets_disjoint(new_config.voters, new_config.non_voters)) ||
    not(sets_disjoint(new_config.new_voters, new_config.non_voters)) {
    return log_position_invalid
  }
  if self.log.latest_config().is_joint_consensus() {
    return log_position_invalid
  }
  self.propose(ClusterConfig(new_config))
}

///| Gets commit status.
pub fn Node::get_commit_status(
  self : Node,
  position : LogPosition
) -> CommitStatus {
  if position.get_index().get() < self.log.get_entries().prev_position().get_index().get() {
    Unknown
  } else if position.get_index().get() <= self.commit_index.get() {
    if self.log.get_entries().contains(position) {
      Committed
    } else {
      Rejected
    }
  } else {
    match self.log.get_entries().get_term(self.commit_index) {
      Some(term) => if position.get_term().get() < term.get() { Rejected } else { InProgress }
      None => InProgress
    }
  }
}

///| Handles election timeout.
pub fn Node::handle_election_timeout(self : Node) -> Unit {
  match self.role {
    Follower => self.transition_to_candidate()
    Candidate(_) => self.transition_to_candidate()
    Leader(_, _, _) => { let _ = self.heartbeat() }
  }
}

///| Sends heartbeat.
pub fn Node::heartbeat(self : Node) -> Bool {
  match self.role {
    Leader(followers, _, _) => {
      if not(followers.is_empty()) {
        let call = Message::append_entries_call(
          self.current_term,
          self.id,
          self.commit_index,
          LogEntries::new(self.log.get_entries().last_position()),
        )
        self.actions.set(BroadcastMessage(call))
      }
      self.actions.set(SetElectionTimeout)
      true
    }
    _ => false
  }
}

///| Handles a message.
pub fn Node::handle_message(self : Node, msg : Message) -> Unit {
  if msg.from() == self.id {
    return
  }
  if self.current_term.get() < msg.term().get() {
    match msg {
      RequestVoteCall(from, _, _) =>
        match self.role {
          Candidate(_) => ()
          _ =>
            match self.voted_for {
              Some(id) => if id != from { return }
              None => ()
            }
        }
      _ => ()
    }
    self.transition_to_follower(msg.term())
  }
  match msg {
    RequestVoteCall(from, term, last_position) =>
      self.handle_request_vote_call(from, term, last_position)
    RequestVoteReply(from, term, vote_granted) =>
      self.handle_request_vote_reply(from, term, vote_granted)
    AppendEntriesCall(from, term, commit_index, entries) =>
      self.handle_append_entries_call(from, term, commit_index, entries)
    AppendEntriesReply(from, term, generation, last_position) =>
      self.handle_append_entries_reply(from, term, generation, last_position)
  }
}

///| Handles snapshot installed.
pub fn Node::handle_snapshot_installed(
  self : Node,
  last_included_position : LogPosition,
  last_included_config : ClusterConfig
) -> Bool {
  if not(self.is_valid_snapshot(last_included_config, last_included_position)) {
    return false
  }
  match self.log.get_entries().since(last_included_position) {
    Some(entries) => {
      self.log = Log::new(last_included_config, entries)
    }
    None => {
      self.log = Log::new(last_included_config, LogEntries::new(last_included_position))
    }
  }
  match self.actions.append_log_entries {
    Some(entries) => {
      entries.handle_snapshot_installed(last_included_position)
      if entries.is_empty() {
        self.actions.append_log_entries = None
      } else {
        self.actions.append_log_entries = Some(entries)
      }
    }
    None => ()
  }
  match self.actions.broadcast_message {
    Some(msg) => {
      self.actions.broadcast_message = Some(msg.handle_snapshot_installed(last_included_position))
    }
    None => ()
  }
  let keys = self.actions.send_messages.keys()
  for id in keys {
    let msg = self.actions.send_messages[id]
    self.actions.send_messages[id] =
      msg.handle_snapshot_installed(last_included_position)
  }
  true
}

///|
fn Node::transition_to_leader(self : Node) -> Unit {
  if self.voted_for != Some(self.id) {
    panic()
  }
  let quorum = Quorum::new(self.config())
  let followers = Map::new()
  let solo_voter =
    self.config().unique_voters().length() == 1 && self.config().voters.contains(self.id)
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
  let solo_voter =
    self.config().unique_voters().length() == 1 && self.config().voters.contains(self.id)
  if solo_voter {
    self.transition_to_leader()
    return
  }
  let granted_votes : Map[NodeId, Unit] = Map::new()
  granted_votes[self.id] = ()
  self.role = Candidate(granted_votes)
  self.actions.set(
    BroadcastMessage(
      Message::request_vote_call(self.current_term, self.id, self.log.last_position()),
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
  match self.role {
    Leader(followers, _, _) => {
      if not(followers.is_empty()) {
        let call = Message::append_entries_call(
          self.current_term,
          self.id,
          self.commit_index,
          LogEntries::from_array(old_last_position, [entry]),
        )
        self.actions.set(BroadcastMessage(call))
      }
    }
    _ => ()
  }
  self.actions.set(SetElectionTimeout)
  self.log.last_position()
}

///|
fn Node::rebuild_followers(self : Node) -> Unit {
  match self.role {
    Leader(followers, _, _) => {
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
    _ => ()
  }
}

///|
fn Node::rebuild_quorum(self : Node) -> Unit {
  match self.role {
    Leader(followers, _quorum, solo_voter) => {
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
    _ => ()
  }
}

///|
fn Node::rebuild_quorum_inner(
  _quorum : Quorum,
  followers : Map[NodeId, Follower],
  config : ClusterConfig,
  self_id : NodeId,
  self_last : LogIndex
) -> Quorum {
  let new_quorum = Quorum::new(config)
  new_quorum.update_match_index(config, self_id, log_index_zero, self_last)
  for id, follower in followers {
    new_quorum.update_match_index(config, id, log_index_zero, follower.match_index)
  }
  new_quorum
}

///|
fn Node::update_commit_index_if_possible(self : Node) -> Unit {
  match self.role {
    Leader(_, quorum, _) => {
      let new_commit_index = quorum.smallest_majority_index()
      if new_commit_index.get() <= self.commit_index.get() ||
        self.log.get_entries().get_term(new_commit_index) != Some(self.current_term) {
        return
      }
      self.commit_index = new_commit_index
      if new_commit_index.get() < self.log.latest_config_index().get() {
        return
      }
      if self.log.latest_config().is_joint_consensus() {
        self.finalize_joint_consensus()
      } else if not(self.log.latest_config().voters.contains(self.id)) {
        self.transition_to_follower(self.current_term)
      }
    }
    _ => ()
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
  match self.role {
    Leader(_, quorum, _) => {
      let old_last_index = self.log.last_position().get_index()
      self.actions.set(
        AppendLogEntries(
          LogEntries::from_array(self.log.last_position(), [entry]),
        ),
      )
      self.log.entries_mut().push(entry)
      quorum.update_match_index(
        self.log.latest_config(),
        self.id,
        old_last_index,
        self.log.last_position().get_index(),
      )
      match entry {
        ClusterConfig(_) => {
          self.rebuild_followers()
          self.rebuild_quorum()
        }
        _ => ()
      }
      match self.role {
        Leader(_, _, true) => self.update_commit_index_if_possible()
        _ => ()
      }
    }
    _ => ()
  }
}

///|
fn Node::append_log_entries_from_leader(
  self : Node,
  entries : LogEntries
) -> Bool {
  if self.log.get_entries().contains(entries.last_position()) {
    return self.log.last_position() == entries.last_position()
  }
  if not(self.log.get_entries().contains(entries.prev_position())) {
    if self.log.get_entries().contains_index(entries.prev_position().get_index()) {
      let snapshot_index = self.log.snapshot_position().get_index().get()
      let prev_index = entries.prev_position().get_index().get()
      if prev_index >= snapshot_index + 1 {
        let new_len = prev_index - (snapshot_index + 1)
        self.log.entries_mut().truncate(new_len)
      } else {
        self.log = Log::new(ClusterConfig::new(), LogEntries::new(log_position_zero))
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

///|
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
      let mut n : UInt64 = 0
      for v in config.voters {
        if granted_votes.get(v) is Some(_) {
          n = n + 1
        }
      }
      if n < config.voter_majority_count() {
        return
      }
      let mut n2 : UInt64 = 0
      for v in config.new_voters {
        if granted_votes.get(v) is Some(_) {
          n2 = n2 + 1
        }
      }
      if n2 < config.new_voter_majority_count() {
        return
      }
      self.transition_to_leader()
    }
    _ => ()
  }
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
