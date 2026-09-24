/// What an agent claims about a run, in a form a replay can check.
///
/// **Over [HeadlessRun.reading], not over the game's own types.** The server
/// plays whatever game a host hands it, so a claim can only name what every
/// game's reading shares: a `player` row and an `actors` list of rows, each
/// with a `position`, a `health` and whether it is `alive`. A game whose
/// reading has no such row is told so in a sentence rather than answered with
/// a claim that silently never holds.
///
/// **Four kinds, because four is what the reading can back.** Where somebody
/// stands (`near`, `inside`), whether they are up (`alive`) and how hurt they
/// are (`health`). What touched what is not here: a contact is a `GameEvent`,
/// events are not in a save, and a claim no replay can reproduce is not worth
/// making.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart' show HeadlessRun;

/// Thrown when a claim cannot be read, or names somebody the reading does not
/// have.
final class ReadingPredicateException implements Exception {
  const ReadingPredicateException(this.message);

  final String message;

  @override
  String toString() => 'ReadingPredicateException: $message';
}

/// One claim about one row of a reading: the player, or an actor by name.
sealed class ReadingPredicate {
  const ReadingPredicate(this.who);

  /// Reads a claim of the shape the `expect` tool takes: a `kind`, a `who`
  /// (the player when left out) and the kind's own fields.
  factory ReadingPredicate.fromJson(Map<String, Object?> json) {
    final who = switch (json['who']) {
      null => 'player',
      final String name when name.isNotEmpty => name,
      _ => throw const ReadingPredicateException(
        '"who" is the player or an actor\'s name',
      ),
    };
    return switch (json['kind']) {
      'near' => NearPredicate(
        who,
        point: _point(json, 'point'),
        within: _number(json, 'within'),
      ),
      'inside' => InsidePredicate(
        who,
        min: _point(json, 'min'),
        max: _point(json, 'max'),
      ),
      'alive' => AlivePredicate(
        who,
        alive: switch (json['is']) {
          null => true,
          final bool alive => alive,
          _ => throw const ReadingPredicateException('"is" is true or false'),
        },
      ),
      'health' => HealthPredicate(
        who,
        below: _optionalNumber(json, 'below'),
        atLeast: _optionalNumber(json, 'atLeast'),
      ),
      final kind => throw ReadingPredicateException(
        'no claim of kind "$kind" — the kinds are near, inside, alive and '
        'health',
      ),
    };
  }

  /// The player, or the name of an actor in the reading's `actors`.
  final String who;

  /// Whether the claim holds for [row], the reading's row for [who].
  bool holdsFor(Map<String, Object?> row);

  /// The claim as a sentence, for an answer read as prose.
  String describe();

  /// Whether the claim holds over a whole [reading].
  ///
  /// Throws a [ReadingPredicateException] when [who] has no row in it, which
  /// is a claim about nobody rather than a claim that is false.
  bool holds(Map<String, Object?> reading) => holdsFor(_rowOf(reading));

  Map<String, Object?> _rowOf(Map<String, Object?> reading) {
    if (who == 'player') {
      if (reading['player'] case final Map<String, Object?> row) return row;
      throw const ReadingPredicateException(
        'this game\'s reading has no player row to make a claim about',
      );
    }
    final actors = reading['actors'];
    if (actors is List<Object?>) {
      for (final actor in actors) {
        if (actor case final Map<String, Object?> row when row['name'] == who) {
          return row;
        }
      }
    }
    throw ReadingPredicateException(
      'nobody called "$who" in the reading — call snapshot for the names',
    );
  }
}

/// [who] stands within [within] metres of [point].
final class NearPredicate extends ReadingPredicate {
  const NearPredicate(super.who, {required this.point, required this.within});

  final List<double> point;
  final double within;

  @override
  bool holdsFor(Map<String, Object?> row) {
    // No body is nowhere, and nowhere is near nothing.
    final at = _position(row);
    if (at == null) return false;
    final dx = at[0] - point[0];
    final dy = at[1] - point[1];
    final dz = at[2] - point[2];
    return dx * dx + dy * dy + dz * dz <= within * within;
  }

  @override
  String describe() => '$who within $within of ${_show(point)}';
}

/// [who] stands inside the box from [min] to [max], edges included.
final class InsidePredicate extends ReadingPredicate {
  const InsidePredicate(super.who, {required this.min, required this.max});

  final List<double> min;
  final List<double> max;

  @override
  bool holdsFor(Map<String, Object?> row) {
    final at = _position(row);
    if (at == null) return false;
    return <int>[0, 1, 2].every((i) => at[i] >= min[i] && at[i] <= max[i]);
  }

  @override
  String describe() => '$who inside ${_show(min)}..${_show(max)}';
}

/// [who] is up when [alive] is true, and down when it is false.
final class AlivePredicate extends ReadingPredicate {
  const AlivePredicate(super.who, {required this.alive});

  final bool alive;

  @override
  bool holdsFor(Map<String, Object?> row) => row['alive'] == alive;

  @override
  String describe() => alive ? '$who alive' : '$who dead';
}

/// [who]'s health is under [below] and at least [atLeast], whichever of the
/// two are given.
final class HealthPredicate extends ReadingPredicate {
  HealthPredicate(super.who, {this.below, this.atLeast}) {
    if (below == null && atLeast == null) {
      throw const ReadingPredicateException(
        'a health claim needs "below", "atLeast" or both',
      );
    }
  }

  final double? below;
  final double? atLeast;

  @override
  bool holdsFor(Map<String, Object?> row) {
    // An actor with no health — a door, a trigger — has none to compare.
    if (row['health'] case final num health) {
      return (below == null || health < below!) &&
          (atLeast == null || health >= atLeast!);
    }
    return false;
  }

  @override
  String describe() => <String>[
    if (atLeast != null) '$who health at least $atLeast',
    if (below != null) '$who health below $below',
  ].join(' and ');
}

List<double>? _position(Map<String, Object?> row) => switch (row['position']) {
  [final num x, final num y, final num z] => <double>[
    x.toDouble(),
    y.toDouble(),
    z.toDouble(),
  ],
  _ => null,
};

List<double> _point(Map<String, Object?> json, String key) =>
    switch (json[key]) {
      [final num x, final num y, final num z] => <double>[
        x.toDouble(),
        y.toDouble(),
        z.toDouble(),
      ],
      _ => throw ReadingPredicateException('"$key" is three numbers, x y z'),
    };

double _number(Map<String, Object?> json, String key) =>
    _optionalNumber(json, key) ??
    (throw ReadingPredicateException('"$key" is a number, and it is missing'));

double? _optionalNumber(Map<String, Object?> json, String key) =>
    switch (json[key]) {
      null => null,
      final num value => value.toDouble(),
      _ => throw ReadingPredicateException('"$key" is a number'),
    };

String _show(List<double> p) =>
    '(${p.map((v) => v.toStringAsFixed(2)).join(', ')})';
