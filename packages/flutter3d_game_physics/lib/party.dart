/// Local and network party sessions for any simulation on flutter3d's
/// relay: a party of up to a full table found by a code or among strangers
/// ([PartySession]), a two-machine room ([RoomSession]), and one side's
/// run kept as a `.f3drun` ([SideRecording]).
///
/// **Every ask carries the simulation's version.** The relay holds a party
/// and a room to one `SimulationVersion` (`flutter3d_plugin_api`'s) and one set of terms, and turns a
/// machine on another away with a reason, before a frame of a session that
/// would part at its first contact. That is the 1.0 network hello, from the
/// side of the code that asks.
///
/// What a session steps — the game's own rollback over the seat's wire —
/// is the game's. This package seats it.
library;

export 'src/party/party_session.dart';
export 'src/party/relay_terms.dart';
export 'src/party/room_session.dart';
