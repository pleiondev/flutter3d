import '../save/state_digest.dart';
import 'level.dart';

/// What changed between two versions of one level, split by who has to act
/// on it.
///
/// **The split is the whole point.** An editor saves a level while the game
/// is running it, and the game has two ways to take the change. What only the
/// picture reads — a light, a material, the fog, the music — can be patched
/// into the running scene as it is, and nothing the simulation computed is
/// disturbed. What the simulation reads — brushes it collides with, entities
/// it spawned, the ground — cannot: patched in place, the run would carry on
/// from a state no run of the new level could have reached, and a replay of
/// it would disagree with the run it recorded. That half goes through a
/// timeline branch instead (`RunTimeline.swapLevel`).
///
/// **Conservative on purpose.** A brush whose only change is its material
/// looks presentational, and usually is — but a brush's surface falls back to
/// its material, and a surface is what footsteps and friction read. A
/// classifier that is sometimes too careful costs a replay; one that is
/// sometimes too bold costs a run that cannot be reproduced. So anything
/// under [simulation] is judged by the whole part, not by a guess at which of
/// its fields the game reads.
final class LevelDiff {
  const LevelDiff({
    this.lights = const <int>[],
    this.lightCountChanged = false,
    this.materials = const <String>[],
    this.fog = false,
    this.music = false,
    this.simulation = const <String>[],
  });

  /// Lights changed in place, by index in the level's list.
  final List<int> lights;

  /// Lights were added or removed, so indices past the shorter list mean
  /// nothing; a presenter rebuilds the lights rather than patching them.
  final bool lightCountChanged;

  /// Materials added, removed or changed, by name.
  final List<String> materials;

  /// The fog's colour or density changed.
  final bool fog;

  /// The music changed.
  final bool music;

  /// Which parts the simulation reads changed: `brushes`, `entities`,
  /// `heightfield`, `recipes`, `next`. Empty when the change can be patched
  /// into a running scene without touching the run.
  final List<String> simulation;

  /// Whether nothing changed at all.
  bool get isEmpty =>
      lights.isEmpty &&
      !lightCountChanged &&
      materials.isEmpty &&
      !fog &&
      !music &&
      simulation.isEmpty;

  /// Whether the change can be patched in without a timeline branch.
  bool get presentationOnly => simulation.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'lights': lights,
    'lightCountChanged': lightCountChanged,
    'materials': materials,
    'fog': fog,
    'music': music,
    'simulation': simulation,
  };
}

/// Compares [before] and [after], part by part, through their documents.
///
/// Through `toJson` rather than field by field: the document is what a level
/// *is* to the editor that wrote it, and a field added to a part later is
/// compared the day it is added, with nothing here to remember.
LevelDiff diffLevel(Level before, Level after) {
  String digest(Object? json) => contentDigestHex(<String, Object?>{'v': json});
  bool differs(Object? a, Object? b) => digest(a) != digest(b);

  final oldLights = before.lights;
  final newLights = after.lights;
  final shared = oldLights.length < newLights.length
      ? oldLights.length
      : newLights.length;

  final names = <String>{...before.materials.keys, ...after.materials.keys};
  return LevelDiff(
    lights: <int>[
      for (var i = 0; i < shared; i++)
        if (differs(oldLights[i].toJson(), newLights[i].toJson())) i,
    ],
    lightCountChanged: oldLights.length != newLights.length,
    materials: <String>[
      for (final name in names)
        if (differs(
          before.materials[name]?.toJson(),
          after.materials[name]?.toJson(),
        ))
          name,
    ],
    fog:
        before.fogColor != after.fogColor ||
        before.fogDensity != after.fogDensity,
    music: before.music != after.music,
    simulation: <String>[
      if (differs(
        <Object?>[for (final b in before.brushes) b.toJson()],
        <Object?>[for (final b in after.brushes) b.toJson()],
      ))
        'brushes',
      if (differs(
        <Object?>[for (final e in before.entities) e.toJson()],
        <Object?>[for (final e in after.entities) e.toJson()],
      ))
        'entities',
      if (differs(before.heightfield?.toJson(), after.heightfield?.toJson()))
        'heightfield',
      if (differs(
        <Object?>[for (final r in before.recipes) r.toJson()],
        <Object?>[for (final r in after.recipes) r.toJson()],
      ))
        'recipes',
      if (before.next != after.next) 'next',
    ],
  );
}
