///| `Action` represents the I/O operations for `Node` that users need to execute.
pub enum Action {
  /// Set an election timeout.
  SetElectionTimeout
  /// Save the current term to persistent storage.
  SaveCurrentTerm
  /// Save the voted-for node ID to persistent storage.
  SaveVotedFor
  /// Broadcast a message to all other nodes.
  BroadcastMessage(Message)
  /// Append log entries to the node-local log on persistent storage.
  AppendLogEntries(LogEntries)
  /// Send a message to a specific node.
  SendMessage(NodeId, Message)
  /// Install a snapshot on a specific node.
  InstallSnapshot(NodeId)
}

///| `Actions` represents a prioritized set of `Action`s that are issued by a `Node` but have not yet been executed.
///
/// Fields of `Actions` are prioritized, and actions are generally executed in the order of these fields.
pub struct Actions {
  /// If `true`, `Action::SetElectionTimeout` needs to be executed.
  mut set_election_timeout : Bool
  /// If `true`, `Action::SaveCurrentTerm` needs to be executed.
  mut save_current_term : Bool
  /// If `true`, `Action::SaveVotedFor` needs to be executed.
  mut save_voted_for : Bool
  /// If `Some`, `Action::BroadcastMessage` needs to be executed.
  mut broadcast_message : Message?
  /// If `Some`, `Action::AppendLogEntries` needs to be executed.
  mut append_log_entries : LogEntries?
  /// If there is an entry for a node, `Action::SendMessage` for the node needs to be executed.
  send_messages : Map[NodeId, Message]
  /// If there is an entry for a node, `Action::InstallSnapshot` for the node needs to be executed.
  install_snapshots : Array[NodeId]
}

///|
pub fn Actions::new() -> Actions {
  Actions::{
    set_election_timeout: false,
    save_current_term: false,
    save_voted_for: false,
    broadcast_message: None,
    append_log_entries: None,
    send_messages: Map::new(),
    install_snapshots: [],
  }
}

///|
fn Actions::set(self : Actions, action : Action) -> Unit {
  match action {
    SetElectionTimeout => self.set_election_timeout = true
    SaveCurrentTerm => self.save_current_term = true
    SaveVotedFor => self.save_voted_for = true
    AppendLogEntries(log_entries) =>
      match self.append_log_entries {
        Some(existing) => {
          let new_entries = existing
          new_entries.append(log_entries)
          self.append_log_entries = Some(new_entries)
        }
        None => self.append_log_entries = Some(log_entries)
      }
    BroadcastMessage(message) =>
      match self.broadcast_message {
        Some(existing) => {
          self.broadcast_message = Some(existing.merge(message))
        }
        None => self.broadcast_message = Some(message)
      }
    SendMessage(node_id, message) =>
      match self.send_messages.get(node_id) {
        Some(existing) => {
          self.send_messages[node_id] = existing.merge(message)
        }
        None => self.send_messages[node_id] = message
      }
    InstallSnapshot(node_id) => {
      insert_sorted_unique(self.install_snapshots, node_id)
    }
  }
}

///| Returns `true` if there are no actions to execute.
pub fn Actions::is_empty(self : Actions) -> Bool {
  not(self.set_election_timeout) &&
  not(self.save_current_term) &&
  not(self.save_voted_for) &&
  self.append_log_entries is None &&
  self.broadcast_message is None &&
  self.send_messages.is_empty() &&
  self.install_snapshots.is_empty()
}

///| Gets the next action to execute (if any), removing it from the queue.
pub fn Actions::next(self : Actions) -> Action? {
  if self.set_election_timeout {
    self.set_election_timeout = false
    return Some(SetElectionTimeout)
  }
  if self.save_current_term {
    self.save_current_term = false
    return Some(SaveCurrentTerm)
  }
  if self.save_voted_for {
    self.save_voted_for = false
    return Some(SaveVotedFor)
  }
  match self.broadcast_message {
    Some(msg) => {
      self.broadcast_message = None
      return Some(BroadcastMessage(msg))
    }
    None => ()
  }
  match self.append_log_entries {
    Some(entries) => {
      self.append_log_entries = None
      return Some(AppendLogEntries(entries))
    }
    None => ()
  }
  let send_keys = self.send_messages.keys().to_array()
  send_keys.sort()
  for node_id in send_keys {
    match self.send_messages.get(node_id) {
      Some(message) => {
        self.send_messages.remove(node_id)
        return Some(SendMessage(node_id, message))
      }
      None => ()
    }
  }
  if not(self.install_snapshots.is_empty()) {
    let node_id = self.install_snapshots[0]
    let _ = self.install_snapshots.remove(0)
    return Some(InstallSnapshot(node_id))
  }
  None
}

///| Returns all pending actions as an array.
pub fn Actions::to_array(self : Actions) -> Array[Action] {
  let result = []
  for action in self.iter() {
    result.push(action)
  }
  result
}

///| Returns the set election timeout flag.
pub fn Actions::get_set_election_timeout(self : Actions) -> Bool {
  self.set_election_timeout
}

///| Returns the save current term flag.
pub fn Actions::get_save_current_term(self : Actions) -> Bool {
  self.save_current_term
}

///| Returns the save voted for flag.
pub fn Actions::get_save_voted_for(self : Actions) -> Bool {
  self.save_voted_for
}

///| Returns the broadcast message (if any).
pub fn Actions::get_broadcast_message(self : Actions) -> Message? {
  self.broadcast_message
}

///| Returns the append log entries (if any).
pub fn Actions::get_append_log_entries(self : Actions) -> LogEntries? {
  self.append_log_entries
}

///| Returns the send messages map.
pub fn Actions::get_send_messages(self : Actions) -> Map[NodeId, Message] {
  self.send_messages
}

///| Returns the install snapshots array.
pub fn Actions::get_install_snapshots(self : Actions) -> Array[NodeId] {
  self.install_snapshots
}

///| Returns the set election timeout flag.
pub fn Actions::set_election_timeout(self : Actions) -> Bool {
  self.get_set_election_timeout()
}

///| Returns the save current term flag.
pub fn Actions::save_current_term(self : Actions) -> Bool {
  self.get_save_current_term()
}

///| Returns the save voted for flag.
pub fn Actions::save_voted_for(self : Actions) -> Bool {
  self.get_save_voted_for()
}

///| Returns the broadcast message (if any).
pub fn Actions::broadcast_message(self : Actions) -> Message? {
  self.get_broadcast_message()
}

///| Returns the append log entries (if any).
pub fn Actions::append_log_entries(self : Actions) -> LogEntries? {
  self.get_append_log_entries()
}

///| Returns the send messages map.
pub fn Actions::send_messages(self : Actions) -> Map[NodeId, Message] {
  self.get_send_messages()
}

///| Returns the install snapshots array.
pub fn Actions::install_snapshots(self : Actions) -> Array[NodeId] {
  self.get_install_snapshots()
}

///| Returns an iterator over pending actions.
pub fn Actions::iter(self : Actions) -> Iter[Action] {
  Iter::new(fn() { self.next() })
}

///| Returns an iterator over pending actions.
pub fn Actions::into_iter(self : Actions) -> Iter[Action] {
  self.iter()
}

///| Inserts a node id into a sorted unique array.
fn insert_sorted_unique(arr : Array[NodeId], id : NodeId) -> Unit {
  for i, existing in arr {
    let cmp = existing.compare(id)
    if cmp == 0 {
      return
    }
    if cmp > 0 {
      let _ = arr.insert(i, id)
      return
    }
  }
  arr.push(id)
}

///|
fn show_broadcast_message(msg : Message) -> String {
  "BroadcastMessage(" + msg.to_string() + ")"
}

///|
fn show_append_log_entries(entries : LogEntries) -> String {
  "AppendLogEntries(" + entries.to_string() + ")"
}

///|
fn show_send_message(node_id : NodeId, msg : Message) -> String {
  "SendMessage(" + node_id.to_string() + ", " + msg.to_string() + ")"
}

///|
fn show_install_snapshot(node_id : NodeId) -> String {
  "InstallSnapshot(" + node_id.to_string() + ")"
}

///| Show implementation for Action
pub impl Show for Action with output(self, logger) {
  match self {
    SetElectionTimeout => logger.write_string("SetElectionTimeout")
    SaveCurrentTerm => logger.write_string("SaveCurrentTerm")
    SaveVotedFor => logger.write_string("SaveVotedFor")
    BroadcastMessage(msg) =>
      logger.write_string(show_broadcast_message(msg))
    AppendLogEntries(entries) =>
      logger.write_string(show_append_log_entries(entries))
    SendMessage(node_id, msg) =>
      logger.write_string(show_send_message(node_id, msg))
    InstallSnapshot(node_id) =>
      logger.write_string(show_install_snapshot(node_id))
  }
}



///| Show implementation for Actions
pub impl Show for Actions with output(self, logger) {
  logger.write_string("Actions {")
  logger.write_string(" set_election_timeout=")
  self.set_election_timeout.output(logger)
  logger.write_string(", save_current_term=")
  self.save_current_term.output(logger)
  logger.write_string(", save_voted_for=")
  self.save_voted_for.output(logger)
  logger.write_string(", broadcast_message=")
  self.broadcast_message.output(logger)
  logger.write_string(", append_log_entries=")
  self.append_log_entries.output(logger)
  logger.write_string(", send_messages=")
  self.send_messages.output(logger)
  logger.write_string(", install_snapshots=")
  self.install_snapshots.output(logger)
  logger.write_string(" }")
}
