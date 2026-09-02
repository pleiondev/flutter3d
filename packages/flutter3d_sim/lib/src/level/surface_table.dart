import 'package:flutter3d_physics/flutter3d_physics.dart';

import 'level.dart';

/// What a body is standing on, as the word the level author wrote.
///
/// Two lines, and both genres had them: the platformer's runner reads what is
/// under its feet this way and the racing game's `TrackField` reads what is
/// under a tyre — with a comment saying "the same way the platformer's runner
/// reads what it is standing on". A rule two files agree about, and one of them
/// explains, belongs where neither of them is.
///
/// The rule itself is [LevelCollision]'s: a brush becomes a collider that
/// carries the brush, and the brush carries the word. Anything else under the
/// body — an entity, a mover, a car — has no surface to report, and null is the
/// right answer rather than a guess.
String? surfaceUnder(Collider? collider) {
  final under = collider?.userData;
  return under is Brush ? under.surface : null;
}

/// What this game thinks a level's surface words are worth.
///
/// **The same class twice, with a different value.** The platformer's
/// `Surfaces` maps a word to a whole `MovementTuning` — ice is low friction
/// *and* low acceleration *and* a different jump — and the racing game's
/// `GripTable` maps it to one number, because on a loose surface there is only
/// one idea and it is "less grip". Everything either of them did around that
/// map was identical, down to the paragraph explaining the fallback.
///
/// The division of labour is the engine's rule and worth restating: a level
/// document says a *word* and has no opinion about physics; the genre owns the
/// table and every number in it. `ice` is a platformer's idea and `gravel` is a
/// racing game's, so neither is spelt here.
///
/// **A word this table has never heard of takes [fallback], and that is the
/// load-bearing decision.** A level may name a surface for its footstep sound
/// or its tyre noise alone, and a game that treated every unknown word as
/// nothing in particular — or worse, as a default of zero — would turn a
/// straight into an ice rink the day somebody added a sound.
base class SurfaceTable<T> {
  const SurfaceTable(this._byName, {required this.fallback});

  final Map<String, T> _byName;

  /// What an unnamed surface, or one this table has never heard of, is worth.
  final T fallback;

  /// What standing on, or driving over, [surface] is worth here.
  ///
  /// Both classes this replaces wrote `surface == null ? fallback : ...` first
  /// and the lookup second, and a mutation that deleted the null check changed
  /// nothing anywhere: `Map<String, T>` takes an `Object?` and answers null for
  /// a key it does not hold, whatever that key is. One branch, not two.
  T of(String? surface) => _byName[surface] ?? fallback;

  /// Whether this table has an opinion about [surface] — for a game deciding
  /// whether a floor is worth a sound.
  bool knows(String surface) => _byName.containsKey(surface);

  Iterable<String> get names => _byName.keys;
}
