/// A `dashwire` connection as a `flame_multiplayer` wire.
///
/// ```dart
/// final wire = DashwireWire(await connectWebSocket(roomUri));
/// final room = PeerRoom(
///   wire,
///   slot: 0,
///   simulation: const SimulationVersion(genre: 'game', genreVersion: 3),
/// );
/// ```
///
/// The room's hello carries the protocol and the game's simulation as JSON
/// like any other message, so a build on another simulation is refused over
/// dashwire the same way as over any wire: [PeerRoom.refusal] says which
/// game to update.
library;

export 'src/dashwire_wire.dart';
