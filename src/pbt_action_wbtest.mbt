///| PBT for Action / Actions.

fn action_rank(action : Action) -> Int {
  match action {
    SetElectionTimeout => 0
    SaveCurrentTerm => 1
    SaveVotedFor => 2
    BroadcastMessage(_) => 3
    AppendLogEntries(_) => 4
    AppendSingleLogEntry(_, _) => 4
    SendMessage(_, _) => 5
    InstallSnapshot(_) => 6
  }
}

fn is_non_decreasing(ranks : Array[Int]) -> Bool {
  for i in 1..<ranks.length() {
    if ranks[i - 1] > ranks[i] {
      return false
    }
  }
  true
}

test "PBT: Actions set makes non-empty" {
  @qc.quick_check(
    @qc.forall(gen_non_empty_array(6, gen_action()), fn(actions_arr) {
      let actions = Actions::new()
      for act in actions_arr {
        actions.set(act)
      }
      actions.is_empty() == false
    })
  )
}

test "PBT: Actions to_array drains the queue" {
  @qc.quick_check(
    @qc.forall(gen_array_sized(8, gen_action()), fn(actions_arr) {
      let actions = Actions::new()
      for act in actions_arr {
        actions.set(act)
      }
      let _ = actions.to_array()
      actions.is_empty()
    })
  )
}

test "PBT: Actions to_array follows priority order" {
  @qc.quick_check(
    @qc.forall(gen_array_sized(10, gen_action()), fn(actions_arr) {
      let actions = Actions::new()
      for act in actions_arr {
        actions.set(act)
      }
      let result = actions.to_array()
      let ranks = result.map(action_rank)
      is_non_decreasing(ranks)
    })
  )
}

test "PBT: Actions InstallSnapshot is de-duplicated" {
  @qc.quick_check(
    @qc.forall(gen_array_sized(10, gen_node_id()), fn(ids) {
      let uniq : Map[NodeId, Unit] = {}
      for id in ids {
        uniq[id] = ()
      }
      let actions = Actions::new()
      for id in ids {
        actions.set(Action::InstallSnapshot(id))
      }
      let result = actions.to_array()
      let installed : Map[NodeId, Unit] = {}
      for action in result {
        match action {
          InstallSnapshot(id) => installed[id] = ()
          _ => ()
        }
      }
      installed.length() == uniq.length()
    })
  )
}

test "Actions SendMessage order is sorted by NodeId" {
  let actions = Actions::new()
  let msg = Message::request_vote_call(term_zero, NodeId::new(0), log_position_zero)
  actions.set(Action::SendMessage(NodeId::new(2), msg))
  actions.set(Action::SendMessage(NodeId::new(1), msg))
  actions.set(Action::SendMessage(NodeId::new(3), msg))
  let result = actions.to_array()
  let ids = []
  for action in result {
    match action {
      SendMessage(id, _) => ids.push(id.get())
      _ => ()
    }
  }
  inspect(ids, content="[1, 2, 3]")
}

test "Actions InstallSnapshot order is sorted by NodeId" {
  let actions = Actions::new()
  actions.set(Action::InstallSnapshot(NodeId::new(3)))
  actions.set(Action::InstallSnapshot(NodeId::new(1)))
  actions.set(Action::InstallSnapshot(NodeId::new(2)))
  let result = actions.to_array()
  let ids = []
  for action in result {
    match action {
      InstallSnapshot(id) => ids.push(id.get())
      _ => ()
    }
  }
  inspect(ids, content="[1, 2, 3]")
}

test "PBT: Actions SendMessage merges by from and term" {
  @qc.quick_check(
    @qc.forall(@qc.liftA3(fn(a, b, c) { (a, b, c) }, gen_node_id(), gen_message(), gen_message()), fn(triple) {
      let (node_id, m1, m2) = triple
      // Force same sender to exercise merge path.
      let msg1 = Message::request_vote_call(m1.term(), node_id, log_position_zero)
      let msg2 = Message::request_vote_call(m2.term(), node_id, log_position_zero)
      let actions = Actions::new()
      actions.set(Action::SendMessage(node_id, msg1))
      actions.set(Action::SendMessage(node_id, msg2))
      let arr = actions.to_array()
      let sent = arr.filter(fn(a) { a is SendMessage(_, _) })
      sent.length() == 1
    })
  )
}

test "Action show format stays stable" {
  inspect(
    Action::BroadcastMessage(
      Message::request_vote_reply(Term::new(2), NodeId::new(1), true),
    ).to_string(),
    content="BroadcastMessage(RequestVoteReply(from=1, term=2, vote_granted=true))",
  )
  inspect(
    Action::AppendLogEntries(
      LogEntries::from_array(log_position_zero, [LogEntry::Command]),
    ).to_string(),
    content=
      "AppendLogEntries(LogEntries { prev_position=LogPosition { term=0, index=0 }, last_position=LogPosition { term=0, index=1 }, len=1 })",
  )
  inspect(
    Action::AppendSingleLogEntry(log_position_zero, LogEntry::Command).to_string(),
    content=
      "AppendSingleLogEntry(LogPosition { term=0, index=0 }, Command)",
  )
  inspect(
    Action::SendMessage(
      NodeId::new(3),
      Message::request_vote_call(
        Term::new(4),
        NodeId::new(3),
        LogPosition::new(Term::new(5), LogIndex::new(6)),
      ),
    ).to_string(),
    content=
      "SendMessage(3, RequestVoteCall(from=3, term=4, last_position=LogPosition { term=5, index=6 }))",
  )
  inspect(
    Action::InstallSnapshot(NodeId::new(7)).to_string(),
    content="InstallSnapshot(7)",
  )
}
