/// Networking over `flutter3d_sim`: the one transport, the one rollback,
/// the relay's transports, finding a party, and rollback over the engine's
/// loop.
///
/// **One transport and one rollback.** Every transport is a [PeerWire] —
/// [WebSocketTransport] through the relay, `flutter3d_net_webrtc`'s data
/// channel, `PeerWire.party` over a relay's party room ([joinParty],
/// [findParty]) — and the rollback is [RollbackSession], for two machines or
/// a party, which [EngineRollback] runs over an `EngineLoop`'s snapshots and
/// steps. [PeerRoom] is two machines meeting, with the hello ([WireHello])
/// that refuses another protocol or another simulation. [LoopbackWire] and
/// [LoopbackParty] stand in for a network in a test, late and lossy as it
/// asks.
///
/// **On the 1.0 line.** These were `flame_multiplayer`'s before 1.0; the
/// network core a 1.0 game depends on lives here, and `flame_multiplayer`
/// (turns, a ghost's feed, a spectator's tape) is built on it.
///
/// **Flat Dart.** Nothing here needs the Flutter SDK; a relay and a test
/// run under plain `dart test`.
library;

export 'src/engine_rollback.dart';
export 'src/party_join.dart';
export 'src/peer_room.dart';
export 'src/peer_wire.dart';
export 'src/rollback_session.dart';
export 'src/snapshot_divergence.dart';
export 'src/websocket_transport.dart';
export 'src/wire_hello.dart';
