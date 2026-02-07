///| PBT for LogEntries and Log.

fn positions_from(prev : LogPosition, entries : Array[LogEntry]) -> Array[LogPosition] {
  let mut term = prev.get_term()
  let mut index = prev.get_index().get() + 1
  let result = []
  for entry in entries {
    match entry {
      Term(t) => term = t
      _ => ()
    }
    let pos = LogPosition::new(term, LogIndex::new(index))
    result.push(pos)
    index = index + 1
  }
  result
}

fn latest_config_from(snapshot : ClusterConfig, entries : Array[LogEntry]) -> ClusterConfig {
  let mut latest = snapshot
  for entry in entries {
    match entry {
      ClusterConfig(config) => latest = config
      _ => ()
    }
  }
  latest
}

fn latest_config_index_from(
  prev_index : LogIndex,
  entries : Array[LogEntry],
  positions : Array[LogPosition]
) -> LogIndex {
  let mut latest = prev_index
  for i, entry in entries {
    match entry {
      ClusterConfig(_) => latest = positions[i].get_index()
      _ => ()
    }
  }
  latest
}

fn config_at_index(
  snapshot : ClusterConfig,
  prev_index : LogIndex,
  positions : Array[LogPosition],
  entries : Array[LogEntry],
  index : LogIndex
) -> ClusterConfig? {
  if index.get() < prev_index.get() {
    return None
  }
  if entries.is_empty() {
    if index == prev_index {
      return Some(snapshot)
    }
    return None
  }
  let last_index = positions[positions.length() - 1].get_index()
  if index.get() > last_index.get() {
    return None
  }
  let mut latest = snapshot
  for i, entry in entries {
    if positions[i].get_index().get() <= index.get() {
      match entry {
        ClusterConfig(config) => latest = config
        _ => ()
      }
    }
  }
  Some(latest)
}

fn suffix_entries(entries : Array[LogEntry], offset : Int) -> Array[LogEntry] {
  let result = []
  for i in offset..<entries.length() {
    result.push(entries[i])
  }
  result
}

test "PBT: LogEntries from_array round-trips to_array" {
  @qc.quick_check(
    @qc.forall(@qc.tuple(gen_log_position(), gen_array_sized(6, gen_log_entry())), fn(pair) {
      let (prev, entries) = pair
      let log_entries = LogEntries::from_array(prev, entries)
      log_entries.to_array() == entries
    })
  )
}

test "PBT: LogEntries len and is_empty are consistent" {
  @qc.quick_check(
    @qc.forall(gen_log_entries(), fn(log_entries) {
      let entries = log_entries.to_array()
      let len = log_entries.len()
      let expected_len = entries.length().to_uint64()
      len == expected_len && log_entries.is_empty() == (expected_len == 0)
    })
  )
}

test "PBT: LogEntries contains_index matches range" {
  @qc.quick_check(
    @qc.forall(@qc.tuple(gen_log_entries(), gen_log_index()), fn(pair) {
      let (log_entries, index) = pair
      let prev = log_entries.prev_position().get_index()
      let last = log_entries.last_position().get_index()
      let expected =
        index.get() >= prev.get() && index.get() <= last.get()
      log_entries.contains_index(index) == expected
    })
  )
}

test "PBT: LogEntries get_entry matches to_array" {
  @qc.quick_check(
    @qc.forall(@qc.tuple(gen_log_entries(), gen_log_index()), fn(pair) {
      let (log_entries, index) = pair
      let prev = log_entries.prev_position().get_index().get()
      let last = log_entries.last_position().get_index().get()
      let entries = log_entries.to_array()
      if index.get() <= prev || index.get() > last {
        log_entries.get_entry(index) is None
      } else {
        let offset = (index.get() - prev - 1).to_int()
        match log_entries.get_entry(index) {
          Some(entry) => entry == entries[offset]
          None => false
        }
      }
    })
  )
}

test "PBT: LogEntries to_array_with_positions is consistent" {
  @qc.quick_check(
    @qc.forall(gen_log_entries(), fn(log_entries) {
      let entries = log_entries.to_array()
      let positions = positions_from(log_entries.prev_position(), entries)
      let with_pos = log_entries.to_array_with_positions()
      if entries.length() != with_pos.length() {
        return false
      }
      for i in 0..<with_pos.length() {
        let (pos, entry) = with_pos[i]
        if entry != entries[i] {
          return false
        }
        if pos != positions[i] {
          return false
        }
      }
      true
    })
  )
}

test "PBT: LogEntries truncate keeps prefix" {
  @qc.quick_check(
    @qc.forall(@qc.tuple(gen_log_entries(), @qc.int_range(0, 8)), fn(pair) {
      let (log_entries, len) = pair
      let expected = log_entries.to_array()
      let truncated = log_entries
      truncated.truncate(len.to_uint64())
      let truncated_entries = truncated.to_array()
      let keep = if len < expected.length() { len } else { expected.length() }
      if truncated_entries.length() != keep {
        return false
      }
      for i in 0..<keep {
        if truncated_entries[i] != expected[i] {
          return false
        }
      }
      true
    })
  )
}

test "PBT: LogEntries since returns suffix when position is contained" {
  @qc.quick_check(
    @qc.forall(gen_log_entries(), fn(log_entries) {
      let entries = log_entries.to_array()
      let positions = positions_from(log_entries.prev_position(), entries)
      let len = entries.length()
      @qc.forall(@qc.int_range(0, len + 1), fn(offset) {
        let pos =
          if offset == 0 {
            log_entries.prev_position()
          } else {
            positions[offset - 1]
          }
        match log_entries.since(pos) {
          Some(since_entries) => {
            let expected = if offset == len { [] } else { suffix_entries(entries, offset) }
            since_entries.to_array() == expected
          }
          None => false
        }
      })
    })
  )
}

test "LogEntries strip_common_prefix uses previous term on divergence" {
  let prev = log_position_zero
  let local_entries = LogEntries::from_array(
    prev,
    [
      LogEntry::Term(Term::new(0)),
      LogEntry::Term(Term::new(1)),
      LogEntry::Command,
    ],
  )
  let remote_entries = LogEntries::from_array(
    prev,
    [
      LogEntry::Term(Term::new(0)),
      LogEntry::Term(Term::new(2)),
      LogEntry::Command,
    ],
  )
  let stripped = remote_entries.strip_common_prefix(local_entries)
  inspect(stripped.to_array(), content="[Term(2), Command]")
}

test "PBT: LogEntries handle_snapshot_installed keeps positions consistent" {
  @qc.quick_check(
    @qc.forall(@qc.tuple(gen_log_entries(), gen_log_position()), fn(pair) {
      let (entries, snapshot_pos) = pair
      let before = entries.prev_position()
      entries.handle_snapshot_installed(snapshot_pos)
      let after = entries.prev_position()
      after.get_index().get() >= before.get_index().get() ||
      snapshot_pos.get_index().get() < before.get_index().get()
    })
  )
}

test "LogEntries truncate/append keeps term/config boundary semantics" {
  let base = LogEntries::from_array(
    log_position_zero,
    [
      LogEntry::Term(Term::new(1)),
      LogEntry::ClusterConfig(ClusterConfig::new()),
      LogEntry::Command,
      LogEntry::Term(Term::new(2)),
      LogEntry::Command,
    ],
  )
  base.truncate(3)
  inspect(
    base.to_array(),
    content=
      "[Term(1), ClusterConfig(ClusterConfig { voters=[], new_voters=[], non_voters=[] }), Command]",
  )

  let extra = LogEntries::from_array(
    LogPosition::new(Term::new(1), LogIndex::new(2)),
    [LogEntry::Command, LogEntry::Term(Term::new(9))],
  )
  base.append(extra)
  inspect(
    base.to_array(),
    content=
      "[Term(1), ClusterConfig(ClusterConfig { voters=[], new_voters=[], non_voters=[] }), Command, Term(9)]",
  )
}

test "PBT: LogEntries since returns None when position is not contained" {
  @qc.quick_check(
    @qc.forall(gen_log_entries(), fn(log_entries) {
      let last = log_entries.last_position()
      let invalid = last.next()
      log_entries.since(invalid) is None
    })
  )
}

test "PBT: Log latest_config and index match entries" {
  @qc.quick_check(
    @qc.forall(@qc.tuple(gen_cluster_config(), gen_log_entries()), fn(pair) {
      let (snapshot, entries) = pair
      let log = Log::new(snapshot, entries)
      let entries_arr = log.get_entries().to_array()
      let positions = positions_from(log.get_entries().prev_position(), entries_arr)
      let expected_config = latest_config_from(log.snapshot_config(), entries_arr)
      let expected_index =
        latest_config_index_from(log.get_entries().prev_position().get_index(), entries_arr, positions)
      log.latest_config() == expected_config &&
      log.latest_config_index() == expected_index
    })
  )
}

test "PBT: Log get_config/get_position_and_config are consistent" {
  @qc.quick_check(
    @qc.forall(@qc.triple(gen_cluster_config(), gen_log_entries(), gen_log_index()), fn(triple) {
      let (snapshot, entries, index) = triple
      let log = Log::new(snapshot, entries)
      let entries_arr = log.get_entries().to_array()
      let prev_index = log.get_entries().prev_position().get_index()
      let positions = positions_from(log.get_entries().prev_position(), entries_arr)
      let expected = config_at_index(snapshot, prev_index, positions, entries_arr, index)
      match log.get_config(index) {
        Some(config) =>
          match expected {
            Some(exp) => {
              if config != exp {
                return false
              }
              match log.get_position_and_config(index) {
                Some((pos, config2)) =>
                  pos.get_index() == index && config2 == exp
                None => false
              }
            }
            None => false
          }
        None => expected is None
      }
    })
  )
}
