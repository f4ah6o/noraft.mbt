///|
/// PBT for Role and CommitStatus.
fn gen_role() -> @qc.Gen[Role] {
  @qc.one_of([
    @qc.pure(Role::Follower),
    @qc.pure(Role::Candidate),
    @qc.pure(Role::Leader),
  ])
}

///|
fn gen_commit_status() -> @qc.Gen[CommitStatus] {
  @qc.one_of([
    @qc.pure(CommitStatus::InProgress),
    @qc.pure(CommitStatus::Committed),
    @qc.pure(CommitStatus::Rejected),
    @qc.pure(CommitStatus::Unknown),
  ])
}

///|
test "PBT: Role is_* functions are consistent" {
  @qc.quick_check(
    @qc.forall(gen_role(), fn(role) {
      match role {
        Follower =>
          role.is_follower() &&
          not(role.is_leader()) &&
          not(role.is_candidate())
        Candidate =>
          role.is_candidate() &&
          not(role.is_leader()) &&
          not(role.is_follower())
        Leader =>
          role.is_leader() &&
          not(role.is_follower()) &&
          not(role.is_candidate())
      }
    }),
  )
}

///|
test "PBT: CommitStatus is_* functions are consistent" {
  @qc.quick_check(
    @qc.forall(gen_commit_status(), fn(status) {
      match status {
        InProgress =>
          status.is_in_progress() &&
          not(status.is_committed()) &&
          not(status.is_rejected()) &&
          not(status.is_unknown())
        Committed =>
          status.is_committed() &&
          not(status.is_in_progress()) &&
          not(status.is_rejected()) &&
          not(status.is_unknown())
        Rejected =>
          status.is_rejected() &&
          not(status.is_in_progress()) &&
          not(status.is_committed()) &&
          not(status.is_unknown())
        Unknown =>
          status.is_unknown() &&
          not(status.is_in_progress()) &&
          not(status.is_committed()) &&
          not(status.is_rejected())
      }
    }),
  )
}
