import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:vector_math/vector_math.dart';

/// What this game's monsters are made of, and what they are doing.
///
/// The mesh, the placement and the death pose are the bridge's; the models, the
/// clips and the three colours are this game's.
final class DungeonMonsters implements ActorAppearance {
  const DungeonMonsters();

  /// The engine hands over an `Actor`; what kind of thing it is lives on its
  /// brain, and reading that here is the application admitting it is a shooter.
  /// A platformer's appearance would cast to its own brain and never see a
  /// `MonsterState` at all.
  @override
  String meshKeyFor(Actor actor) => _brainOf(actor)?.def.name ?? 'actor';

  @override
  String? modelFor(Actor actor) => modelsForKind[_brainOf(actor)?.def.name];

  /// Which clip, from what the brain is doing.
  ///
  /// **A list per state rather than a name, because the models disagree.** These
  /// are three third-party exports and they do not carry the same clips: the
  /// runner has `Run`, `Punch` and `HitReact`; the other two have neither `Run`
  /// nor `Punch`, and spell the third `HitRecieve` — with the typo, which is in
  /// the file and is not ours to quietly correct.
  ///
  /// So each state names what it would like in order of preference, and
  /// `crossFadeToNamed` reports whether the model had it. A model with none of
  /// them keeps whatever it was playing, which is what a model with no
  /// animation at all wants anyway.
  ///
  /// This is the shape `RunnerLooks` has in the platformer and for the same
  /// reason: on the way in a state, on the way out a value, and no renderer
  /// anywhere near it.
  @override
  List<String> clipsFor(Actor actor) {
    final brain = _brainOf(actor);
    if (brain == null) return const <String>[];
    return clipsForState[brain.state] ?? const <String>[];
  }

  /// Every clip each state would accept, best first.
  ///
  /// Public because it is the part worth testing on its own: a state with an
  /// empty list is a monster frozen mid-stride, and there is no run of the game
  /// that makes that obvious — you have to catch one in that state and look.
  static final Map<MonsterState, List<String>>
  clipsForState = <MonsterState, List<String>>{
    MonsterState.idle: <String>['Idle'],
    // The pause before it comes for you. Deliberately the same as idle: the
    // hesitation is what the player reads, and giving it its own gesture makes
    // a monster that waves before charging.
    MonsterState.alert: <String>['Idle'],
    MonsterState.chase: <String>['Run', 'Walk'],
    MonsterState.attack: <String>['Punch', 'Bite_Front', 'Idle'],
    // Both spellings, and the misspelt one is in two of the three files.
    MonsterState.hurt: <String>['HitReact', 'HitRecieve', 'Idle'],
    MonsterState.dead: <String>['Death'],
  };

  @override
  Material materialFor(Actor actor) {
    final brain = _brainOf(actor);
    // Brightened for a moment after a hit, which is the cheapest damage
    // feedback there is and the one whose absence makes a fight feel
    // unresponsive. Only reaches a monster still drawn as a capsule — a model
    // brings its own materials, and a hit flash on one is a job for the shader
    // rather than for a colour swap.
    if (brain?.state == MonsterState.hurt) return _struck;
    return _materials[brain?.def.name] ?? _unknown;
  }

  static ChaseBrain? _brainOf(Actor actor) {
    final brain = actor.brain;
    return brain is ChaseBrain ? brain : null;
  }

  /// A model per kind. Silhouette rather than colour is what tells them apart
  /// in a corridor lit by one torch: a low quadruped, a tall robed figure and
  /// something twice your width.
  ///
  /// Public for the same reason [clipsForState] is: a kind missing from here
  /// is a monster silently drawn as a capsule, and a test that only checked
  /// the files on disk would pass — which it did, until a mutation said so.
  static const Map<String, String> modelsForKind = <String, String>{
    'runner': 'assets/models/monster_runner.glb',
    'shooter': 'assets/models/monster_shooter.glb',
    'tank': 'assets/models/monster_tank.glb',
  };

  /// Materials by kind, for anything still drawn as a capsule — an actor whose
  /// model is missing, or one this game has not given a model to.
  static final Map<String, Material> _materials = <String, Material>{
    'runner': Material(
      baseColor: Vector4(0.52, 0.20, 0.18, 1.0),
      roughness: 0.7,
    ),
    'shooter': Material(
      baseColor: Vector4(0.22, 0.32, 0.52, 1.0),
      roughness: 0.6,
    ),
    'tank': Material(
      baseColor: Vector4(0.30, 0.28, 0.16, 1.0),
      roughness: 0.85,
    ),
  };

  static final Material _struck = Material(
    baseColor: Vector4(1.4, 0.9, 0.8, 1.0),
    roughness: 0.6,
  );

  /// Shared rather than built per call: [ActorAppearance.materialFor] runs for
  /// every monster every frame, and a default that allocated would allocate once
  /// a frame per monster.
  static final Material _unknown = Material();
}
