test "Node basic operations" {
  // Create a node
  let node = Node::start(NodeId::new(1))

  // Check initial state
  inspect(node.id(), content="1")
  inspect(node.current_term(), content="0")
  inspect(node.commit_index(), content="0")
}

test "ClusterConfig operations" {
  let config = ClusterConfig::new()

  // Initially empty
  inspect(config.voters_ref().is_empty(), content="true")
  inspect(config.new_voters_ref().is_empty(), content="true")
  inspect(config.non_voters_ref().is_empty(), content="true")

  // Add voters
  config.add_voter(NodeId::new(1))
  config.add_voter(NodeId::new(2))
  inspect(config.voters_ref().length(), content="2")
  inspect(config.contains(NodeId::new(1)), content="true")
  inspect(config.is_voter(NodeId::new(1)), content="true")
}

test "LogPosition operations" {
  let pos1 = LogPosition::new(Term::new(1), LogIndex::new(5))
  inspect(pos1.get_term(), content="1")
  inspect(pos1.get_index(), content="5")
}

test "Actions operations" {
  let actions = Actions::new()
  inspect(actions.is_empty(), content="true")
}

test "Compatibility helpers" {
  inspect(Term::zero().get(), content="0")
  inspect(LogIndex::zero().get(), content="0")
  let pos0 = LogPosition::zero()
  assert_true(not(pos0.is_invalid()))
  let invalid = LogPosition::invalid()
  assert_true(invalid.is_invalid())

  let entries = LogEntries::new(LogPosition::zero())
  inspect(entries.iter().count(), content="0")
  inspect(entries.iter_with_positions().count(), content="0")
  let from_iter = LogEntries::from_iter(LogPosition::zero(), [])
  inspect(from_iter.len(), content="0")

  let log = Log::new(ClusterConfig::new(), LogEntries::new(LogPosition::zero()))
  inspect(log.entries().len(), content="0")

  let actions = Actions::new()
  inspect(actions.iter().count(), content="0")
  let actions2 = Actions::new()
  inspect(actions2.into_iter().count(), content="0")
}

// PBT: Basic Types - NodeId
// ========================

test "PBT: NodeId equality is reflexive" {
  @qc.quick_check_fn(fn(id : NodeId) { id == id })
}

test "PBT: NodeId round-trip through get/new" {
  @qc.quick_check_fn(fn(id : NodeId) { NodeId::new(id.get()) == id })
}

test "PBT: NodeId from/to uint64 round-trip" {
  @qc.quick_check_fn(fn(id : NodeId) { NodeId::from_uint64(id.to_uint64()) == id })
}

// PBT: Basic Types - Term
// =======================

test "PBT: Term equality is reflexive" {
  @qc.quick_check_fn(fn(term : Term) { term == term })
}

test "PBT: Term round-trip through get/new" {
  @qc.quick_check_fn(fn(term : Term) { Term::new(term.get()) == term })
}

test "PBT: Term from/to uint64 round-trip" {
  @qc.quick_check_fn(fn(term : Term) { Term::from_uint64(term.to_uint64()) == term })
}


test "PBT: Term comparison is consistent" {
  @qc.quick_check_fn(fn(pair : (Term, Term)) {
    let (a, b) = pair
    let cmp1 = a.compare(b)
    let cmp2 = b.compare(a)
    (cmp1 == cmp2.neg()) || (a == b && cmp1 == 0)
  })
}

// PBT: Basic Types - LogIndex
// ===========================

test "PBT: LogIndex equality is reflexive" {
  @qc.quick_check_fn(fn(index : LogIndex) { index == index })
}

test "PBT: LogIndex round-trip through get/new" {
  @qc.quick_check_fn(fn(index : LogIndex) {
    LogIndex::new(index.get()) == index
  })
}

test "PBT: LogIndex from/to uint64 round-trip" {
  @qc.quick_check_fn(fn(index : LogIndex) {
    LogIndex::from_uint64(index.to_uint64()) == index
  })
}


test "PBT: LogIndex comparison is consistent" {
  @qc.quick_check_fn(fn(pair : (LogIndex, LogIndex)) {
    let (a, b) = pair
    let cmp1 = a.compare(b)
    let cmp2 = b.compare(a)
    (cmp1 == cmp2.neg()) || (a == b && cmp1 == 0)
  })
}

// PBT: Basic Types - LogPosition
// ==============================

test "PBT: LogPosition equality is reflexive" {
  @qc.quick_check_fn(fn(pos : LogPosition) { pos == pos })
}


test "PBT: LogPosition get_term/get_index are consistent with constructor" {
  @qc.quick_check_fn(fn(pair : (Term, LogIndex)) {
    let (term, index) = pair
    let pos = LogPosition::new(term, index)
    pos.get_term() == term && pos.get_index() == index
  })
}

test "PBT: LogPosition comparison is consistent" {
  @qc.quick_check_fn(fn(pair : (LogPosition, LogPosition)) {
    let (a, b) = pair
    let cmp1 = a.compare(b)
    let cmp2 = b.compare(a)
    (cmp1 == cmp2.neg()) || (a == b && cmp1 == 0)
  })
}

// PBT: Basic Types - NodeGeneration
// =================================

test "PBT: NodeGeneration equality is reflexive" {
  @qc.quick_check_fn(fn(gen : NodeGeneration) { gen == gen })
}

test "PBT: NodeGeneration round-trip through get/new" {
  @qc.quick_check_fn(fn(gen : NodeGeneration) {
    NodeGeneration::new(gen.get()) == gen
  })
}

test "PBT: NodeGeneration from/to uint64 round-trip" {
  @qc.quick_check_fn(fn(gen : NodeGeneration) {
    NodeGeneration::from_uint64(gen.to_uint64()) == gen
  })
}

test "PBT: NodeGeneration comparison is consistent" {
  @qc.quick_check_fn(fn(pair : (NodeGeneration, NodeGeneration)) {
    let (a, b) = pair
    let cmp1 = a.compare(b)
    let cmp2 = b.compare(a)
    (cmp1 == cmp2.neg()) || (a == b && cmp1 == 0)
  })
}

// PBT: Term add/sub
// =================

test "PBT: Term add/sub are inverse" {
  @qc.quick_check_fn(fn(pair : (Term, Term)) {
    let (a, b) = pair
    a.sub(b).add(b) == a
  })
}

// PBT: LogIndex add/sub
// =====================

test "PBT: LogIndex add/sub are inverse" {
  @qc.quick_check_fn(fn(pair : (LogIndex, LogIndex)) {
    let (a, b) = pair
    a.sub(b).add(b) == a
  })
}

// PBT: NodeId add/sub
// ===================

test "PBT: NodeId add/sub are inverse" {
  @qc.quick_check_fn(fn(pair : (NodeId, NodeId)) {
    let (a, b) = pair
    a.sub(b).add(b) == a
  })
}
