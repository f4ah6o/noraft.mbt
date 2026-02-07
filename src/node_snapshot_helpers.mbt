///|
fn Node::update_pending_append_log_entries_for_snapshot(
  self : Node,
  last_included_position : LogPosition
) -> Unit {
  match self.actions.append_log_entries {
    Some(entries) => {
      entries.handle_snapshot_installed(last_included_position)
      self.actions.append_log_entries =
        if entries.is_empty() { None } else { Some(entries) }
    }
    None => ()
  }
}

///|
fn Node::update_pending_broadcast_message_for_snapshot(
  self : Node,
  last_included_position : LogPosition
) -> Unit {
  match self.actions.broadcast_message {
    Some(msg) =>
      self.actions.broadcast_message =
        Some(msg.handle_snapshot_installed(last_included_position))
    None => ()
  }
}

///|
fn Node::update_pending_send_messages_for_snapshot(
  self : Node,
  last_included_position : LogPosition
) -> Unit {
  let keys = self.actions.send_messages.keys()
  for id in keys {
    let msg = self.actions.send_messages[id]
    self.actions.send_messages[id] =
      msg.handle_snapshot_installed(last_included_position)
  }
}
