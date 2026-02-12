///|
/// PBT generators for noraft.
fn gen_uint64() -> @qc.Gen[UInt64] {
  @qc.frequency([
    (70, @qc.Gen::spawn()),
    (15, @qc.one_of([@qc.pure(0), @qc.pure(1), @qc.pure(@uint64.max_value)])),
    (
      15,
      @qc.one_of([@qc.pure(2), @qc.pure(3), @qc.pure(@uint64.max_value - 1)]),
    ),
  ])
}

///|
fn gen_node_id() -> @qc.Gen[NodeId] {
  gen_uint64().fmap(NodeId::new)
}

///|
fn gen_term() -> @qc.Gen[Term] {
  gen_uint64().fmap(Term::new)
}

///|
fn gen_small_uint64(max : Int) -> @qc.Gen[UInt64] {
  @qc.sized(fn(size) {
    let bound = if max <= 0 { 1 } else { max }
    let limit = if size < bound { size } else { bound - 1 }
    @qc.int_range(0, limit + 1).fmap(fn(i) { i.to_uint64() })
  })
}

///|
fn gen_log_index() -> @qc.Gen[LogIndex] {
  gen_small_uint64(64).fmap(LogIndex::new)
}

///|
fn gen_generation() -> @qc.Gen[NodeGeneration] {
  gen_uint64().fmap(NodeGeneration::new)
}

///|
fn gen_log_position() -> @qc.Gen[LogPosition] {
  @qc.liftA2(LogPosition::new, gen_term(), gen_log_index())
}

///|
fn[T] gen_array_len(len : Int, gen : @qc.Gen[T]) -> @qc.Gen[Array[T]] {
  let gens : Array[@qc.Gen[T]] = []
  for _i in 0..<len {
    gens.push(gen)
  }
  @qc.flatten_array(gens)
}

///|
fn[T] gen_array_sized(max_len : Int, gen : @qc.Gen[T]) -> @qc.Gen[Array[T]] {
  @qc.sized(fn(size) {
    let len = if max_len <= 0 { 0 } else { size % max_len }
    gen_array_len(len, gen)
  })
}

///|
fn[T] gen_non_empty_array(max_len : Int, gen : @qc.Gen[T]) -> @qc.Gen[Array[T]] {
  @qc.sized(fn(size) {
    let len = if max_len <= 1 { 1 } else { size % (max_len - 1) + 1 }
    gen_array_len(len, gen)
  })
}

///|
fn dedup_node_ids(arr : Array[NodeId]) -> Array[NodeId] {
  let map : Map[NodeId, Unit] = {}
  for id in arr {
    map[id] = ()
  }
  let result = map.keys().to_array()
  result.sort()
  result
}

///|
fn gen_unique_node_ids(max_len : Int) -> @qc.Gen[Array[NodeId]] {
  gen_array_sized(max_len, gen_node_id()).fmap(dedup_node_ids)
}

///|
fn gen_cluster_config() -> @qc.Gen[ClusterConfig] {
  @qc.Gen::spawn()
}

///|
fn gen_config_with_voters(
  min_len : Int,
  max_len : Int,
) -> @qc.Gen[ClusterConfig] {
  gen_non_empty_array(max_len, gen_node_id())
  .fmap(dedup_node_ids)
  .such_that(fn(arr) { arr.length() >= min_len })
  .fmap(fn(arr) {
    let config = ClusterConfig::new()
    for id in arr {
      config.add_voter(id)
    }
    config
  })
}

///|
fn gen_config_with_voters_and_new(
  min_voters : Int,
  max_voters : Int,
  max_new : Int,
) -> @qc.Gen[ClusterConfig] {
  gen_config_with_voters(min_voters, max_voters).bind(fn(config) {
    @qc.frequency([
      (70, @qc.pure(config)),
      (
        30,
        gen_unique_node_ids(max_new).fmap(fn(news) {
          for id in news {
            config.add_new_voter(id)
          }
          config
        }),
      ),
    ])
  })
}

///|
fn gen_log_entry() -> @qc.Gen[LogEntry] {
  @qc.frequency([
    (3, gen_term().fmap(fn(term) { LogEntry::Term(term) })),
    (
      2,
      gen_cluster_config().fmap(fn(config) { LogEntry::ClusterConfig(config) }),
    ),
    (5, @qc.pure(LogEntry::Command)),
  ])
}

///|
fn gen_log_entries() -> @qc.Gen[LogEntries] {
  @qc.liftA2(
    fn(prev, entries) { LogEntries::from_array(prev, entries) },
    gen_log_position(),
    gen_array_sized(6, gen_log_entry()),
  )
}

///|
fn gen_log_entries_from_prev(prev : LogPosition) -> @qc.Gen[LogEntries] {
  gen_array_sized(6, gen_log_entry()).fmap(fn(entries) {
    LogEntries::from_array(prev, entries)
  })
}

///|
fn gen_message() -> @qc.Gen[Message] {
  let gen_from = gen_node_id()
  let gen_term = gen_term()
  @qc.frequency([
    (
      3,
      @qc.liftA3(
        fn(from, term, pos) { Message::request_vote_call(term, from, pos) },
        gen_from,
        gen_term,
        gen_log_position(),
      ),
    ),
    (
      3,
      @qc.liftA3(
        fn(from, term, granted) {
          Message::request_vote_reply(term, from, granted)
        },
        gen_from,
        gen_term,
        @qc.Gen::spawn(),
      ),
    ),
    (
      3,
      @qc.liftA4(
        fn(from, term, commit_index, entries) {
          Message::append_entries_call(term, from, commit_index, entries)
        },
        gen_from,
        gen_term,
        gen_log_index(),
        gen_log_entries(),
      ),
    ),
    (
      3,
      @qc.liftA4(
        fn(from, term, gen, pos) {
          Message::append_entries_reply(term, from, gen, pos)
        },
        gen_from,
        gen_term,
        gen_generation(),
        gen_log_position(),
      ),
    ),
  ])
}

///|
fn gen_action() -> @qc.Gen[Action] {
  @qc.frequency([
    (1, @qc.pure(Action::SetElectionTimeout)),
    (1, @qc.pure(Action::SaveCurrentTerm)),
    (1, @qc.pure(Action::SaveVotedFor)),
    (2, gen_message().fmap(fn(msg) { Action::BroadcastMessage(msg) })),
    (
      2,
      gen_log_entries().fmap(fn(entries) { Action::AppendLogEntries(entries) }),
    ),
    (
      2,
      @qc.liftA2(
        fn(prev, entry) { Action::AppendSingleLogEntry(prev, entry) },
        gen_log_position(),
        gen_log_entry(),
      ),
    ),
    (
      2,
      @qc.liftA2(
        fn(node_id, msg) { Action::SendMessage(node_id, msg) },
        gen_node_id(),
        gen_message(),
      ),
    ),
    (1, gen_node_id().fmap(fn(node_id) { Action::InstallSnapshot(node_id) })),
  ])
}
