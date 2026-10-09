import 'package:flutter3d_game_physics/party.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'net_race_session.dart';
import 'party_race.dart';
import 'staging.dart';

/// A [PartyRace] on the relay: the party itself is the addon's
/// [PartySession]; what is here is the race it stages, the car this machine
/// drives, and how many of the others have been heard from.
///
/// The car is the slot the relay gave. A party another client made larger
/// than a grid is refused before a car is staged.
final class PartyRaceSession {
  PartyRaceSession._(this._party);

  /// The cars a party can ask for: three up to a full grid.
  static const List<int> sizes = <int>[3, kFieldSize];

  final PartySession<PartyRace> _party;

  PartyRace get race => _party.game;

  /// What the other drivers type to join.
  String get code => _party.code;

  /// How many cars the party races, as the relay settled it.
  int get size => _party.size;

  /// The car this machine drives.
  int get localCarIndex => race.localCarIndex;

  /// How many of the other machines a frame has come from.
  int get heard => race.heard.length;

  /// Whether every car has its driver.
  bool get full => _party.isFull;

  /// Makes a party of [size] under a new code, or with [code] joins one
  /// somebody made, and stages its race once the relay has said which car
  /// is this machine's. Asked with the racing simulation's version, so a
  /// build on other rules is turned away by the relay.
  ///
  /// With [find], neither: the relay seats this machine among strangers
  /// who asked for a race of [size] on the same [circuit].
  static Future<PartyRaceSession> open({
    required Uri relayBase,
    required TrackDocument document,
    required CollisionWorld world,
    required InputState input,
    String? code,
    int size = 4,
    bool find = false,
    String circuit = '',
  }) async => PartyRaceSession._(
    await PartySession.open<PartyRace>(
      relayBase: relayBase,
      simulation: racingSimulationVersion,
      game: 'racing/$circuit',
      terms: NetRaceSession.terms,
      newCode: NetRaceSession.randomRoomCode,
      code: code,
      size: size,
      find: find,
      seats: kFieldSize,
      stage: (PartySeat seat) => PartyRace(
        sim: stage(document, world, cars: seat.size, laps: kLapsInARace).sim,
        wire: seat.wire,
        cars: seat.size,
        localInput: input,
        maxRollbackFrames: 24,
      ),
    ),
  );

  void advance() => race.advance();

  Future<void> dispose() => _party.dispose();
}
