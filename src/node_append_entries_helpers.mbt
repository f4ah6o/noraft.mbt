///|
fn Node::append_entries_call(self : Node, entries : LogEntries) -> Message {
  Message::append_entries_call(
    self.current_term,
    self.id,
    self.commit_index,
    entries,
  )
}

///|
fn Node::broadcast_append_entries(self : Node, entries : LogEntries) -> Unit {
  self.actions.set(BroadcastMessage(self.append_entries_call(entries)))
}

///|
fn Node::send_append_entries(
  self : Node,
  to : NodeId,
  entries : LogEntries
) -> Unit {
  self.actions.set(SendMessage(to, self.append_entries_call(entries)))
}
