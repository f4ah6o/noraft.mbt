///|
fn Node::rebuild_log_after_snapshot(
  self : Node,
  last_included_position : LogPosition,
  last_included_config : ClusterConfig,
) -> Unit {
  match self.log.get_entries().since(last_included_position) {
    Some(entries) => self.log = Log::new(last_included_config, entries)
    None =>
      self.log = Log::new(
        last_included_config,
        LogEntries::new(last_included_position),
      )
  }
}
