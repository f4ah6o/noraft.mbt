///| PBT for Quorum.

fn gen_quorum_config() -> @qc.Gen[ClusterConfig] {
  gen_config_with_voters_and_new(1, 6, 4)
}

test "PBT: Quorum smallest_majority_index starts at zero" {
  @qc.quick_check(
    @qc.forall(gen_quorum_config(), fn(config) {
      let quorum = Quorum::new(config)
      quorum.smallest_majority_index() == log_index_zero
    })
  )
}

test "PBT: Quorum smallest_majority_index is non-decreasing on updates" {
  @qc.quick_check(
    @qc.forall(gen_quorum_config(), fn(config) {
      let voters = config.voters_ref()
      @qc.forall(@qc.one_of_array(voters), fn(node_id) {
        @qc.forall(gen_log_index(), fn(new_index) {
          let quorum = Quorum::new(config)
          let before = quorum.smallest_majority_index()
          quorum.update_match_index(config, node_id, log_index_zero, new_index)
          let after = quorum.smallest_majority_index()
          after.get() >= before.get()
        })
      })
    })
  )
}

test "PBT: Quorum ignores nodes outside config" {
  @qc.quick_check(
    @qc.forall(gen_quorum_config(), fn(config) {
      @qc.forall(gen_node_id().such_that(fn(id) { not(config.contains(id)) }), fn(other) {
        let quorum = Quorum::new(config)
        let before = quorum.smallest_majority_index()
        quorum.update_match_index(config, other, log_index_zero, LogIndex::new(10))
        let after = quorum.smallest_majority_index()
        after == before
      })
    })
  )
}
