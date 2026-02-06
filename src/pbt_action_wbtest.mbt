///| PBT for Action / Actions.

fn action_rank(action : Action) -> Int {
  match action {
    SetElectionTimeout => 0
    SaveCurrentTerm => 1
    SaveVotedFor => 2
    BroadcastMessage(_) => 3
    AppendLogEntries(_) => 4
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
