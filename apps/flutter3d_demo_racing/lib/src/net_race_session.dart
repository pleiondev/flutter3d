import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_net/flutter3d_net.dart';

import 'net_race.dart';
import 'staging.dart';

/// `net-03`'s connection half: turning a room code into a two-car
/// [NetRace], deciding [NetRace.localCarIndex] the way the design note on
/// `NetRace` itself settles it — whoever creates the room drives car 0,
/// whoever joins drives car 1 — and recording this device's own side of
/// the match as a `.f3drun`.
///
/// **A `.f3drun` per side, not one shared file.** `Demo` is one player's
/// own input tape against a state the tape alone can reproduce — a net
/// race has two independently-driven cars, and no single tape replays the
/// other one's driving, which came over the network rather than from a
/// script. What the plan's own acceptance actually asks for — "оба файла
/// прогона дают одинаковые дайджесты" — is exactly what two independently
/// written [checkpoints] traces can answer without either file needing to
/// stand in for both cars.
final class NetRaceSession {
  NetRaceSession._({
    required this.race,
    required this.roomCode,
    required this.localCarIndex,
    required this._transport,
    required this._checkpoints,
    required this._start,
    required this._levelHash,
    required this._trackAsset,
    required this._recorder,
    required this._input,
  });

  final NetRace race;
  final String roomCode;

  /// Which grid slot this device drives — 0 for whoever called [create], 1
  /// for whoever called [join].
  final int localCarIndex;

  final WebSocketTransport _transport;
  final DigestTrace _checkpoints;
  final Snapshot _start;
  final String _levelHash;
  final String _trackAsset;
  final InputTapeRecorder _recorder;
  final InputState _input;

  /// Whether the far side has actually sent a frame — [NetRace.connected],
  /// read here for a screen's own "the other car is a ghost" indicator.
  bool get connected => race.connected;

  static const String _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// A short room code neither `0`/`O` nor `1`/`I` can be confused between
  /// — read aloud or typed on a phone keyboard, the two ways this is
  /// actually going to travel between two people in the same room.
  static String randomRoomCode({math.Random? random}) {
    final dice = random ?? math.Random();
    return List<String>.generate(
      5,
      (_) => _codeAlphabet[dice.nextInt(_codeAlphabet.length)],
    ).join();
  }

  /// Creates a fresh room (or joins [roomCode] if one was already agreed
  /// on) as car 0 — the side that started the match.
  static Future<NetRaceSession> create({
    required Uri relayBase,
    required TrackDocument document,
    required CollisionWorld world,
    required InputState input,
    required String trackAsset,
    String? roomCode,
    int inputDelay = 3,
    int maxRollbackFrames = 24,
  }) async {
    final code = roomCode ?? randomRoomCode();
    final transport = await WebSocketTransport.connect(
      relayBase.resolve('room/$code'),
    );
    return _staged(
      document: document,
      world: world,
      input: input,
      trackAsset: trackAsset,
      localCarIndex: 0,
      transport: transport,
      roomCode: code,
      inputDelay: inputDelay,
      maxRollbackFrames: maxRollbackFrames,
    );
  }

  /// Joins a room somebody else already created, as car 1.
  static Future<NetRaceSession> join({
    required Uri relayBase,
    required TrackDocument document,
    required CollisionWorld world,
    required InputState input,
    required String trackAsset,
    required String roomCode,
    int inputDelay = 3,
    int maxRollbackFrames = 24,
  }) async {
    final transport = await WebSocketTransport.connect(
      relayBase.resolve('room/$roomCode'),
    );
    return _staged(
      document: document,
      world: world,
      input: input,
      trackAsset: trackAsset,
      localCarIndex: 1,
      transport: transport,
      roomCode: roomCode,
      inputDelay: inputDelay,
      maxRollbackFrames: maxRollbackFrames,
    );
  }

  static NetRaceSession _staged({
    required TrackDocument document,
    required CollisionWorld world,
    required InputState input,
    required String trackAsset,
    required int localCarIndex,
    required WebSocketTransport transport,
    required String roomCode,
    required int inputDelay,
    required int maxRollbackFrames,
  }) {
    final staged = stage(document, world, cars: 2, laps: kLapsInARace);
    final start = staged.sim.save();
    final checkpoints = DigestTrace();
    final recorder = InputTapeRecorder(seed: start.data.integer('random'));

    final race = NetRace(
      sim: staged.sim,
      localCarIndex: localCarIndex,
      localInput: input,
      transport: transport,
      inputDelay: inputDelay,
      maxRollbackFrames: maxRollbackFrames,
      onSettled: (step, after) => checkpoints.observe(step + 1, after.toJson()),
    );

    return NetRaceSession._(
      race: race,
      roomCode: roomCode,
      localCarIndex: localCarIndex,
      transport: transport,
      checkpoints: checkpoints,
      start: start,
      levelHash: document.level!.digestHex,
      trackAsset: trackAsset,
      recorder: recorder,
      input: input,
    );
  }

  /// Advances the race by one fixed step and records this device's own
  /// driver input for the run [toDemo] will write.
  void advance() {
    _recorder.record(_input);
    race.advance();
  }

  /// This device's own half of the match, as a `Demo` — see the class doc
  /// for why this is one side's tape, not a merged one.
  Demo toDemo({String buildStamp = 'dev', String? recordedBy}) => Demo(
    level: _trackAsset,
    levelHash: _levelHash,
    start: _start,
    tape: _recorder.tape,
    buildStamp: buildStamp,
    checkpoints: _checkpoints,
    recordedBy: recordedBy,
  );

  /// Writes [toDemo] to [path].
  ///
  /// **Synchronous, not `writeAsString`.** `rp-04`'s own note in
  /// `doc/tooling-plan.md` already found this the hard way: an asynchronous
  /// `File.writeAsString` inside `flutter test` in this sandbox hangs
  /// forever — no exception, no timeout — while the synchronous call in the
  /// same test returns instantly. A few kilobytes of JSON is not the volume
  /// that async I/O exists to help with anyway.
  void saveRunTo(String path, {String buildStamp = 'dev', String? recordedBy}) {
    File(path).writeAsStringSync(
      jsonEncode(
        toDemo(buildStamp: buildStamp, recordedBy: recordedBy).toJson(),
      ),
    );
  }

  Future<void> dispose() => _transport.close();
}
