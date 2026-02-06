///| Log entry.
///
/// Each log entry within a cluster is uniquely identified by a `LogPosition`.
pub enum LogEntry {
  /// A log entry to indicate the start of a new term with a new leader.
  Term(Term)
  /// A log entry for a new cluster configuration.
  ClusterConfig(ClusterConfig)
  /// A log entry for a user-defined command.
  ///
  /// # Note
  ///
  /// This crate does not handle the content of user-defined commands.
  /// Therefore, this variant is represented as a unit.
  /// It is the user's responsibility to manage the mapping from each `LogEntry::Command` to
  /// an actual command data.
  Command
} derive(Eq)

///| Log entries.
///
/// This representation is compact and only requires `O(|terms|) + O(|configs|)` memory,
/// where `|terms|` is the number of `LogEntry::Term` entries and
/// `|configs|` is the number of `LogEntry::ClusterConfig` entries.
pub struct LogEntries {
  mut prev_position : LogPosition
  mut last_position : LogPosition
  mut terms : Map[LogIndex, Term]
  mut configs : Map[LogIndex, ClusterConfig]
}

///|
pub fn LogEntries::new(prev_position : LogPosition) -> LogEntries {
  LogEntries::{
    prev_position,
    last_position: prev_position,
    terms: Map::new(),
    configs: Map::new(),
  }
}

///| Makes a new `LogEntries` instance with the given entries.
pub fn LogEntries::from_array(
  prev_position : LogPosition,
  entries : Array[LogEntry]
) -> LogEntries {
  let this = LogEntries::new(prev_position)
  for entry in entries {
    this.push(entry)
  }
  this
}

///| Returns the number of entries in this `LogEntries` instance.
pub fn LogEntries::len(self : LogEntries) -> UInt64 {
  self.last_position.get_index().get() - self.prev_position.get_index().get()
}

///| Returns `true` if the log entries is empty.
pub fn LogEntries::is_empty(self : LogEntries) -> Bool {
  self.prev_position == self.last_position
}

///| Returns the position immediately before the first entry in this `LogEntries` instance.
pub fn LogEntries::prev_position(self : LogEntries) -> LogPosition {
  self.prev_position
}

///| Returns the position of the last entry in this `LogEntries` instance.
pub fn LogEntries::last_position(self : LogEntries) -> LogPosition {
  self.last_position
}

///| Returns an array of entries in this `LogEntries` instance.
pub fn LogEntries::to_array(self : LogEntries) -> Array[LogEntry] {
  let start = self.prev_position.get_index().get() + 1
  let end = self.last_position.get_index().get()
  let result = []
  for i in start..=end {
    let index = LogIndex::new(i)
    match self.terms.get(index) {
      Some(term) => result.push(Term(term))
      None =>
        match self.configs.get(index) {
          Some(config) => result.push(ClusterConfig(config))
          None => result.push(Command)
        }
    }
  }
  result
}

///| Returns an array of (position, entry) tuples in this `LogEntries` instance.
pub fn LogEntries::to_array_with_positions(
  self : LogEntries
) -> Array[(LogPosition, LogEntry)] {
  let base_index = self.prev_position.get_index().get() + 1
  let mut term = self.prev_position.get_term()
  let result = []
  let entries = self.to_array()
  for i, entry in entries {
    match entry {
      Term(t) => term = t
      _ => ()
    }
    let index = LogIndex::new(base_index + i.to_uint64())
    let position = LogPosition::new(term, index)
    result.push((position, entry))
  }
  result
}

///| Returns `true` if the given position is within the range of this entries.
pub fn LogEntries::contains(self : LogEntries, position : LogPosition) -> Bool {
  match self.get_term(position.get_index()) {
    Some(t) => t == position.get_term()
    None => false
  }
}

///| Returns `true` if the given index is within the range of this entries.
pub fn LogEntries::contains_index(self : LogEntries, index : LogIndex) -> Bool {
  index >= self.prev_position.get_index() && index <= self.last_position.get_index()
}

///| Returns the term of the given index if it is within the range of this entries.
pub fn LogEntries::get_term(self : LogEntries, index : LogIndex) -> Term? {
  if not(self.contains_index(index)) {
    return None
  }
  // Find the highest term <= index
  let mut result_term = self.prev_position.get_term()
  for idx, term in self.terms {
    if idx <= index {
      result_term = term
    }
  }
  Some(result_term)
}

///| Returns the entry at the given index if it is within the range of this entries.
///
/// Note that if the index is equal to the previous index, this method returns `None`.
pub fn LogEntries::get_entry(self : LogEntries, index : LogIndex) -> LogEntry? {
  if not(self.contains_index(index)) || self.prev_position.get_index() == index {
    return None
  }
  match self.terms.get(index) {
    Some(term) => Some(Term(term))
    None =>
      match self.configs.get(index) {
        Some(config) => Some(ClusterConfig(config))
        None => Some(Command)
      }
  }
}

///| Appends an entry to the back of this entries.
pub fn LogEntries::push(self : LogEntries, entry : LogEntry) -> Unit {
  self.last_position = self.last_position.next()
  match entry {
    Term(term) => {
      self.terms[self.last_position.get_index()] = term
      self.last_position = LogPosition::new(term, self.last_position.get_index())
    }
    ClusterConfig(config) => {
      self.configs[self.last_position.get_index()] = config
    }
    Command => ()
  }
}

///| Shortens the entries, keeping the first `len` entries and dropping the rest.
pub fn LogEntries::truncate(self : LogEntries, len : UInt64) -> Unit {
  let last_index = LogIndex::new(self.prev_position.get_index().get() + len)
  if self.last_position.get_index().get() <= last_index.get() {
    return
  }
  match self.get_term(last_index) {
    Some(last_term) => {
      self.last_position = LogPosition::new(last_term, last_index)
      // Remove terms and configs after last_index
      let keys_to_remove = []
      for index, _ in self.terms {
        if index.get() > last_index.get() {
          keys_to_remove.push(index)
        }
      }
      for key in keys_to_remove {
        self.terms.remove(key)
      }
      let config_keys_to_remove = []
      for index, _ in self.configs {
        if index.get() > last_index.get() {
          config_keys_to_remove.push(index)
        }
      }
      for key in config_keys_to_remove {
        self.configs.remove(key)
      }
    }
    None => ()
  }
}

///| Returns entries starting from the given position.
pub fn LogEntries::since(
  self : LogEntries,
  new_prev_position : LogPosition
) -> LogEntries? {
  if not(self.contains(new_prev_position)) {
    return None
  }
  let new_terms : Map[LogIndex, Term] = Map::new()
  let new_configs : Map[LogIndex, ClusterConfig] = Map::new()
  for index, term in self.terms {
    if index.get() > new_prev_position.get_index().get() {
      new_terms[index] = term
    }
  }
  for index, config in self.configs {
    if index.get() > new_prev_position.get_index().get() {
      new_configs[index] = config
    }
  }
  Some(
    LogEntries::{
      prev_position: new_prev_position,
      last_position: self.last_position,
      terms: new_terms,
      configs: new_configs,
    },
  )
}

///| Appends entries from another LogEntries.
pub fn LogEntries::append(self : LogEntries, entries : LogEntries) -> Unit {
  if self.last_position != entries.prev_position {
    // Truncate
    guard self.contains(entries.prev_position) else {
      return
    }
    self.last_position = entries.prev_position
    let keys_to_remove = []
    for index, _ in self.terms {
      if index.get() > self.last_position.get_index().get() {
        keys_to_remove.push(index)
      }
    }
    for key in keys_to_remove {
      self.terms.remove(key)
    }
    let config_keys_to_remove = []
    for index, _ in self.configs {
      if index.get() > self.last_position.get_index().get() {
        config_keys_to_remove.push(index)
      }
    }
    for key in config_keys_to_remove {
      self.configs.remove(key)
    }
  }
  // Extend
  for index, term in entries.terms {
    self.terms[index] = term
  }
  for index, config in entries.configs {
    self.configs[index] = config
  }
  self.last_position = entries.last_position
}

///| Strips the common prefix and returns only the diverging entries.
pub fn LogEntries::strip_common_prefix(
  self : LogEntries,
  local_entries : LogEntries
) -> LogEntries {
  guard local_entries.contains(self.prev_position) else {
    return self
  }
  guard not(local_entries.contains(self.last_position)) else {
    return self
  }
  if self.prev_position == local_entries.last_position {
    return self
  }
  if self.contains(local_entries.last_position) {
    return self.since(local_entries.last_position).unwrap()
  }
  let mut last_common_position = self.prev_position
  for index, term in self.terms {
    let position = LogPosition::new(term, index)
    if not(local_entries.contains(position)) {
      last_common_position = LogPosition::new(term, LogIndex::new(index.get() - 1))
      guard local_entries.contains(last_common_position) else {
        return self
      }
      return self.since(last_common_position).unwrap()
    }
    last_common_position = position
  }
  // self.terms is empty
  self
}

///| Handles snapshot installation.
pub fn LogEntries::handle_snapshot_installed(
  self : LogEntries,
  last_included_position : LogPosition
) -> Unit {
  if last_included_position.get_index() < self.prev_position.get_index() {
    return
  }
  if self.prev_position.get_index() < last_included_position.get_index() {
    self.prev_position = last_included_position
    self.last_position = last_included_position
    self.terms.clear()
    self.configs.clear()
  } else {
    match self.since(last_included_position) {
      Some(entries) => {
        self.prev_position = entries.prev_position
        self.last_position = entries.last_position
        self.terms = entries.terms
        self.configs = entries.configs
      }
      None => ()
    }
  }
}

///| In-memory representation of a `Node` local log.
pub struct Log {
  snapshot_config : ClusterConfig
  entries : LogEntries
}

///|
pub fn Log::new(
  snapshot_config : ClusterConfig,
  entries : LogEntries
) -> Log {
  Log::{ snapshot_config, entries }
}

///| Returns a reference to the entries in this log.
pub fn Log::get_entries(self : Log) -> LogEntries {
  self.entries
}

///| Returns a mutable reference to the entries in this log.
pub fn Log::entries_mut(self : Log) -> LogEntries {
  self.entries
}

///| Returns the position of the last entry in this log.
pub fn Log::last_position(self : Log) -> LogPosition {
  self.entries.last_position()
}

///| Returns the log position where the snapshot was taken.
pub fn Log::snapshot_position(self : Log) -> LogPosition {
  self.entries.prev_position()
}

///| Returns a reference to the cluster configuration at the time the snapshot was taken.
pub fn Log::snapshot_config(self : Log) -> ClusterConfig {
  self.snapshot_config
}

///| Returns a reference to the cluster configuration located at the highest index in this log.
pub fn Log::latest_config(self : Log) -> ClusterConfig {
  match self.entries.configs.values().last() {
    Some(config) => config
    None => self.snapshot_config
  }
}

///| Returns the log position and a reference to the most recent cluster configuration at the given index.
pub fn Log::get_position_and_config(
  self : Log,
  index : LogIndex
) -> (LogPosition, ClusterConfig)? {
  match self.entries.get_term(index) {
    Some(term) =>
      match self.get_config(index) {
        Some(config) => Some((LogPosition::new(term, index), config))
        None => None
      }
    None => None
  }
}

///|
pub fn Log::get_config(self : Log, index : LogIndex) -> ClusterConfig? {
  if not(self.entries.contains_index(index)) {
    return None
  }
  // Find the highest config <= index
  let mut result_config = self.snapshot_config
  for idx, config in self.entries.configs {
    if idx <= index {
      result_config = config
    }
  }
  Some(result_config)
}

///|
pub fn Log::latest_config_index(self : Log) -> LogIndex {
  match self.entries.configs.keys().last() {
    Some(index) => index
    None => self.entries.prev_position().get_index()
  }
}

///| Show implementation for LogEntry
pub impl Show for LogEntry with output(self, logger) {
  match self {
    Term(t) => {
      logger.write_string("Term(")
      t.output(logger)
      logger.write_string(")")
    }
    ClusterConfig(config) => {
      logger.write_string("ClusterConfig(")
      config.output(logger)
      logger.write_string(")")
    }
    Command => logger.write_string("Command")
  }
}

///| Show implementation for LogEntries
pub impl Show for LogEntries with output(self, logger) {
  logger.write_string("LogEntries {")
  logger.write_string(" prev_position=")
  self.prev_position.output(logger)
  logger.write_string(", last_position=")
  self.last_position.output(logger)
  logger.write_string(", len=")
  self.len().output(logger)
  logger.write_string(" }")
}

///| Show implementation for Log
pub impl Show for Log with output(self, logger) {
  logger.write_string("Log {")
  logger.write_string(" snapshot_config=")
  self.snapshot_config.output(logger)
  logger.write_string(", entries=")
  self.entries.output(logger)
  logger.write_string(" }")
}
