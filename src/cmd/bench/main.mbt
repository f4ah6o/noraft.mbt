///| Bench configuration.
struct BenchConfig {
  mut micro_create_iters : Int
  mut micro_propose_iters : Int
  mut cluster_runs : Int
  mut cluster_commands : Int
  mut target : String
}

///|
fn BenchConfig::default() -> BenchConfig {
  BenchConfig::{
    micro_create_iters: 10_000,
    micro_propose_iters: 100_000,
    cluster_runs: 5,
    cluster_commands: 100,
    target: "native",
  }
}

///|
fn parse_int_arg(arg : String, prefix : String) -> Int? {
  if not(arg.has_prefix(prefix)) {
    return None
  }
  let view = try! arg[prefix.length():]
  let parsed : Result[Int, Error] = try? @strconv.parse_int(view)
  match parsed {
    Ok(value) => Some(value)
    _ => None
  }
}

///|
fn parse_string_arg(arg : String, prefix : String) -> String? {
  if not(arg.has_prefix(prefix)) {
    return None
  }
  let view = try! arg[prefix.length():]
  Some(view.to_string())
}

///|
fn parse_args(args : Array[String]) -> BenchConfig {
  let cfg = BenchConfig::default()
  for arg in args {
    match parse_int_arg(arg, "--micro-create-iters=") {
      Some(v) => cfg.micro_create_iters = v
      _ => ()
    }
    match parse_int_arg(arg, "--micro-propose-iters=") {
      Some(v) => cfg.micro_propose_iters = v
      _ => ()
    }
    match parse_int_arg(arg, "--cluster-runs=") {
      Some(v) => cfg.cluster_runs = v
      _ => ()
    }
    match parse_int_arg(arg, "--cluster-commands=") {
      Some(v) => cfg.cluster_commands = v
      _ => ()
    }
    match parse_string_arg(arg, "--target=") {
      Some(v) => cfg.target = v
      _ => ()
    }
  }
  cfg
}

///| Converts microseconds to seconds.
fn micros_to_secs(elapsed_micros : Double) -> Double {
  elapsed_micros / 1_000_000.0
}

///| Computes ns/iter from total seconds and iteration count.
fn calc_ns_per_iter(total_secs : Double, iters : Int) -> Double {
  if iters <= 0 {
    0.0
  } else {
    total_secs * 1_000_000_000.0 / iters.to_double()
  }
}

///|
fn outcome_to_json(
  impl_name : String,
  target : String,
  outcome : BenchOutcome
) -> Json {
  let iters = outcome.iters
  let total_secs = outcome.total_secs
  let ns_per_iter = calc_ns_per_iter(total_secs, iters)
  let obj : Map[String, Json] = Map::new()
  obj["impl"] = Json::string(impl_name)
  obj["target"] = Json::string(target)
  obj["scenario"] = Json::string(outcome.scenario)
  obj["iters"] = Json::number(iters.to_double())
  obj["total_secs"] = Json::number(total_secs)
  obj["ns_per_iter"] = Json::number(ns_per_iter)
  obj["meta"] = Json::object(outcome.meta)
  Json::object(obj)
}

///|
fn main {
  let cfg = parse_args(@env.args())
  let results : Array[BenchOutcome] = [
    bench_micro_create(cfg.micro_create_iters),
    bench_micro_propose(cfg.micro_propose_iters),
    bench_cluster_commit(cfg.cluster_runs, cfg.cluster_commands),
  ]
  let json_results : Array[Json] = []
  for outcome in results {
    json_results.push(outcome_to_json("moonbit", cfg.target, outcome))
  }
  let output = Json::array(json_results).stringify(indent=2)
  println(output)
}
