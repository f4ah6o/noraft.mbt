///|
/// Message for RPC.
///
/// Note that this enum does not include the InstallSnapshot RPC,
/// as the specifics of snapshot installation depend heavily on
/// each individual application and are not managed by this crate.
pub enum Message {
  RequestVoteCall(NodeId, Term, LogPosition)
  RequestVoteReply(NodeId, Term, Bool)
  AppendEntriesCall(NodeId, Term, LogIndex, LogEntries)
  AppendEntriesReply(NodeId, Term, NodeGeneration, LogPosition)
}

///|
/// Returns the sender node ID of the message.
pub fn Message::from(self : Message) -> NodeId {
  match self {
    RequestVoteCall(from, _, _) => from
    RequestVoteReply(from, _, _) => from
    AppendEntriesCall(from, _, _, _) => from
    AppendEntriesReply(from, _, _, _) => from
  }
}

///|
/// Returns the term of the message.
pub fn Message::term(self : Message) -> Term {
  match self {
    RequestVoteCall(_, term, _) => term
    RequestVoteReply(_, term, _) => term
    AppendEntriesCall(_, term, _, _) => term
    AppendEntriesReply(_, term, _, _) => term
  }
}

///|
fn Message::request_vote_call(
  term : Term,
  from : NodeId,
  last_position : LogPosition,
) -> Message {
  RequestVoteCall(from, term, last_position)
}

///|
fn Message::request_vote_reply(
  term : Term,
  from : NodeId,
  vote_granted : Bool,
) -> Message {
  RequestVoteReply(from, term, vote_granted)
}

///|
fn Message::append_entries_call(
  term : Term,
  from : NodeId,
  commit_index : LogIndex,
  entries : LogEntries,
) -> Message {
  AppendEntriesCall(from, term, commit_index, entries)
}

///|
fn Message::append_entries_reply(
  term : Term,
  from : NodeId,
  generation : NodeGeneration,
  last_position : LogPosition,
) -> Message {
  AppendEntriesReply(from, term, generation, last_position)
}

///|
/// Merges another message into this one.
fn Message::merge(self : Message, other : Message) -> Message {
  match (self, other) {
    (
      AppendEntriesCall(_from0, _term0, _leader_commit0, entries0),
      AppendEntriesCall(from1, term1, leader_commit1, entries1),
    ) => {
      // Only AppendEntriesCall can be merged; all other RPCs keep the latest one.
      let mut new_entries = entries0
      if entries0.contains(entries1.prev_position()) {
        new_entries.append(entries1)
      } else {
        new_entries = entries1
      }
      AppendEntriesCall(from1, term1, leader_commit1, new_entries)
    }
    (_, other) => other
  }
}

///|
fn term_at_least(term : Term, min_term : Term) -> Term {
  if term > min_term {
    term
  } else {
    min_term
  }
}

///|
fn position_at_least(
  position : LogPosition,
  min_position : LogPosition,
) -> LogPosition {
  if position.get_index() < min_position.get_index() {
    min_position
  } else {
    position
  }
}

///|
/// Handles snapshot installation.
fn Message::handle_snapshot_installed(
  self : Message,
  last_included_position : LogPosition,
) -> Message {
  let min_term = last_included_position.get_term()
  match self {
    RequestVoteCall(from, term, last_position) => {
      let new_term = term_at_least(term, min_term)
      let new_last_position = position_at_least(
        last_position, last_included_position,
      )
      RequestVoteCall(from, new_term, new_last_position)
    }
    RequestVoteReply(from, term, vote_granted) => {
      let new_term = term_at_least(term, min_term)
      RequestVoteReply(from, new_term, vote_granted)
    }
    AppendEntriesCall(from, term, commit_index, entries) => {
      let new_term = term_at_least(term, min_term)
      entries.handle_snapshot_installed(last_included_position)
      AppendEntriesCall(from, new_term, commit_index, entries)
    }
    AppendEntriesReply(from, term, generation, last_position) => {
      let new_term = term_at_least(term, min_term)
      let new_last_position = position_at_least(
        last_position, last_included_position,
      )
      AppendEntriesReply(from, new_term, generation, new_last_position)
    }
  }
}

///|
fn show_request_vote_call(
  from : NodeId,
  term : Term,
  last_position : LogPosition,
) -> String {
  "RequestVoteCall(from=" +
  from.to_string() +
  ", term=" +
  term.to_string() +
  ", last_position=" +
  last_position.to_string() +
  ")"
}

///|
fn show_request_vote_reply(
  from : NodeId,
  term : Term,
  vote_granted : Bool,
) -> String {
  "RequestVoteReply(from=" +
  from.to_string() +
  ", term=" +
  term.to_string() +
  ", vote_granted=" +
  vote_granted.to_string() +
  ")"
}

///|
fn show_append_entries_call(
  from : NodeId,
  term : Term,
  commit_index : LogIndex,
) -> String {
  // Keep logs compact by intentionally omitting entries payload details.
  "AppendEntriesCall(from=" +
  from.to_string() +
  ", term=" +
  term.to_string() +
  ", commit_index=" +
  commit_index.to_string() +
  ")"
}

///|
fn show_append_entries_reply(
  from : NodeId,
  term : Term,
  generation : NodeGeneration,
  last_position : LogPosition,
) -> String {
  "AppendEntriesReply(from=" +
  from.to_string() +
  ", term=" +
  term.to_string() +
  ", generation=" +
  generation.to_string() +
  ", last_position=" +
  last_position.to_string() +
  ")"
}

///|
/// Show implementation for Message
pub impl Show for Message with output(self, logger) {
  match self {
    RequestVoteCall(from, term, last_position) =>
      logger.write_string(show_request_vote_call(from, term, last_position))
    RequestVoteReply(from, term, vote_granted) =>
      logger.write_string(show_request_vote_reply(from, term, vote_granted))
    AppendEntriesCall(from, term, commit_index, _entries) =>
      logger.write_string(show_append_entries_call(from, term, commit_index))
    AppendEntriesReply(from, term, generation, last_position) =>
      logger.write_string(
        show_append_entries_reply(from, term, generation, last_position),
      )
  }
}
