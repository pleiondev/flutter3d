/// Rollback netcode over `flutter3d_sim`: input frames per step, prediction
/// by the last one that arrived, and a rollback when a confirmation
/// disagreed — `net-01` in `doc/tooling-plan.md`.
///
/// **Flat Dart, the same reasoning `flutter3d_physics` gives for itself.**
/// [NetSession] reads a caller's input through two callbacks and never names
/// a genre, a widget, or a socket — a relay's signalling half and a WebRTC
/// data channel are both reachable from `dart:io`/`package:web`, not from
/// Flutter, so nothing here needs the SDK to be tested under plain
/// `dart test`.
///
/// [NetTransport] is the one door to a real network — [LoopbackTransport]
/// stands in for it with a real fixed delay and a real, seeded loss rate,
/// which is what a test drives two [NetSession]s through rather than
/// against a mock that cannot lie about timing.
library;

export 'src/loopback_transport.dart';
export 'src/net_session.dart';
export 'src/net_transport.dart';
export 'src/snapshot_divergence.dart';
export 'src/websocket_transport.dart';
