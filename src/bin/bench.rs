use noraft::{Action, LogPosition, Message, Node, NodeId};
use std::collections::VecDeque;
use std::env;
use std::hint::black_box;
use std::time::Instant;

struct BenchConfig {
    micro_create_iters: usize,
    micro_propose_iters: usize,
    cluster_runs: usize,
    cluster_commands: usize,
}

impl BenchConfig {
    fn default() -> Self {
        Self {
            micro_create_iters: 10_000,
            micro_propose_iters: 100_000,
            cluster_runs: 5,
            cluster_commands: 100,
        }
    }
}

fn parse_usize_arg(arg: &str, prefix: &str) -> Option<usize> {
    arg.strip_prefix(prefix).and_then(|value| value.parse().ok())
}

fn parse_args() -> BenchConfig {
    let mut cfg = BenchConfig::default();
    for arg in env::args() {
        if let Some(v) = parse_usize_arg(&arg, "--micro-create-iters=") {
            cfg.micro_create_iters = v;
        }
        if let Some(v) = parse_usize_arg(&arg, "--micro-propose-iters=") {
            cfg.micro_propose_iters = v;
        }
        if let Some(v) = parse_usize_arg(&arg, "--cluster-runs=") {
            cfg.cluster_runs = v;
        }
        if let Some(v) = parse_usize_arg(&arg, "--cluster-commands=") {
            cfg.cluster_commands = v;
        }
    }
    cfg
}

struct BenchOutcome {
    scenario: &'static str,
    iters: usize,
    total_secs: f64,
    meta: Vec<(&'static str, f64)>,
}

fn bench_micro_create(iters: usize) -> BenchOutcome {
    let voters = [NodeId::new(0)];
    let start = Instant::now();
    for _ in 0..iters {
        let mut node = Node::start(NodeId::new(0));
        let _ = node.create_cluster(&voters);
        drain_actions(&mut node);
        black_box(&node);
    }
    BenchOutcome {
        scenario: "micro/create_cluster_single",
        iters,
        total_secs: start.elapsed().as_secs_f64(),
        meta: Vec::new(),
    }
}

fn bench_micro_propose(iters: usize) -> BenchOutcome {
    let voters = [NodeId::new(0)];
    let mut node = Node::start(NodeId::new(0));
    let _ = node.create_cluster(&voters);
    drain_actions(&mut node);
    if !node.role().is_leader() {
        node.handle_election_timeout();
        drain_actions(&mut node);
    }
    if !node.role().is_leader() {
        panic!("single-node cluster did not become leader");
    }

    let start = Instant::now();
    for _ in 0..iters {
        let pos = node.propose_command();
        black_box(pos);
        drain_actions(&mut node);
    }
    BenchOutcome {
        scenario: "micro/propose_command_single",
        iters,
        total_secs: start.elapsed().as_secs_f64(),
        meta: Vec::new(),
    }
}

struct BenchCluster {
    nodes: Vec<Node>,
}

impl BenchCluster {
    fn new_three() -> Self {
        let nodes = (0..3)
            .map(|id| Node::start(NodeId::new(id as u64)))
            .collect();
        Self { nodes }
    }

    fn create_cluster(&mut self) {
        let voters = [NodeId::new(0), NodeId::new(1), NodeId::new(2)];
        let pos = self.nodes[0].create_cluster(&voters);
        if pos == LogPosition::INVALID {
            panic!("create_cluster failed");
        }
    }

    fn leader_index(&self) -> Option<usize> {
        self.nodes.iter().position(|node| node.role().is_leader())
    }

    fn run_until_idle(&mut self, max_steps: usize) {
        let mut queue: VecDeque<(NodeId, NodeId, Message)> = VecDeque::new();
        for idx in 0..self.nodes.len() {
            drain_actions_to_queue(&mut self.nodes[idx], &mut queue);
        }

        let mut steps = 0usize;
        while let Some((_src, dst, msg)) = queue.pop_front() {
            if steps >= max_steps {
                panic!("message loop exceeded max_steps");
            }
            let idx = dst.get() as usize;
            self.nodes[idx].handle_message(&msg);
            drain_actions_to_queue(&mut self.nodes[idx], &mut queue);
            steps += 1;
        }
    }
}

fn drain_actions(node: &mut Node) {
    while node.actions_mut().next().is_some() {}
}

fn drain_actions_to_queue(
    node: &mut Node,
    queue: &mut VecDeque<(NodeId, NodeId, Message)>,
) {
    let node_id = node.id();
    let peers: Vec<NodeId> = node.peers().collect();
    while let Some(action) = node.actions_mut().next() {
        match action {
            Action::BroadcastMessage(msg) => {
                for peer in &peers {
                    queue.push_back((node_id, *peer, msg.clone()));
                }
            }
            Action::SendMessage(dst, msg) => {
                queue.push_back((node_id, dst, msg));
            }
            _ => {}
        }
    }
}

fn bench_cluster_commit(runs: usize, commands: usize) -> BenchOutcome {
    let total_iters = runs.saturating_mul(commands);
    let start = Instant::now();
    for _ in 0..runs {
        let mut cluster = BenchCluster::new_three();
        cluster.create_cluster();
        cluster.run_until_idle(100_000);
        let leader_idx = cluster
            .leader_index()
            .expect("no leader after cluster creation");

        for _ in 0..commands {
            let pos = cluster.nodes[leader_idx].propose_command();
            cluster.run_until_idle(100_000);
            if !cluster.nodes[leader_idx]
                .get_commit_status(pos)
                .is_committed()
            {
                panic!("commit did not finish");
            }
        }
    }
    BenchOutcome {
        scenario: "cluster/3node_commit",
        iters: total_iters,
        total_secs: start.elapsed().as_secs_f64(),
        meta: vec![
            ("nodes", 3.0),
            ("cluster_runs", runs as f64),
            ("cluster_commands", commands as f64),
        ],
    }
}

fn format_json_string(value: &str) -> String {
    let escaped = value
        .replace('\\', "\\\\")
        .replace('"', "\\\"");
    format!("\"{}\"", escaped)
}

fn meta_object(meta: &[(&'static str, f64)]) -> String {
    if meta.is_empty() {
        return "{}".to_string();
    }
    let mut parts = Vec::new();
    for (key, value) in meta {
        parts.push(format!("{}: {}", format_json_string(key), value));
    }
    format!("{{{}}}", parts.join(", "))
}

fn outcome_to_json(impl_name: &str, target: &str, outcome: &BenchOutcome) -> String {
    let ns_per_iter = if outcome.iters == 0 {
        0.0
    } else {
        outcome.total_secs * 1_000_000_000.0 / outcome.iters as f64
    };
    let fields = vec![
        format!("\"impl\": {}", format_json_string(impl_name)),
        format!("\"target\": {}", format_json_string(target)),
        format!("\"scenario\": {}", format_json_string(outcome.scenario)),
        format!("\"iters\": {}", outcome.iters),
        format!("\"total_secs\": {:.9}", outcome.total_secs),
        format!("\"ns_per_iter\": {:.3}", ns_per_iter),
        format!("\"meta\": {}", meta_object(&outcome.meta)),
    ];
    format!("{{{}}}", fields.join(", "))
}

fn main() {
    let cfg = parse_args();
    let outcomes = vec![
        bench_micro_create(cfg.micro_create_iters),
        bench_micro_propose(cfg.micro_propose_iters),
        bench_cluster_commit(cfg.cluster_runs, cfg.cluster_commands),
    ];
    let json_items: Vec<String> = outcomes
        .iter()
        .map(|outcome| outcome_to_json("rust", "rust", outcome))
        .collect();
    println!("[{}]", json_items.join(", "));
}
