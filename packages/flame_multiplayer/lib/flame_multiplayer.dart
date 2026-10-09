/// Two players on two machines, or a party of them, for a game that steps in
/// fixed steps.
///
/// Four ways machines share a game, over the one transport, [PeerWire] —
/// `flutter3d_net`'s, with the room, the hello and the rollback, which this
/// package re-exports so a game names them from one import:
///
/// - [PeerRoom] — who is who, a handshake that says what each machine plays
///   and refuses a machine on another protocol or simulation version
///   ([WireHello]), and conversations on one wire that do not hear each
///   other.
/// - [RollbackSession] — all play one simulation in step, each driving
///   their own player, with an ending every machine agrees on: two machines
///   or up to thirty-two.
/// - [BatonStream] — turns: the machine whose turn it is plays, the other
///   replays what it is told, and the turn goes across with the state.
/// - [PeerFeed] — each plays a game of its own and tells the other where it
///   is: a ghost, a rival's score.
///
/// [LoopbackWire] and [LoopbackParty] are wires in one process, late and
/// lossy as a test asks. A wire to a real network is a [PeerWire] in the
/// package that owns that network: `flutter3d_net`'s relay and WebRTC
/// transports, `flame_multiplayer_dashwire` for a `dashwire` connection.
/// Over an `EngineLoop`, `flutter3d_net`'s `EngineRollback` hands
/// [RollbackSession] the loop's snapshots.
///
/// **The network core is `flutter3d_net`'s**, on the 1.0 line: [PeerWire],
/// [PeerRoom], [WireHello], [RollbackSession] and the loopbacks moved there
/// before 1.0. What stays here — turns, a ghost's feed, a party's spectator
/// and its authority — is built on them.
///
/// A game calls them from its own fixed step — Flame's `HasFixedStep` in
/// the bridged games — so what happens first within a step stays the
/// game's to say.
library;

// The network core, so a game reaching for the turns or the feed still
// names the wire, the room and the rollback from this one import.
export 'package:flutter3d_net/flutter3d_net.dart'
    show
        LoopbackParty,
        LoopbackWire,
        PeerRoom,
        PeerWire,
        RollbackSession,
        WireHello,
        WireState;

export 'src/baton_stream.dart';
export 'src/party.dart';
export 'src/peer_feed.dart';
