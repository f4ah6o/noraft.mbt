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
        self.broadcast_append_entries(
          LogEntries::new(self.log.get_entries().last_position()),
        )
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
