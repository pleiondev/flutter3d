import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_game_physics/party.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'net_race.dart';
import 'staging.dart';

/// `net-03`'s connection half: a room code turned into a two-car [NetRace].
/// The room and the run are the addon's ([RoomSession], [SideRecording]);
/// what is here is the race: who drives which car — whoever creates the
/// room drives car 0, whoever joins drives car 1, as the design note on
/// `NetRace` settles it — the staging, and writing the run to a file.
final class NetRaceSession {
  NetRaceSession._({
    required this.race,
    required this._room,
    required this._recording,
    required this._input,
  });

  final NetRace race;
  final RoomSession _room;
  final SideRecording _recording;
  final InputState _input;

  String get roomCode => _room.code;

  /// Which grid slot this device drives — 0 for whoever called [create], 1
  /// for whoever called [join].
  int get localCarIndex => _room.seat;

  /// Whether the far side has actually sent a frame — [NetRace.connected],
  /// read here for a screen's own "the other car is a ghost" indicator.
  bool get connected => race.connected;

  /// What every machine in a race has to share: [physicsTerms].
  static String get terms => physicsTerms;

  /// Why the relay closed this race's room — another machine's terms, a
  /// room already holding two — or null while it is open.
  String? get closedBecause => _room.closedBecause;

  /// A short room code from [partyCodeAlphabet].
  static String randomRoomCode({math.Random? random}) =>
      partyCode(random ?? math.Random());

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
  }) async => _staged(
    room: await RoomSession.host(
      relayBase: relayBase,
      code: roomCode ?? randomRoomCode(),
      simulation: racingSimulationVersion,
      terms: terms,
    ),
    document: document,
    world: world,
    input: input,
    trackAsset: trackAsset,
    inputDelay: inputDelay,
    maxRollbackFrames: maxRollbackFrames,
  );

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
  }) async => _staged(
    room: await RoomSession.join(
      relayBase: relayBase,
      code: roomCode,
      simulation: racingSimulationVersion,
      terms: terms,
    ),
    document: document,
    world: world,
    input: input,
    trackAsset: trackAsset,
    inputDelay: inputDelay,
    maxRollbackFrames: maxRollbackFrames,
  );

  /// The room [code] on [relayBase], asked for with [terms] and the racing
  /// simulation's version — [RoomSession.address].
  static Uri roomAddress(Uri relayBase, String code) => RoomSession.address(
    relayBase,
    code,
    simulation: racingSimulationVersion,
    terms: terms,
  );

  /// [racingSimulationVersion] as the one number a relay compares.
  static int get relayVersion => relayVersionOf(racingSimulationVersion);

  static NetRaceSession _staged({
    required RoomSession room,
    required TrackDocument document,
    required CollisionWorld world,
    required InputState input,
    required String trackAsset,
    required int inputDelay,
    required int maxRollbackFrames,
  }) {
    final staged = stage(document, world, cars: 2, laps: kLapsInARace);
    final recording = SideRecording(
      start: staged.sim.save(),
      level: trackAsset,
      levelHash: document.level!.digestHex,
      physics: world.backend,
    );
    return NetRaceSession._(
      race: NetRace(
        sim: staged.sim,
        localCarIndex: room.seat,
        localInput: input,
        transport: room.transport,
        inputDelay: inputDelay,
        maxRollbackFrames: maxRollbackFrames,
        onSettled: recording.settled,
      ),
      room: room,
      recording: recording,
      input: input,
    );
  }

  /// Advances the race by one fixed step and records this device's own
  /// driver input for the run [toDemo] will write.
  void advance() {
    _recording.record(_input);
    race.advance();
  }

  /// This device's own half of the match — see [SideRecording] for why it
  /// is one side's tape, not a merged one.
  Demo toDemo({String buildStamp = 'dev', String? recordedBy}) =>
      _recording.toDemo(buildStamp: buildStamp, recordedBy: recordedBy);

  /// Writes [toDemo] to [path].
  ///
  /// **Synchronous, not `writeAsString`.** `rp-04`'s own note in
  /// `doc/tooling-plan.md` already found this the hard way: an asynchronous
  /// `File.writeAsString` inside `flutter test` in this sandbox hangs
  /// forever — no exception, no timeout — while the synchronous call in the
  /// same test returns instantly.
  void saveRunTo(String path, {String buildStamp = 'dev', String? recordedBy}) {
    File(path).writeAsStringSync(
      jsonEncode(
        toDemo(buildStamp: buildStamp, recordedBy: recordedBy).toJson(),
      ),
    );
  }

  Future<void> dispose() => _room.close();
}
