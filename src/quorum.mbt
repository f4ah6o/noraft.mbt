///| Quorum tracks the progress of log replication to followers
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
  let mut i = 0
  for id in voters {
    if i < count {
      majority_indices.push((log_index_zero, id))
      i = i + 1
    }
  }
  let new_majority_indices : Array[(LogIndex, NodeId)] = []
  let new_voters = config.new_voters
  if not(new_voters.is_empty()) {
    let new_count = config.new_voter_majority_count().to_int()
    let mut j = 0
    for id in new_voters {
      if j < new_count {
        new_majority_indices.push((log_index_zero, id))
        j = j + 1
      }
    }
  }
  Quorum::{ majority_indices, new_majority_indices }
}

///| Updates the match index for a node.
pub fn Quorum::update_match_index(
  self : Quorum,
  config : ClusterConfig,
  node_id : NodeId,
  old_index : LogIndex,
  index : LogIndex
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

///| Returns the smallest index that has been replicated to a majority of nodes.
pub fn Quorum::smallest_majority_index(self : Quorum) -> LogIndex {
  let i0 = if self.majority_indices.is_empty() {
    // This should be unreachable: Quorum is constructed with at least one voter.
    panic()
  } else {
    self.majority_indices[0].0
  }
  if self.new_majority_indices.is_empty() {
    i0
  } else {
    let i1 = self.new_majority_indices[0].0
    if i0.get() < i1.get() { i0 } else { i1 }
  }
}

///|
fn Quorum::update_majority(
  self : Quorum,
  old_entry : (LogIndex, NodeId),
  new_entry : (LogIndex, NodeId)
) -> Unit {
  if self.majority_indices.is_empty() {
    return
  }
  let min = self.majority_indices[0]
  if new_entry.0.get() <= min.0.get() {
    return
  }
  self.majority_indices.push(new_entry)
  self.majority_indices.sort_by(fn(a, b) {
    let c = a.0.get().compare(b.0.get())
    if c == 0 { a.1.compare(b.1) } else { c }
  })
  // Remove old entry if present; otherwise remove the smallest entry.
  let old_idx = self.majority_indices.search_by(fn(x) { x == old_entry })
  match old_idx {
    Some(idx) => {
      let _ = self.majority_indices.remove(idx)
    }
    None => {
      let _ = self.majority_indices.remove(0)
    }
  }
}

///|
fn Quorum::update_majority_new(
  self : Quorum,
  old_entry : (LogIndex, NodeId),
  new_entry : (LogIndex, NodeId)
) -> Unit {
  if self.new_majority_indices.is_empty() {
    return
  }
  let min = self.new_majority_indices[0]
  if new_entry.0.get() <= min.0.get() {
    return
  }
  self.new_majority_indices.push(new_entry)
  self.new_majority_indices.sort_by(fn(a, b) {
    let c = a.0.get().compare(b.0.get())
    if c == 0 { a.1.compare(b.1) } else { c }
  })
  // Remove old entry if present; otherwise remove the smallest entry.
  let old_idx = self.new_majority_indices.search_by(fn(x) { x == old_entry })
  match old_idx {
    Some(idx) => {
      let _ = self.new_majority_indices.remove(idx)
    }
    None => {
      let _ = self.new_majority_indices.remove(0)
    }
  }
}
