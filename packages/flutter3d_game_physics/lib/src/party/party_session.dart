import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'relay_terms.dart';

/// A party on the relay, and the game staged for it: the code a party is
/// found by, the slot this machine plays, and whether every slot is taken.
///
/// **The relay decides the seats.** The first machine to ask for a code
/// makes the party, at the size it asked for; every later one is given the
/// next free slot and the size the first chose, so two friends who picked
/// different numbers still play the same game. A game reads its own seat
/// from [seat]'s `slot`.
///
/// **The simulation's version always goes with the ask.** A party runs one
/// simulation, and the relay turns away a machine on another with a reason
/// naming the version to update to, before a frame of a game that would
/// part at its first contact. [open] requires it for that reason: a party
/// that asked with none met only others that asked with none, which is
/// every build of every game.
final class PartySession<G> {
  PartySession._({required this.game, required this.seat});

  /// What [open]'s `stage` made of the seat: the game this party plays.
  final G game;

  /// This machine's place in the party: its wire, slot, the party's size
  /// and code.
  final PartySeat seat;

  /// What the other players type to join.
  String get code => seat.code;

  /// How many players the party has, as the relay settled it.
  int get size => seat.size;

  /// The slot this machine plays.
  int get slot => seat.slot;

  /// Whether every slot has its player: the relay says so once the last
  /// one joins.
  bool get isFull => _full;
  bool _full = false;

  /// Makes a party of [size] under a new code, or with [code] joins one
  /// somebody made, and calls [stage] with the seat once the relay has said
  /// which slot is this machine's.
  ///
  /// With [find], neither: the relay seats this machine among strangers who
  /// asked for a party of [size] for the same [game] — a game's name and,
  /// where it has them, the place played, `'racing/ring'` — and the code is
  /// whatever party that turned out to be.
  ///
  /// [simulation] is what the relay holds the party to (see
  /// [relayVersionOf]), [terms] what else every machine must share, usually
  /// [physicsTerms]. [newCode] makes the code when [code] is null.
  ///
  /// [seats] is how many players this game can stage. A party another
  /// client made larger is left, and the future fails with a [StateError]
  /// naming both numbers: there is nothing for some of the slots to play.
  static Future<PartySession<G>> open<G>({
    required Uri relayBase,
    required SimulationVersion simulation,
    required G Function(PartySeat seat) stage,
    required String Function() newCode,
    String game = '',
    String terms = '',
    String? code,
    int size = 4,
    bool find = false,
    int? seats,
  }) async {
    final seat = find
        ? await findParty(
            relayBase,
            game: game,
            size: size,
            terms: terms,
            simulation: simulation,
          )
        : await joinParty(
            relayBase,
            code ?? newCode(),
            size: size,
            terms: terms,
            simulation: simulation,
          );
    if (seats != null && seat.size > seats) {
      await seat.socket.close();
      throw StateError(
        'party ${seat.code} is for ${seat.size} players, and this game '
        'seats $seats',
      );
    }
    return PartySession<G>._(game: stage(seat), seat: seat).._watchFull();
  }

  void _watchFull() => seat.full.then((_) => _full = true);

  /// Leaves the party.
  Future<void> dispose() => seat.socket.close();
}
