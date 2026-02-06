///| Message for RPC.
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

///| Returns the sender node ID of the message.
pub fn Message::from(self : Message) -> NodeId {
  match self {
    RequestVoteCall(from, _, _) => from
    RequestVoteReply(from, _, _) => from
    AppendEntriesCall(from, _, _, _) => from
    AppendEntriesReply(from, _, _, _) => from
  }
}

///| Returns the term of the message.
pub fn Message::term(self : Message) -> Term {
  match self {
    RequestVoteCall(_, term, _) => term
    RequestVoteReply(_, term, _) => term
    AppendEntriesCall(_, term, _, _) => term
    AppendEntriesReply(_, term, _, _) => term
  }
}

///|
pub fn Message::request_vote_call(
  term : Term,
  from : NodeId,
  last_position : LogPosition
) -> Message {
  RequestVoteCall(from, term, last_position)
}

///|
pub fn Message::request_vote_reply(
  term : Term,
  from : NodeId,
  vote_granted : Bool
) -> Message {
  RequestVoteReply(from, term, vote_granted)
}

///|
pub fn Message::append_entries_call(
  term : Term,
  from : NodeId,
  commit_index : LogIndex,
  entries : LogEntries
) -> Message {
  AppendEntriesCall(from, term, commit_index, entries)
}

///|
pub fn Message::append_entries_reply(
  term : Term,
  from : NodeId,
  generation : NodeGeneration,
  last_position : LogPosition
) -> Message {
  AppendEntriesReply(from, term, generation, last_position)
}

///| Merges another message into this one.
pub fn Message::merge(self : Message, other : Message) -> Message {
  guard self.from() == other.from() else {
    return other
  }
  guard self.term() <= other.term() else {
    return other
  }
  match (self, other) {
    (
      AppendEntriesCall(from0, term0, leader_commit0, entries0),
      AppendEntriesCall(from1, term1, leader_commit1, entries1),
    ) => {
      let mut new_entries = entries0
      if entries0.contains(LogPosition::new(entries1.prev_position().get_term(), entries1.prev_position().get_index())) {
        new_entries.append(entries1)
      } else {
        new_entries = entries1
      }
      AppendEntriesCall(from1, term1, leader_commit1, new_entries)
    }
    (_, other) => other
  }
}

///| Handles snapshot installation.
pub fn Message::handle_snapshot_installed(
  self : Message,
  last_included_position : LogPosition
) -> Message {
  match self {
    RequestVoteCall(from, term, last_position) => {
      let new_term = if term.get() > last_included_position.get_term().get() {
        term
      } else {
        last_included_position.get_term()
      }
      let new_last_position = if last_position.get_index().get() <
        last_included_position.get_index().get() {
        last_included_position
      } else {
        last_position
      }
      RequestVoteCall(from, new_term, new_last_position)
    }
    RequestVoteReply(from, term, vote_granted) => {
      let new_term = if term.get() > last_included_position.get_term().get() {
        term
      } else {
        last_included_position.get_term()
      }
      RequestVoteReply(from, new_term, vote_granted)
    }
    AppendEntriesCall(from, term, commit_index, entries) => {
      let new_term = if term.get() > last_included_position.get_term().get() {
        term
      } else {
        last_included_position.get_term()
      }
      entries.handle_snapshot_installed(last_included_position)
      AppendEntriesCall(from, new_term, commit_index, entries)
    }
    AppendEntriesReply(from, term, generation, last_position) => {
      let new_term = if term.get() > last_included_position.get_term().get() {
        term
      } else {
        last_included_position.get_term()
      }
      let new_last_position = if last_position.get_index().get() <
        last_included_position.get_index().get() {
        last_included_position
      } else {
        last_position
      }
      AppendEntriesReply(from, new_term, generation, new_last_position)
    }
  }
}

///| Show implementation for Message
pub impl Show for Message with output(self, logger) {
  match self {
    RequestVoteCall(from, term, last_position) =>
      logger.write_string(
        "RequestVoteCall(from=" +
        from.to_string() +
        ", term=" +
        term.to_string() +
        ", last_position=" +
        last_position.to_string() +
        ")",
      )
    RequestVoteReply(from, term, vote_granted) =>
      logger.write_string(
        "RequestVoteReply(from=" +
        from.to_string() +
        ", term=" +
        term.to_string() +
        ", vote_granted=" +
        vote_granted.to_string() +
        ")",
      )
    AppendEntriesCall(from, term, commit_index, entries) =>
      logger.write_string(
        "AppendEntriesCall(from=" +
        from.to_string() +
        ", term=" +
        term.to_string() +
        ", commit_index=" +
        commit_index.to_string() +
        ")",
      )
    AppendEntriesReply(from, term, generation, last_position) =>
      logger.write_string(
        "AppendEntriesReply(from=" +
        from.to_string() +
        ", term=" +
        term.to_string() +
        ", generation=" +
        generation.to_string() +
        ", last_position=" +
        last_position.to_string() +
        ")",
      )
  }
}
