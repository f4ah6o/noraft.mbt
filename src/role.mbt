///|
/// Role of a Raft node (follower, candidate, or leader).
///
/// Note that the Raft paper refers to this concept as "state".
/// However, this crate uses the term "role" as it is more specific and less ambiguous.
pub enum Role {
  /// Follower.
  Follower
  /// Candidate.
  Candidate
  /// Leader.
  Leader
} derive(Eq, Show, ToJson)

///|
/// Returns `true` if the role is leader.
pub fn Role::is_leader(self : Role) -> Bool {
  match self {
    Leader => true
    _ => false
  }
}

///|
/// Returns `true` if the role is follower.
pub fn Role::is_follower(self : Role) -> Bool {
  match self {
    Follower => true
    _ => false
  }
}

///|
/// Returns `true` if the role is candidate.
pub fn Role::is_candidate(self : Role) -> Bool {
  match self {
    Candidate => true
    _ => false
  }
}

///|
/// Commit status of a log entry.
pub enum CommitStatus {
  /// The log entry is currently being committed.
  InProgress
  /// The log entry has been successfully committed.
  Committed
  /// The log entry has been rejected.
  Rejected
  /// The log entry does not exist, typically due to removal by snapshotting.
  ///
  /// It is unknown whether the entry was ever committed or rejected.
  Unknown
} derive(Eq, Show, ToJson)

///|
/// Returns `true` if the status is `InProgress`.
pub fn CommitStatus::is_in_progress(self : CommitStatus) -> Bool {
  match self {
    InProgress => true
    _ => false
  }
}

///|
/// Returns `true` if the status is `Committed`.
pub fn CommitStatus::is_committed(self : CommitStatus) -> Bool {
  match self {
    Committed => true
    _ => false
  }
}

///|
/// Returns `true` if the status is `Rejected`.
pub fn CommitStatus::is_rejected(self : CommitStatus) -> Bool {
  match self {
    Rejected => true
    _ => false
  }
}

///|
/// Returns `true` if the status is `Unknown`.
pub fn CommitStatus::is_unknown(self : CommitStatus) -> Bool {
  match self {
    Unknown => true
    _ => false
  }
}
