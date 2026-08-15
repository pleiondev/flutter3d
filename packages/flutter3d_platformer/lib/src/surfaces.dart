import 'package:flutter3d_game/flutter3d_game.dart';

/// What the floor does to whoever is standing on it.
///
/// The engine gave a brush a [Brush.surface] — a word, and no opinion about
/// what it means — and made `MovementTuning` swappable. This is the other half:
/// the genre's table from that word to those numbers. `ice` is a platformer's
/// idea, so it is spelt here and nowhere below.
///
/// One table rather than a field per effect, because "how does this floor feel"
/// is every number in `MovementTuning` at once: ice is low friction *and* low
/// acceleration, mud is low speed *and* high friction, and a slow-effect is
/// both again. A friction multiplier would have been the first of five.
final class Surfaces {
  const Surfaces(this._byName, {this.fallback = const MovementTuning()});

  /// Nothing named, everything ordinary. What a game gets before it decides it
  /// wants ice.
  const Surfaces.plain() : this(const <String, MovementTuning>{});

  /// What a platformer usually wants, and a reasonable place to start.
  ///
  /// The numbers are chosen against a runner who walks at six metres a second
  /// and stops in about a fifth of a second on stone.
  factory Surfaces.common() => const Surfaces(<String, MovementTuning>{
        'ice': MovementTuning(
          // Almost no grip: you keep what you had and gather speed slowly.
          groundFriction: 3.0,
          groundAcceleration: 12.0,
        ),
        'mud': MovementTuning(
          walkSpeed: 2.6,
          sprintSpeed: 3.4,
          groundAcceleration: 30.0,
          groundFriction: 70.0,
          jumpSpeed: 6.0,
        ),
      });

  final Map<String, MovementTuning> _byName;

  /// The numbers for a floor nobody named, or one named nothing special.
  final MovementTuning fallback;

  /// What standing on [surface] feels like. A name this table has never heard
  /// of is ordinary ground — a level may name a surface for its footstep sound
  /// alone, and that must not silently change how it walks.
  MovementTuning tuningFor(String? surface) =>
      surface == null ? fallback : (_byName[surface] ?? fallback);

  /// Whether this table has an opinion about [surface]. For a game deciding
  /// whether a floor is worth a sound.
  bool knows(String surface) => _byName.containsKey(surface);

  Iterable<String> get names => _byName.keys;
}

/// The collision bits this genre gives its own geometry.
///
/// **Declared here and not in the engine**, and that is the rule rather than
/// a preference: `CollisionLayers` has `world`, `player`, `monster`, `pickup`
/// and `trigger`, which are facts about any game with bodies in it. "You may
/// pass upwards through this" is a platformer's idea, and an engine that knew
/// the word would be an engine written for one genre.
abstract final class PlatformerLayers {
  /// Platforms you jump up through and land on top of.
  ///
  /// Bit six: the engine uses nought to five, and bit three is spare there
  /// rather than free — taking it would be borrowing a number somebody else
  /// may name.
  static const int oneWay = 1 << 6;
}
