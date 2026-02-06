///| noraft: Minimal, feature-complete Raft for MoonBit - no I/O, no dependencies.
///
/// [Raft]: https://raft.github.io/
///
/// `Node` is the main struct that represents a Raft node.
/// It offers methods for creating a cluster, proposing commands, updating cluster configurations,
/// handling incoming messages, snapshotting, and more.
///
/// `Node` itself does not execute I/O operations.
/// Instead, it generates `Action`s that represent pending I/O operations.
/// How to execute these actions is up to the user.

///| Node identifier ([`UInt64`]).
pub struct NodeId {
  value : UInt64
} derive(Eq, Compare)

///|
pub fn NodeId::new(id : UInt64) -> NodeId {
  NodeId::{ value: id }
}

///|
pub fn NodeId::get(self : NodeId) -> UInt64 {
  self.value
}

///| Node generation ([`UInt64`]).
///
/// The user is responsible for supplying a unique generation on restart.
/// The generation should be monotonically increasing for the same node.
pub struct NodeGeneration {
  value : UInt64
} derive(Eq, Compare)

///|
pub let node_generation_zero : NodeGeneration = NodeGeneration::{ value: 0 }

///|
pub fn NodeGeneration::new(generation : UInt64) -> NodeGeneration {
  NodeGeneration::{ value: generation }
}

///|
pub fn NodeGeneration::get(self : NodeGeneration) -> UInt64 {
  self.value
}

///| Term.
pub struct Term {
  value : UInt64
} derive(Eq, Compare)

///| The initial term.
pub let term_zero : Term = Term::{ value: 0 }

///|
pub fn Term::new(t : UInt64) -> Term {
  Term::{ value: t }
}

///|
pub fn Term::get(self : Term) -> UInt64 {
  self.value
}

///|
pub fn Term::next(self : Term) -> Term {
  Term::{ value: self.value + 1 }
}

///| Log index.
///
/// According to the Raft paper, index 0 serves as a sentinel value,
/// and the actual log entries start from index 1.
pub struct LogIndex {
  value : UInt64
} derive(Eq, Compare)

///| The initial log index (sentinel value)
pub let log_index_zero : LogIndex = LogIndex::{ value: 0 }

///|
pub fn LogIndex::new(i : UInt64) -> LogIndex {
  LogIndex::{ value: i }
}

///|
pub fn LogIndex::get(self : LogIndex) -> UInt64 {
  self.value
}

///|
pub fn LogIndex::next(self : LogIndex) -> LogIndex {
  LogIndex::{ value: self.value + 1 }
}

///| Log position ([`Term`] and [`LogIndex`]).
///
/// A `LogPosition` uniquely identifies a `LogEntry` stored within a cluster.
pub struct LogPosition {
  term : Term
  index : LogIndex
} derive(Eq, Compare)

///| The initial log position ([`term_zero`] and [`log_index_zero`]).
pub let log_position_zero : LogPosition = LogPosition::{ term: term_zero, index: log_index_zero }

///| An invalid log position.
pub let log_position_invalid : LogPosition = LogPosition::{ term: Term::{ value: 18446744073709551615 }, index: log_index_zero }

///|
pub fn LogPosition::new(term : Term, index : LogIndex) -> LogPosition {
  LogPosition::{ term, index }
}

///|
pub fn LogPosition::next(self : LogPosition) -> LogPosition {
  LogPosition::{ term: self.term, index: LogIndex::{ value: self.index.get() + 1 } }
}

///| Returns `true` if this position is equal to `log_position_invalid`.
pub fn LogPosition::is_invalid(self : LogPosition) -> Bool {
  self.term.get() == 18446744073709551615 && self.index.get() == 0
}

///| Returns the term of the log entry.
pub fn LogPosition::get_term(self : LogPosition) -> Term {
  self.term
}

///| Returns the index of the log entry.
pub fn LogPosition::get_index(self : LogPosition) -> LogIndex {
  self.index
}

///| Show implementation for LogPosition
pub impl Show for LogPosition with output(self, logger) {
  logger.write_string("LogPosition { term=")
  self.term.get().output(logger)
  logger.write_string(", index=")
  self.index.get().output(logger)
  logger.write_string(" }")
}

///| Show implementation for NodeId
pub impl Show for NodeId with output(self, logger) {
  self.value.output(logger)
}

///| Hash implementation for NodeId
pub impl Hash for NodeId with hash_combine(self, hasher) {
  hasher.combine(self.value)
}

///| Show implementation for NodeGeneration
pub impl Show for NodeGeneration with output(self, logger) {
  self.value.output(logger)
}

///| Show implementation for Term
pub impl Show for Term with output(self, logger) {
  self.value.output(logger)
}

///| Show implementation for LogIndex
pub impl Show for LogIndex with output(self, logger) {
  self.value.output(logger)
}

///| Hash implementation for LogIndex
pub impl Hash for LogIndex with hash_combine(self, hasher) {
  hasher.combine(self.value)
}
