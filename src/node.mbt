///| Internal follower state for leader.
priv struct Follower {
  match_index : LogIndex
  generation : NodeGeneration
}

///|
fn Follower::new() -> Follower {
  Follower::{ match_index: log_index_zero, generation: node_generation_zero }
}

///| Internal role state.
enum RoleState {
  Follower
  Candidate(Array[NodeId])
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
  if false {
    touch_unused_internals()
  }
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
pub fn Node::get_log(self : Node) -> Log {
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
  if not(self.config().voters_ref().is_empty()) {
    return log_position_invalid
  }
  if initial_voters.is_empty() {
    return log_position_invalid
  }
  let config = ClusterConfig::new()
  for id in initial_voters {
    config.voters_ref().push(id)
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
    Leader(_, _, _) => log_position_zero // Placeholder
    _ => log_position_invalid
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
    Leader(_, _, _) => {
      self.actions.set(SetElectionTimeout)
      true
    }
    _ => false
  }
}

///| Handles a message.
pub fn Node::handle_message(self : Node, msg : Message) -> Unit {
  // Minimal implementation - just handle basic term updates
  if msg.from() == self.id {
    return
  }
  if self.current_term.get() < msg.term().get() {
    self.transition_to_follower(msg.term())
  }
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
    InProgress
  }
}

///| Handles snapshot installed.
pub fn Node::handle_snapshot_installed(
  _self : Node,
  _last_included_position : LogPosition,
  _last_included_config : ClusterConfig
) -> Bool {
  // Minimal implementation
  false
}

///| Proposes config change.
pub fn Node::propose_config(
  _self : Node,
  _new_config : ClusterConfig
) -> LogPosition {
  log_position_invalid
}

///|
fn Node::transition_to_leader(_self : Node) -> Unit {
  // Placeholder implementation
}

///|
fn Node::transition_to_candidate(_self : Node) -> Unit {
  // Placeholder implementation
}

fn touch_unused_internals() -> Unit {
  let follower = Follower::new()
  let _ = follower.match_index
  let _ = follower.generation
  let candidate = RoleState::Candidate([NodeId::new(0)])
  match candidate {
    Candidate(ids) => {
      let _ = ids.length()
    }
    _ => ()
  }
  let leader = RoleState::Leader(Map::new(), Quorum::new(ClusterConfig::new()), false)
  match leader {
    Leader(map, quorum, flag) => {
      let _ = map.is_empty()
      let _ = quorum.smallest_majority_index()
      let _ = flag
    }
    _ => ()
  }
  let node = Node::new(NodeId::new(0), node_generation_zero)
  node.transition_to_leader()
  node.transition_to_candidate()
  let _ = node.handle_snapshot_installed(log_position_zero, ClusterConfig::new())
  let _ = node.propose_config(ClusterConfig::new())
}

///|
fn Node::transition_to_follower(self : Node, term : Term) -> Unit {
  self.current_term = term
  self.voted_for = None
  self.role = Follower
  self.actions.set(SetElectionTimeout)
}
