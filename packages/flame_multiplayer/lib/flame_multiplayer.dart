/// Two players on two machines, for a game that steps in fixed steps.
///
/// Four ways two machines share a game, over any [PeerWire]:
///
/// - [PeerRoom] — who is who, a handshake that says what each machine plays,
///   and conversations on one wire that do not hear each other.
/// - [RollbackPlay] — both play one simulation in step, each driving their
///   own player, with an ending both machines agree on.
/// - [BatonStream] — turns: the machine whose turn it is plays, the other
///   replays what it is told, and the turn goes across with the state.
/// - [PeerFeed] — each plays a game of its own and tells the other where it
///   is: a ghost, a rival's score.
///
/// Under them, [RollbackSession] is rollback itself, and [LoopbackWire] two
/// ends of a wire in one process, late and lossy as a test asks. The wire
/// to a real network is an adapter: `flutter3d_net`'s `NetTransportWire`
/// for its relay and WebRTC transports, `flame_multiplayer_dashwire` for a
/// `dashwire` connection. Nothing here depends on either.
///
/// A game calls them from its own fixed step — Flame's `HasFixedStep` in
/// the bridged games — so what happens first within a step stays the
/// game's to say.
library;

export 'src/baton_stream.dart';
export 'src/party.dart';
export 'src/peer_feed.dart';
export 'src/peer_room.dart';
export 'src/peer_wire.dart';
export 'src/rollback_play.dart';
export 'src/rollback_session.dart';
