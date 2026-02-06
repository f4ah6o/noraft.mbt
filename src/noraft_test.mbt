test "Node basic operations" {
  // Create a node
  let node = Node::start(NodeId::new(1))
  
  // Check initial state
  inspect!(node.id(), content="1")
  inspect!(node.current_term(), content="0")
  inspect!(node.commit_index(), content="0")
}

test "ClusterConfig operations" {
  let config = ClusterConfig::new()
  
  // Initially empty
  inspect!(config.voters_ref().is_empty(), content="true")
  inspect!(config.new_voters_ref().is_empty(), content="true")
  inspect!(config.non_voters_ref().is_empty(), content="true")
  
  // Add voters
  config.voters_ref().push(NodeId::new(1))
  config.voters_ref().push(NodeId::new(2))
  inspect!(config.voters_ref().length(), content="2")
  inspect!(config.contains(NodeId::new(1)), content="true")
  inspect!(config.is_voter(NodeId::new(1)), content="true")
}

test "LogPosition operations" {
  let pos1 = LogPosition::new(Term::new(1), LogIndex::new(5))
  inspect!(pos1.get_term(), content="1")
  inspect!(pos1.get_index(), content="5")
  
  let pos2 = pos1.next()
  inspect!(pos2.get_term(), content="1")
  inspect!(pos2.get_index(), content="6")
}

test "Actions operations" {
  let actions = Actions::new()
  inspect!(actions.is_empty(), content="true")
}

test "Message operations" {
  let msg = Message::request_vote_call(
    Term::new(1),
    NodeId::new(1),
    LogPosition::new(Term::new(1), LogIndex::new(5))
  )
  
  inspect!(msg.from(), content="1")
  inspect!(msg.term(), content="1")
}
