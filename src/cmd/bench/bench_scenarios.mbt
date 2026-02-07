///| Benchmark outcome.
struct BenchOutcome {
  scenario : String
  iters : Int
  total_secs : Double
  meta : Map[String, Json]
}

///|
fn BenchOutcome::new(
  scenario : String,
  iters : Int,
  total_secs : Double
) -> BenchOutcome {
  BenchOutcome::{ scenario, iters, total_secs, meta: Map::new() }
}

///|
fn bench_micro_create(iters : Int) -> BenchOutcome {
  let node_id = @noraft.NodeId::new(0)
  let voters = [node_id]
  let start = @bench_core.monotonic_clock_start()
  for _ in 0..<iters {
    let node = @noraft.Node::start(node_id)
    let _ = node.create_cluster(voters)
    drain_actions(node)
  }
  let elapsed_micros = @bench_core.monotonic_clock_end(start)
  let elapsed_secs = micros_to_secs(elapsed_micros)
  BenchOutcome::new("micro/create_cluster_single", iters, elapsed_secs)
}

///|
fn bench_micro_propose(iters : Int) -> BenchOutcome {
  let node_id = @noraft.NodeId::new(0)
  let voters = [node_id]
  let node = @noraft.Node::start(node_id)
  let _ = node.create_cluster(voters)
  drain_actions(node)
  if not(node.role().is_leader()) {
    node.handle_election_timeout()
    drain_actions(node)
  }
  if not(node.role().is_leader()) {
    @abort.abort("single-node cluster did not become leader")
  }

  let start = @bench_core.monotonic_clock_start()
  for _ in 0..<iters {
    let _ = node.propose_command()
    drain_actions(node)
  }
  let elapsed_micros = @bench_core.monotonic_clock_end(start)
  let elapsed_secs = micros_to_secs(elapsed_micros)
  BenchOutcome::new("micro/propose_command_single", iters, elapsed_secs)
}

///|
fn bench_cluster_commit(runs : Int, commands : Int) -> BenchOutcome {
  let run_count = if runs < 0 { 0 } else { runs }
  let command_count = if commands < 0 { 0 } else { commands }
  let total_iters = run_count * command_count

  let start = @bench_core.monotonic_clock_start()
  for _ in 0..<run_count {
    let cluster = BenchCluster::new_three()
    cluster.create_cluster()
    cluster.run_until_idle(100_000)
    let leader_idx = match cluster.leader_index() {
      Some(i) => i
      None => @abort.abort("no leader after cluster creation")
    }
    for _ in 0..<command_count {
      let pos = cluster.nodes[leader_idx].propose_command()
      cluster.run_until_idle(100_000)
      if not(cluster.nodes[leader_idx].get_commit_status(pos).is_committed()) {
        @abort.abort("commit did not finish")
      }
    }
  }
  let elapsed_micros = @bench_core.monotonic_clock_end(start)
  let elapsed_secs = micros_to_secs(elapsed_micros)
  let result = BenchOutcome::new("cluster/3node_commit", total_iters, elapsed_secs)
  result.meta["nodes"] = Json::number(3.0)
  result.meta["cluster_runs"] = Json::number(runs.to_double())
  result.meta["cluster_commands"] = Json::number(commands.to_double())
  result
}
