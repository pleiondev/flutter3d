import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'relay_terms.dart';

/// A two-machine room on the relay, asked for with the simulation's
/// version: the socket a rollback session runs over, the code, and why the
/// relay closed it.
///
/// **Who made the room plays seat 0, who joined plays seat 1.** That is the
/// whole of the seating a room needs, and a game names it when it calls
/// [host] or [join] rather than learning it from the relay.
final class RoomSession {
  RoomSession._({
    required this.transport,
    required this.code,
    required this.seat,
  }) {
    transport.closed.then(
      (String? reason) => _closedBecause = reason ?? 'the room closed',
    );
  }

  /// The socket to the other machine, for `NetRollback` or a game's own.
  final WebSocketTransport transport;

  /// What the other player types to join.
  final String code;

  /// 0 for the machine that called [host], 1 for the one that called
  /// [join].
  final int seat;

  /// Why the relay closed the room — another machine's terms or
  /// simulation, a room already holding two — or null while it is open.
  String? get closedBecause => _closedBecause;
  String? _closedBecause;

  /// The room [code] on [relayBase], asked for with [terms], the wire
  /// protocol and [simulation]'s [relayVersionOf]: `relayRoom`'s address, as a
  /// party's seat asks for its own. A machine on another simulation is
  /// closed by the relay with its reason, which [closedBecause] reads,
  /// before a frame of a game that would part at its first contact.
  static Uri address(
    Uri relayBase,
    String code, {
    required SimulationVersion simulation,
    String terms = '',
  }) => relayRoom(relayBase, code, terms: terms, simulation: simulation);

  /// Creates the room [code] as seat 0, the side that started the session.
  static Future<RoomSession> host({
    required Uri relayBase,
    required String code,
    required SimulationVersion simulation,
    String terms = '',
  }) => _connect(relayBase, code, simulation, terms, seat: 0);

  /// Joins the room [code] somebody else created, as seat 1.
  static Future<RoomSession> join({
    required Uri relayBase,
    required String code,
    required SimulationVersion simulation,
    String terms = '',
  }) => _connect(relayBase, code, simulation, terms, seat: 1);

  static Future<RoomSession> _connect(
    Uri relayBase,
    String code,
    SimulationVersion simulation,
    String terms, {
    required int seat,
  }) async => RoomSession._(
    transport: await WebSocketTransport.connect(
      address(relayBase, code, simulation: simulation, terms: terms),
    ),
    code: code,
    seat: seat,
  );

  /// Leaves the room.
  Future<void> close() => transport.close();
}

/// One machine's own side of a networked session, kept as a `.f3drun`.
///
/// **A run per side, not one shared file.** A [Demo] is one player's input
/// tape against a state the tape alone reproduces. A session of two has two
/// independently driven players, and no single tape replays the one whose
/// input came over the network. What the two files can answer is whether
/// both sides settled the same states: each writes its own [checkpoints],
/// and the digests are compared.
final class SideRecording {
  /// Starts a recording from [start], the state the session was staged in,
  /// for the level read from [level] whose hash is [levelHash]. The tape's
  /// seed is the snapshot's `random`.
  SideRecording({
    required this.start,
    required this.level,
    required this.levelHash,
    this.physics = const DartPhysics(),
  }) : _recorder = InputTapeRecorder(seed: start.data.integer('random'));

  /// The state the session was staged in.
  final Snapshot start;

  /// The level's asset path, as a [Demo] names it.
  final String level;
  final String levelHash;

  final InputTapeRecorder _recorder;

  /// The settled states, one digest a step.
  final DigestTrace checkpoints = DigestTrace();

  /// Records this machine's own [input] for the step about to run. Call it
  /// before the session advances.
  void record(InputState input) => _recorder.record(input);

  /// Notes that [step] settled at [after]: hand it to the rollback
  /// session's `onSettled`.
  void settled(int step, Snapshot after) =>
      checkpoints.observe(step + 1, after.toJson());

  /// The physics this side plays on, named in its [Demo]: the Dart
  /// reference unless the game hands over the one it chose (`usePhysics()`).
  final PhysicsBackend physics;

  /// This machine's half of the session as a [Demo].
  Demo toDemo({String buildStamp = 'dev', String? recordedBy}) => Demo(
    level: level,
    levelHash: levelHash,
    start: start,
    tape: _recorder.tape,
    buildStamp: buildStamp,
    checkpoints: checkpoints,
    recordedBy: recordedBy,
    physics: physics.name,
  );
}
