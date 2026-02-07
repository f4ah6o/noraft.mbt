///| Cluster configuration (membership).
pub struct ClusterConfig {
  /// Voting nodes.
  voters : @sorted_set.SortedSet[NodeId]
  /// New voting nodes during joint consensus.
  new_voters : @sorted_set.SortedSet[NodeId]
  /// Non-voting nodes.
  non_voters : @sorted_set.SortedSet[NodeId]
}

///|
pub fn ClusterConfig::new() -> ClusterConfig {
  ClusterConfig::{
    voters: @sorted_set.SortedSet::new(),
    new_voters: @sorted_set.SortedSet::new(),
    non_voters: @sorted_set.SortedSet::new(),
  }
}

///| Adds a voter to the configuration.
pub fn ClusterConfig::add_voter(self : ClusterConfig, id : NodeId) -> Unit {
  self.voters.add(id)
}

///| Adds a new voter to the configuration.
pub fn ClusterConfig::add_new_voter(self : ClusterConfig, id : NodeId) -> Unit {
  self.new_voters.add(id)
}

///| Adds a non-voter to the configuration.
pub fn ClusterConfig::add_non_voter(self : ClusterConfig, id : NodeId) -> Unit {
  self.non_voters.add(id)
}

///| Removes a voter from the configuration.
pub fn ClusterConfig::remove_voter(self : ClusterConfig, id : NodeId) -> Unit {
  self.voters.remove(id)
}

///| Removes a new voter from the configuration.
pub fn ClusterConfig::remove_new_voter(self : ClusterConfig, id : NodeId) -> Unit {
  self.new_voters.remove(id)
}

///| Removes a non-voter from the configuration.
pub fn ClusterConfig::remove_non_voter(self : ClusterConfig, id : NodeId) -> Unit {
  self.non_voters.remove(id)
}

///| Returns `true` if the given node is in this configuration.
pub fn ClusterConfig::contains(self : ClusterConfig, id : NodeId) -> Bool {
  self.voters.contains(id) ||
  self.new_voters.contains(id) ||
  self.non_voters.contains(id)
}

///| Returns `true` if this configuration represents a joint consensus state.
pub fn ClusterConfig::is_joint_consensus(self : ClusterConfig) -> Bool {
  not(self.new_voters.is_empty())
}

///| Gets an array of all unique NodeIds in this configuration, in sorted order.
pub fn ClusterConfig::unique_nodes(self : ClusterConfig) -> Array[NodeId] {
  let result = self.voters.to_array()
  for id in self.new_voters {
    if not(self.voters.contains(id)) {
      result.push(id)
    }
  }
  for id in self.non_voters {
    if not(self.voters.contains(id)) && not(self.new_voters.contains(id)) {
      result.push(id)
    }
  }
  result.sort()
  result
}

///|
fn ClusterConfig::unique_voters(self : ClusterConfig) -> Array[NodeId] {
  let result = self.voters.to_array()
  for id in self.new_voters {
    if not(self.voters.contains(id)) {
      result.push(id)
    }
  }
  result.sort()
  result
}

///|
pub fn ClusterConfig::is_voter(self : ClusterConfig, id : NodeId) -> Bool {
  self.voters.contains(id) || self.new_voters.contains(id)
}

///| Converts this configuration to a joint consensus by adding and removing voters.
pub fn ClusterConfig::to_joint_consensus(
  self : ClusterConfig,
  adding_voters : Array[NodeId],
  removing_voters : Array[NodeId]
) -> ClusterConfig {
  let new_voters = self.voters.copy()
  for id in adding_voters {
    new_voters.add(id)
  }
  for id in removing_voters {
    new_voters.remove(id)
  }
  ClusterConfig::{
    voters: self.voters.copy(),
    new_voters,
    non_voters: self.non_voters.copy(),
  }
}

///|
fn ClusterConfig::voter_majority_count(self : ClusterConfig) -> UInt64 {
  let len = self.voters.length().to_uint64()
  len / 2 + 1
}

///|
fn ClusterConfig::new_voter_majority_count(self : ClusterConfig) -> UInt64 {
  if self.new_voters.is_empty() {
    0
  } else {
    let len = self.new_voters.length().to_uint64()
    len / 2 + 1
  }
}

///| Returns a copy of voters as an array.
pub fn ClusterConfig::voters_ref(self : ClusterConfig) -> Array[NodeId] {
  self.voters.to_array()
}

///| Returns a copy of new_voters as an array.
pub fn ClusterConfig::new_voters_ref(
  self : ClusterConfig
) -> Array[NodeId] {
  self.new_voters.to_array()
}

///| Returns a copy of non_voters as an array.
pub fn ClusterConfig::non_voters_ref(
  self : ClusterConfig
) -> Array[NodeId] {
  self.non_voters.to_array()
}

///| Eq implementation for ClusterConfig
pub impl Eq for ClusterConfig with equal(self, other) -> Bool {
  self.voters == other.voters &&
  self.new_voters == other.new_voters &&
  self.non_voters == other.non_voters
}

///| Show implementation for ClusterConfig
pub impl Show for ClusterConfig with output(self, logger) {
  logger.write_string("ClusterConfig { voters=[")
  for i, id in self.voters.to_array() {
    if i > 0 {
      logger.write_string(", ")
    }
    id.output(logger)
  }
  logger.write_string("], new_voters=[")
  for i, id in self.new_voters.to_array() {
    if i > 0 {
      logger.write_string(", ")
    }
    id.output(logger)
  }
  logger.write_string("], non_voters=[")
  for i, id in self.non_voters.to_array() {
    if i > 0 {
      logger.write_string(", ")
    }
    id.output(logger)
  }
  logger.write_string("] }")
}

// PBT: ClusterConfig
// ==================

///| Arbitrary implementation for ClusterConfig
pub impl @moonbitlang/core/quickcheck.Arbitrary for ClusterConfig with arbitrary(size, rs) {
  let voters = @sorted_set.SortedSet::new()
  let new_voters = @sorted_set.SortedSet::new()
  let non_voters = @sorted_set.SortedSet::new()
  let voter_count = size % 5
  let new_voter_count = (size / 5) % 3
  let non_voter_count = (size / 15) % 3
  for i in 0..<voter_count {
    voters.add(NodeId::new(rs.next_uint64()))
  }
  for i in 0..<new_voter_count {
    new_voters.add(NodeId::new(rs.next_uint64()))
  }
  for i in 0..<non_voter_count {
    non_voters.add(NodeId::new(rs.next_uint64()))
  }
  ClusterConfig::{ voters, new_voters, non_voters }
}

///| Shrink implementation for ClusterConfig
pub impl @moonbitlang/quickcheck.Shrink for ClusterConfig with shrink(self) {
  let result : Array[ClusterConfig] = []
  // Shrink by removing one element from voters
  if not(self.voters.is_empty()) {
    for i in 0..<self.voters.length() {
      let shrunk = ClusterConfig::new()
      let voters = self.voters.to_array()
      for j, v in voters {
        if i != j {
          shrunk.add_voter(v)
        }
      }
      for v in self.new_voters {
        shrunk.add_new_voter(v)
      }
      for v in self.non_voters {
        shrunk.add_non_voter(v)
      }
      result.push(shrunk)
    }
  }
  // Shrink by removing all new_voters
  if not(self.new_voters.is_empty()) {
    let shrunk = ClusterConfig::new()
    for v in self.voters {
      shrunk.add_voter(v)
    }
    for v in self.non_voters {
      shrunk.add_non_voter(v)
    }
    result.push(shrunk)
  }
  result.iter()
}

test "PBT: ClusterConfig contains works correctly" {
  @qc.quick_check_fn(fn(id : NodeId) {
    let config2 = ClusterConfig::new()
    config2.add_voter(id)
    config2.add_voter(NodeId::new(999))
    config2.contains(id)
  })
}

test "PBT: ClusterConfig is_joint_consensus is consistent with new_voters" {
  @qc.quick_check_fn(fn(config : ClusterConfig) {
    config.is_joint_consensus() == not(config.new_voters_ref().is_empty())
  })
}

test "PBT: ClusterConfig unique_nodes returns sorted unique nodes" {
  @qc.quick_check_fn(fn(config : ClusterConfig) {
    let unique = config.unique_nodes()
    // Check sorted
    for i in 1..<unique.length() {
      if unique[i - 1].compare(unique[i]) > 0 {
        return false
      }
    }
    // Check uniqueness
    for i in 0..<unique.length() {
      for j in (i + 1)..<unique.length() {
        if unique[i] == unique[j] {
          return false
        }
      }
    }
    true
  })
}

test "PBT: ClusterConfig is_voter is consistent with voters and new_voters" {
  @qc.quick_check_fn(fn(pair : (ClusterConfig, NodeId)) {
    let (config, id) = pair
    let is_voter = config.is_voter(id)
    let in_voters = config.voters_ref().contains(id)
    let in_new_voters = config.new_voters_ref().contains(id)
    is_voter == (in_voters || in_new_voters)
  })
}

test "PBT: ClusterConfig voter_majority_count calculation" {
  @qc.quick_check_fn(fn(config : ClusterConfig) {
    let expected = if config.voters_ref().is_empty() {
      1UL
    } else {
      config.voters_ref().length().to_uint64() / 2 + 1
    }
    config.voter_majority_count() == expected
  })
}
