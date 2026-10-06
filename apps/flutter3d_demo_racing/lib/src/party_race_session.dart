import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'net_race_session.dart';
import 'party_race.dart';
import 'staging.dart';

/// A [PartyRace] on the relay: the code a party is found by, the car this
/// machine drives, and how many of the others have been heard from.
///
/// **The relay decides the grid.** The first machine to ask for a code makes
/// the party, at the size it asked for; every later one is given the next
/// free slot and the size the first chose, so two friends who picked
/// different numbers still race the same race. The car is the slot.
final class PartyRaceSession {
  PartyRaceSession._({
    required this.race,
    required this.code,
    required this.size,
    required this._seat,
  });

  /// The cars a party can ask for: three up to a full grid.
  static const List<int> sizes = <int>[3, kFieldSize];

  final PartyRace race;

  /// What the other drivers type to join.
  final String code;

  /// How many cars the party races, as the relay settled it.
  final int size;

  final PartySeat _seat;

  /// The car this machine drives.
  int get localCarIndex => race.localCarIndex;

  /// How many of the other machines a frame has come from.
  int get heard => race.heard.length;

  /// Makes a party of [size] under a new code, or with [code] joins one
  /// somebody made, and stages its race once the relay has said which car
  /// is this machine's.
  static Future<PartyRaceSession> open({
    required Uri relayBase,
    required TrackDocument document,
    required CollisionWorld world,
    required InputState input,
    String? code,
    int size = 4,
  }) async {
    final party = code ?? NetRaceSession.randomRoomCode();
    final seat = await joinParty(relayBase, party, size: size);
    if (seat.size > kFieldSize) {
      // A party another client made larger than this circuit's grid: there
      // is no car for some of the slots, so this machine does not race.
      await seat.socket.close();
      throw StateError(
        'party $party is for ${seat.size} cars, and a grid here holds '
        '$kFieldSize',
      );
    }
    final staged = stage(document, world, cars: seat.size, laps: kLapsInARace);
    return PartyRaceSession._(
      race: PartyRace(
        sim: staged.sim,
        wire: seat.wire,
        cars: seat.size,
        localInput: input,
        maxRollbackFrames: 24,
      ),
      code: party,
      size: seat.size,
      seat: seat,
    );
  }

  void advance() => race.advance();

  Future<void> dispose() => _seat.socket.close();
}
