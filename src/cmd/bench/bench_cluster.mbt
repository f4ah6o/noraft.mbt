///|
/// Bench-only cluster utilities (3-node, immediate delivery).
struct MessageQueue {
  items : Array[(@noraft.NodeId, @noraft.NodeId, @noraft.Message)]
  mut head : Int
}

///|
fn MessageQueue::new(capacity : Int) -> MessageQueue {
  let items : Array[(@noraft.NodeId, @noraft.NodeId, @noraft.Message)] = Array::new(
    capacity~,
  )
  MessageQueue::{ items, head: 0 }
}

///|
fn MessageQueue::clear(self : MessageQueue) -> Unit {
  self.items.clear()
  self.head = 0
}

///|
fn MessageQueue::push(
  self : MessageQueue,
  item : (@noraft.NodeId, @noraft.NodeId, @noraft.Message),
) -> Unit {
  self.items.push(item)
}

///|
fn MessageQueue::pop(
  self : MessageQueue,
) -> (@noraft.NodeId, @noraft.NodeId, @noraft.Message)? {
  match self.items.get(self.head) {
    None => {
      self.clear()
      None
    }
    Some(item) => {
      self.head = self.head + 1
      let len = self.items.length()
      if self.head >= 1024 && self.head * 2 >= len {
        let _ = self.items.drain(0, self.head)
        self.head = 0
      } else if self.head == len {
        self.clear()
      }
      Some(item)
    }
  }
}

///|
struct BenchCluster {
  nodes : Array[@noraft.Node]
  node_ids : Array[@noraft.NodeId]
  queue : MessageQueue
}

///|
fn BenchCluster::new_three() -> BenchCluster {
  let node_ids = [
    @noraft.NodeId::new(0),
    @noraft.NodeId::new(1),
    @noraft.NodeId::new(2),
  ]
  let nodes = node_ids.map(fn(id) { @noraft.Node::start(id) })
  BenchCluster::{ nodes, node_ids, queue: MessageQueue::new(256) }
}

///|
fn BenchCluster::leader_index(self : BenchCluster) -> Int? {
  self.nodes.search_by(fn(node) { node.role().is_leader() })
}

///|
fn BenchCluster::create_cluster(self : BenchCluster) -> Unit {
  let pos = self.nodes[0].create_cluster(self.node_ids)
  if pos.is_invalid() {
    @abort.abort("create_cluster failed")
  }
}

///|
fn node_index(id : @noraft.NodeId) -> Int {
  id.get().to_int()
}

///|
fn BenchCluster::drain_actions_into_queue(
  self : BenchCluster,
  idx : Int,
) -> Unit {
  let node = self.nodes[idx]
  let self_id = node.id()
  while true {
    match node.actions_mut().next() {
      Some(action) =>
        match action {
          @noraft.Action::BroadcastMessage(msg) =>
            for peer in self.node_ids {
              if peer != self_id {
                self.queue.push((self_id, peer, msg))
              }
            }
          @noraft.Action::SendMessage(dst, msg) =>
            self.queue.push((self_id, dst, msg))
          _ => ()
        }
      None => break
    }
  }
}

///|
fn BenchCluster::run_until_idle(self : BenchCluster, max_steps : Int) -> Unit {
  self.queue.clear()
  for i, _ in self.nodes {
    self.drain_actions_into_queue(i)
  }
  let mut steps = 0
  while true {
    match self.queue.pop() {
      None => break
      Some((_src, dst, msg)) => {
        let idx = node_index(dst)
        self.nodes[idx].handle_message(msg)
        self.drain_actions_into_queue(idx)
      }
    }
    if steps >= max_steps {
      @abort.abort("message loop exceeded max_steps")
    }
    steps = steps + 1
  }
}

///|
/// Drain all pending actions from a node.
fn drain_actions(node : @noraft.Node) -> Unit {
  while node.actions_mut().next() is Some(_) {

  }
}
