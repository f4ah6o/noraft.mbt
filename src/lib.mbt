///| noraft: Minimal, feature-complete Raft for MoonBit - no I/O, no dependencies.
///
/// [Raft]: https://raft.github.io/
///
/// `Node` is the main struct that represents a Raft node.
/// It offers methods for creating a cluster, proposing commands, updating cluster configurations,
/// handling incoming messages, snapshotting, and more.
///
/// `Node` itself does not execute I/O operations.
/// Instead, it generates `Action`s that represent pending I/O operations.
/// How to execute these actions is up to the user.

// All public types and functions are exported from their respective files
