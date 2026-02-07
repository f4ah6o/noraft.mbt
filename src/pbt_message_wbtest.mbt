///| PBT for Message.

fn gen_message_triplet() -> @qc.Gen[(Message, NodeId, Term)] {
  let gen_from = gen_node_id()
  let gen_term = gen_term()
  @qc.frequency([
    (
      3,
      @qc.liftA3(fn(from, term, pos) {
        (Message::request_vote_call(term, from, pos), from, term)
      }, gen_from, gen_term, gen_log_position()),
    ),
    (
      3,
      @qc.liftA3(fn(from, term, granted) {
        (Message::request_vote_reply(term, from, granted), from, term)
      }, gen_from, gen_term, @qc.Gen::spawn()),
    ),
    (
      3,
      @qc.liftA4(fn(from, term, commit_index, entries) {
        (Message::append_entries_call(term, from, commit_index, entries), from, term)
      }, gen_from, gen_term, gen_log_index(), gen_log_entries()),
    ),
    (
      3,
      @qc.liftA4(fn(from, term, gen, pos) {
        (Message::append_entries_reply(term, from, gen, pos), from, term)
      }, gen_from, gen_term, gen_generation(), gen_log_position()),
    ),
  ])
}

fn log_entries_eq(a : LogEntries, b : LogEntries) -> Bool {
  a.prev_position() == b.prev_position() &&
  a.last_position() == b.last_position() &&
  a.to_array() == b.to_array()
}

fn message_eq(a : Message, b : Message) -> Bool {
  match (a, b) {
    (RequestVoteCall(from0, term0, pos0), RequestVoteCall(from1, term1, pos1)) =>
      from0 == from1 && term0 == term1 && pos0 == pos1
    (RequestVoteReply(from0, term0, granted0), RequestVoteReply(from1, term1, granted1)) =>
      from0 == from1 && term0 == term1 && granted0 == granted1
    (AppendEntriesCall(from0, term0, commit0, entries0), AppendEntriesCall(from1, term1, commit1, entries1)) =>
      from0 == from1 && term0 == term1 && commit0 == commit1 &&
      log_entries_eq(entries0, entries1)
    (AppendEntriesReply(from0, term0, gen0, pos0), AppendEntriesReply(from1, term1, gen1, pos1)) =>
      from0 == from1 && term0 == term1 && gen0 == gen1 && pos0 == pos1
    _ => false
  }
}

test "PBT: Message from/term are consistent with constructors" {
  @qc.quick_check(
    @qc.forall(gen_message_triplet(), fn(triple) {
      let (msg, from, term) = triple
      msg.from() == from && msg.term() == term
    })
  )
}

test "PBT: AppendEntriesCall merge appends when prev_position is contained" {
  @qc.quick_check(
    @qc.forall(@qc.tuple(gen_node_id(), gen_log_entries()), fn(pair) {
      let (from, base_entries) = pair
      let prev = base_entries.last_position()
      @qc.forall(gen_log_entries_from_prev(prev), fn(extra_entries) {
        let term0 = Term::new(1)
        let term1 = Term::new(1)
        let commit0 = log_index_zero
        let commit1 = log_index_zero
        let base_for_msg = base_entries
        let base_for_expected = base_entries
        let msg1 = Message::append_entries_call(term0, from, commit0, base_for_msg)
        let msg2 = Message::append_entries_call(term1, from, commit1, extra_entries)
        let expected_entries = base_for_expected
        expected_entries.append(extra_entries)
        let expected = Message::append_entries_call(term1, from, commit1, expected_entries)
        message_eq(msg1.merge(msg2), expected)
      })
    })
  )
}

test "PBT: AppendEntriesCall merge returns other when prev_position is not contained" {
  @qc.quick_check(
    @qc.forall(@qc.tuple(gen_node_id(), gen_log_entries()), fn(pair) {
      let (from, base_entries) = pair
      let prev = base_entries.last_position().next()
      @qc.forall(gen_log_entries_from_prev(prev), fn(extra_entries) {
        let term0 = Term::new(1)
        let term1 = Term::new(1)
        let commit0 = log_index_zero
        let commit1 = log_index_zero
        let msg1 = Message::append_entries_call(term0, from, commit0, base_entries)
        let msg2 = Message::append_entries_call(term1, from, commit1, extra_entries)
        message_eq(msg1.merge(msg2), msg2)
      })
    })
  )
}

test "PBT: Message handle_snapshot_installed updates term and positions" {
  @qc.quick_check(
    @qc.forall(@qc.tuple(gen_message(), gen_log_position()), fn(pair) {
      let (msg, snapshot_pos) = pair
      let updated = msg.handle_snapshot_installed(snapshot_pos)
      if updated.term().get() < snapshot_pos.get_term().get() {
        return false
      }
      match updated {
        RequestVoteCall(_, _, last_pos) =>
          last_pos.get_index().get() >= snapshot_pos.get_index().get()
        AppendEntriesReply(_, _, _, last_pos) =>
          last_pos.get_index().get() >= snapshot_pos.get_index().get()
        _ => true
      }
    })
  )
}

test "Message show format stays stable" {
  let request_vote_call = Message::request_vote_call(
    Term::new(2),
    NodeId::new(1),
    LogPosition::new(Term::new(3), LogIndex::new(4)),
  )
  inspect(
    request_vote_call.to_string(),
    content=
      "RequestVoteCall(from=1, term=2, last_position=LogPosition { term=3, index=4 })",
  )

  let request_vote_reply =
    Message::request_vote_reply(Term::new(6), NodeId::new(5), true)
  inspect(
    request_vote_reply.to_string(),
    content="RequestVoteReply(from=5, term=6, vote_granted=true)",
  )

  let append_entries_call = Message::append_entries_call(
    Term::new(8),
    NodeId::new(7),
    LogIndex::new(9),
    LogEntries::new(log_position_zero),
  )
  inspect(
    append_entries_call.to_string(),
    content="AppendEntriesCall(from=7, term=8, commit_index=9)",
  )

  let append_entries_reply = Message::append_entries_reply(
    Term::new(11),
    NodeId::new(10),
    NodeGeneration::new(12),
    LogPosition::new(Term::new(13), LogIndex::new(14)),
  )
  inspect(
    append_entries_reply.to_string(),
    content=
      "AppendEntriesReply(from=10, term=11, generation=12, last_position=LogPosition { term=13, index=14 })",
  )
}

test "Message handle_snapshot_installed updates all variants consistently" {
  let snapshot = LogPosition::new(Term::new(7), LogIndex::new(10))
  let entries = LogEntries::from_array(
    LogPosition::new(Term::new(1), LogIndex::new(2)),
    [LogEntry::Command, LogEntry::Command],
  )
  let msgs = [
    Message::request_vote_call(
      Term::new(1),
      NodeId::new(1),
      LogPosition::new(Term::new(2), LogIndex::new(3)),
    ),
    Message::request_vote_reply(Term::new(2), NodeId::new(2), false),
    Message::append_entries_call(Term::new(3), NodeId::new(3), LogIndex::new(4), entries),
    Message::append_entries_reply(
      Term::new(4),
      NodeId::new(4),
      NodeGeneration::new(5),
      LogPosition::new(Term::new(6), LogIndex::new(7)),
    ),
  ]
  for msg in msgs {
    let updated = msg.handle_snapshot_installed(snapshot)
    assert_true(updated.term() >= snapshot.get_term())
  }
}
