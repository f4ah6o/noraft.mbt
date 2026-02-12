///|
/// PBT for ClusterConfig.
fn expected_unique_voters(config : ClusterConfig) -> Array[NodeId] {
  let map : Map[NodeId, Unit] = {}
  for id in config.voters_ref() {
    map[id] = ()
  }
  for id in config.new_voters_ref() {
    map[id] = ()
  }
  let result = map.keys().to_array()
  result.sort()
  result
}

///|
test "PBT: ClusterConfig unique_voters returns sorted unique voters" {
  @qc.quick_check(
    @qc.forall(gen_cluster_config(), fn(config) {
      let unique = config.unique_voters()
      let expected = expected_unique_voters(config)
      unique.sort()
      expected.sort()
      unique == expected
    }),
  )
}

///|
test "PBT: ClusterConfig to_joint_consensus computes new_voters" {
  @qc.quick_check(
    @qc.forall(
      @qc.triple(
        gen_cluster_config(),
        gen_array_sized(6, gen_node_id()),
        gen_array_sized(6, gen_node_id()),
      ),
      fn(triple) {
        let (config, adding, removing) = triple
        let new_config = config.to_joint_consensus(adding, removing)
        let expected = config.voters_ref().copy()
        for id in adding {
          if not(expected.contains(id)) {
            expected.push(id)
          }
        }
        let expected_filtered = expected.filter(fn(id) {
          not(removing.contains(id))
        })
        let expected_sorted = expected_filtered
        expected_sorted.sort()
        let actual_sorted = new_config.new_voters_ref()
        actual_sorted.sort()
        new_config.voters_ref() == config.voters_ref() &&
        actual_sorted == expected_sorted
      },
    ),
  )
}

///|
test "PBT: ClusterConfig new_voter_majority_count matches size" {
  @qc.quick_check(
    @qc.forall(gen_cluster_config(), fn(config) {
      let expected = if config.new_voters_ref().is_empty() {
        0UL
      } else {
        config.new_voters_ref().length().to_uint64() / 2 + 1
      }
      config.new_voter_majority_count() == expected
    }),
  )
}
