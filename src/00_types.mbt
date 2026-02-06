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

///|
pub fn NodeId::from_uint64(value : UInt64) -> NodeId {
  NodeId::new(value)
}

///|
pub fn NodeId::to_uint64(self : NodeId) -> UInt64 {
  self.value
}

///| Adds two node IDs.
pub fn NodeId::add(self : NodeId, other : NodeId) -> NodeId {
  NodeId::new(self.value + other.value)
}

///| Subtracts two node IDs.
pub fn NodeId::sub(self : NodeId, other : NodeId) -> NodeId {
  NodeId::new(self.value - other.value)
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

///|
pub fn NodeGeneration::from_uint64(value : UInt64) -> NodeGeneration {
  NodeGeneration::new(value)
}

///|
pub fn NodeGeneration::to_uint64(self : NodeGeneration) -> UInt64 {
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
pub fn Term::from_uint64(value : UInt64) -> Term {
  Term::new(value)
}

///|
pub fn Term::to_uint64(self : Term) -> UInt64 {
  self.value
}

///|
pub fn Term::next(self : Term) -> Term {
  Term::{ value: self.value + 1 }
}

///| Adds two terms.
pub fn Term::add(self : Term, other : Term) -> Term {
  Term::new(self.value + other.value)
}

///| Subtracts two terms.
pub fn Term::sub(self : Term, other : Term) -> Term {
  Term::new(self.value - other.value)
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
pub fn LogIndex::from_uint64(value : UInt64) -> LogIndex {
  LogIndex::new(value)
}

///|
pub fn LogIndex::to_uint64(self : LogIndex) -> UInt64 {
  self.value
}

///|
pub fn LogIndex::next(self : LogIndex) -> LogIndex {
  LogIndex::{ value: self.value + 1 }
}

///| Adds two log indices.
pub fn LogIndex::add(self : LogIndex, other : LogIndex) -> LogIndex {
  LogIndex::new(self.value + other.value)
}

///| Subtracts two log indices.
pub fn LogIndex::sub(self : LogIndex, other : LogIndex) -> LogIndex {
  LogIndex::new(self.value - other.value)
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

// PBT: Arbitrary implementations
// ================================

///| Arbitrary implementation for NodeId
pub impl @moonbitlang/core/quickcheck.Arbitrary for NodeId with arbitrary(_size, rs) {
  NodeId::new(rs.next_uint64())
}

///| Shrink implementation for NodeId
pub impl @moonbitlang/quickcheck.Shrink for NodeId with shrink(self) {
  if self.get() == 0 {
    Iter::empty()
  } else {
    Iter::singleton(NodeId::new(self.get() / 2))
  }
}

///| Arbitrary implementation for Term
pub impl @moonbitlang/core/quickcheck.Arbitrary for Term with arbitrary(_size, rs) {
  Term::new(rs.next_uint64())
}

///| Shrink implementation for Term
pub impl @moonbitlang/quickcheck.Shrink for Term with shrink(self) {
  if self.get() == 0 {
    Iter::empty()
  } else {
    Iter::singleton(Term::new(self.get() / 2))
  }
}

///| Arbitrary implementation for LogIndex
pub impl @moonbitlang/core/quickcheck.Arbitrary for LogIndex with arbitrary(_size, rs) {
  LogIndex::new(rs.next_uint64())
}

///| Shrink implementation for LogIndex
pub impl @moonbitlang/quickcheck.Shrink for LogIndex with shrink(self) {
  if self.get() == 0 {
    Iter::empty()
  } else {
    Iter::singleton(LogIndex::new(self.get() / 2))
  }
}

///| Arbitrary implementation for NodeGeneration
pub impl @moonbitlang/core/quickcheck.Arbitrary for NodeGeneration with arbitrary(_size, rs) {
  NodeGeneration::new(rs.next_uint64())
}

///| Shrink implementation for NodeGeneration
pub impl @moonbitlang/quickcheck.Shrink for NodeGeneration with shrink(self) {
  if self.get() == 0 {
    Iter::empty()
  } else {
    Iter::singleton(NodeGeneration::new(self.get() / 2))
  }
}

///| Arbitrary implementation for LogPosition
pub impl @moonbitlang/core/quickcheck.Arbitrary for LogPosition with arbitrary(size, rs) {
  let term = @moonbitlang/core/quickcheck.Arbitrary::arbitrary(size, rs)
  let index = @moonbitlang/core/quickcheck.Arbitrary::arbitrary(size, rs)
  LogPosition::new(term, index)
}

///| Shrink implementation for LogPosition
pub impl @moonbitlang/quickcheck.Shrink for LogPosition with shrink(self) {
  let term_shrinks = @moonbitlang/quickcheck.Shrink::shrink(self.get_term()).map(fn(t) { LogPosition::new(t, self.get_index()) })
  let index_shrinks = @moonbitlang/quickcheck.Shrink::shrink(self.get_index()).map(fn(i) { LogPosition::new(self.get_term(), i) })
  term_shrinks.concat(index_shrinks)
}
