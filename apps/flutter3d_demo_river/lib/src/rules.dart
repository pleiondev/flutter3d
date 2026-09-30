/// The rules of a run, kept apart from everything that draws or moves it:
/// the score, the jets left, the fuel, and the bridge a lost jet starts
/// again from.
library;

import 'dart:math' as math;

import 'course.dart' show TargetKind;
import 'levels.dart';

/// One run, from the first take-off to the last jet lost.
final class RunState {
  /// Jets in reserve at the start, not counting the one flying.
  static const int startingReserve = 3;

  /// Another jet in reserve every this many points.
  static const int extraJetEvery = 10000;

  /// A full tank lasts this many seconds of flying.
  static const double tankSeconds = 38.0;

  /// A depot fills an empty tank in this many seconds over it.
  static const double refillSeconds = 2.4;

  /// Below this the gauge warns.
  static const double lowFuel = 0.25;

  int score = 0;
  int reserve = startingReserve;

  /// From empty at zero to full at one.
  double fuel = 1.0;

  /// The section a lost jet starts again from: the one past the last bridge
  /// it brought down.
  int checkpoint = 0;

  int _nextExtraJet = extraJetEvery;

  /// What has gone down on the level being flown, by kind. Kept through a
  /// lost jet: what was shot stays shot, even though the river puts it back.
  final Map<TargetKind, int> tally = <TargetKind, int>{};

  /// One more [kind] down on this level.
  void count(TargetKind kind) => tally[kind] = (tally[kind] ?? 0) + 1;

  /// How many more of [kind] [level]'s task wants.
  int stillWanted(Level level, TargetKind kind) =>
      math.max(0, (level.task[kind] ?? 0) - (tally[kind] ?? 0));

  /// Whether [level]'s task is done, and its last bridge can fall.
  bool taskDone(Level level) =>
      level.task.keys.every((kind) => stillWanted(level, kind) == 0);

  /// [level] is flown: its bonus, and a clean tally for the next one.
  void finishLevel(Level level) {
    award(level.bonus);
    tally.clear();
  }

  bool get outOfFuel => fuel <= 0.0;
  bool get fuelLow => fuel < lowFuel;

  /// Adds [points], and a jet in reserve for every threshold they carry the
  /// score past.
  void award(int points) {
    score += points;
    while (score >= _nextExtraJet) {
      reserve++;
      _nextExtraJet += extraJetEvery;
    }
  }

  void burn(double dt) => fuel = math.max(0.0, fuel - dt / tankSeconds);

  void refuel(double dt) => fuel = math.min(1.0, fuel + dt / refillSeconds);

  /// The bridge at the end of section [index] is down: the next jet starts
  /// past it.
  void bridgeDown(int index) => checkpoint = math.max(checkpoint, index + 1);

  /// Takes a jet out of reserve for the next attempt, with a full tank.
  /// False when there is none left and the run is over.
  bool nextJet() {
    if (reserve == 0) return false;
    reserve--;
    fuel = 1.0;
    return true;
  }

  /// The run as it travels to the other machine.
  Map<String, Object?> toJson() => <String, Object?>{
    'score': score,
    'reserve': reserve,
    'fuel': fuel,
    'checkpoint': checkpoint,
    'extra': _nextExtraJet,
    'tally': <String, int>{
      for (final MapEntry(:key, :value) in tally.entries) key.name: value,
    },
  };

  /// Becomes the run [json] describes, in place: whoever holds this one,
  /// the panel and the game, sees the change.
  void load(Map<String, Object?> json) {
    score = (json['score'] as num?)?.toInt() ?? 0;
    reserve = (json['reserve'] as num?)?.toInt() ?? startingReserve;
    fuel = (json['fuel'] as num?)?.toDouble() ?? 1.0;
    checkpoint = (json['checkpoint'] as num?)?.toInt() ?? 0;
    _nextExtraJet = (json['extra'] as num?)?.toInt() ?? extraJetEvery;
    tally.clear();
    if (json['tally'] case final Map<Object?, Object?> counts) {
      for (final kind in TargetKind.values) {
        if (counts[kind.name] case final num n) tally[kind] = n.toInt();
      }
    }
  }
}

/// Two players taking turns up the river, as the cartridge had them: one jet
/// in the air at a time, each player with a run of their own — score, jets,
/// the bridge they start again from.
///
/// **A lost jet hands over.** The other player flies next if they have a jet
/// left, and the same one again only when the other has none; when neither
/// has, the game is over.
final class Turns {
  Turns() : runs = <RunState>[RunState(), RunState()];

  final List<RunState> runs;

  /// Whose jet is in the air, nought or one.
  int player = 0;

  /// Whether each player has had their first jet, which is not one out of
  /// reserve.
  final List<bool> _started = <bool>[true, false];

  RunState get current => runs[player];

  /// Who flies after [player]'s jet is lost, taking that player's next jet;
  /// null when neither has one and the game is over.
  int? next() {
    for (final p in <int>[1 - player, player]) {
      if (_takeJet(p)) return player = p;
    }
    return null;
  }

  bool _takeJet(int p) {
    if (_started[p]) return runs[p].nextJet();
    _started[p] = true;
    return true;
  }

  /// Both runs fresh, player nought first, starting from section [checkpoint].
  void reset({int checkpoint = 0}) {
    for (final run in runs) {
      run.load(RunState().toJson());
      run.checkpoint = checkpoint;
    }
    player = 0;
    _started
      ..[0] = true
      ..[1] = false;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'player': player,
    'started': List<bool>.of(_started),
    'runs': <Map<String, Object?>>[for (final run in runs) run.toJson()],
  };

  /// Becomes the turns [json] describes, its runs loaded in place.
  void load(Map<String, Object?> json) {
    player = (json['player'] as num?)?.toInt() ?? 0;
    if (json['started'] case final List<Object?> started) {
      for (var i = 0; i < 2 && i < started.length; i++) {
        _started[i] = started[i] == true;
      }
    }
    if (json['runs'] case final List<Object?> rows) {
      for (var i = 0; i < 2 && i < rows.length; i++) {
        if (rows[i] case final Map<Object?, Object?> row) {
          runs[i].load(row.cast<String, Object?>());
        }
      }
    }
  }
}
