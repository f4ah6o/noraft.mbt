///|
/// Quorum tracks the progress of log replication to followers
/// and determines when entries can be committed.
pub struct Quorum {
  majority_indices : Array[(LogIndex, NodeId)]
  new_majority_indices : Array[(LogIndex, NodeId)]
}

///|
pub fn Quorum::new(config : ClusterConfig) -> Quorum {
  let majority_indices : Array[(LogIndex, NodeId)] = []
  let voters = config.voters
  let count = config.voter_majority_count().to_int()
  for id in voters {
    if majority_indices.length() < count {
      majority_indices.push((log_index_zero, id))
    }
  }
  let new_majority_indices : Array[(LogIndex, NodeId)] = []
  let new_voters = config.new_voters
  if not(new_voters.is_empty()) {
    let new_count = config.new_voter_majority_count().to_int()
    for id in new_voters {
      if new_majority_indices.length() < new_count {
        new_majority_indices.push((log_index_zero, id))
      }
    }
  }
  Quorum::{ majority_indices, new_majority_indices }
}

///|
/// Updates the match index for a node.
pub fn Quorum::update_match_index(
  self : Quorum,
  config : ClusterConfig,
  node_id : NodeId,
  old_index : LogIndex,
  index : LogIndex,
) -> Unit {
  guard old_index.get() <= index.get() else { return }
  let old_entry = (old_index, node_id)
  let new_entry = (index, node_id)
  if config.voters.contains(node_id) {
    self.update_majority(old_entry, new_entry)
  }
  if config.new_voters.contains(node_id) {
    self.update_majority_new(old_entry, new_entry)
  }
}

///|
/// Returns the smallest index that has been replicated to a majority of nodes.
pub fn Quorum::smallest_majority_index(self : Quorum) -> LogIndex {
  match self.majority_indices {
    [] =>
      // This should be unreachable: Quorum is constructed with at least one voter.
      panic()
    [min0, ..] =>
      match self.new_majority_indices {
        [] => min0.0
        [min1, ..] => if min0.0.get() < min1.0.get() { min0.0 } else { min1.0 }
      }
  }
}

///|
fn update_majority_indices(
  indices : Array[(LogIndex, NodeId)],
  old_entry : (LogIndex, NodeId),
  new_entry : (LogIndex, NodeId),
) -> Unit {
  match indices {
    [] => return
    [min, ..] => if new_entry.0.get() <= min.0.get() { return } else { () }
  }
  indices.push(new_entry)
  indices.sort_by(fn(a, b) {
    let c = a.0.get().compare(b.0.get())
    if c == 0 {
      a.1.compare(b.1)
    } else {
      c
    }
  })
  // Remove old entry if present; otherwise remove the smallest entry.
  let old_idx = indices.search_by(fn(x) { x == old_entry })
  match old_idx {
    Some(idx) => {
      let _ = indices.remove(idx)
    }
    None => {
      let _ = indices.remove(0)
    }
  }
}

///|
fn Quorum::update_majority(
  self : Quorum,
  old_entry : (LogIndex, NodeId),
  new_entry : (LogIndex, NodeId),
) -> Unit {
  update_majority_indices(self.majority_indices, old_entry, new_entry)
}

///|
fn Quorum::update_majority_new(
  self : Quorum,
  old_entry : (LogIndex, NodeId),
  new_entry : (LogIndex, NodeId),
) -> Unit {
  update_majority_indices(self.new_majority_indices, old_entry, new_entry)
}
