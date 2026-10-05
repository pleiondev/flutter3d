import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// What this game's monsters are made of, and what they are doing.
///
/// The mesh, the placement and the death pose are the bridge's; the models, the
/// clips and the three colours are this game's.
final class DungeonMonsters implements ActorAppearance, ActorGraphs {
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

  // MARK: - The graph

  /// What a monster is doing, as the graph's `state` parameter reads it.
  static const List<MonsterState> stateCodes = <MonsterState>[
    MonsterState.idle,
    MonsterState.alert,
    MonsterState.chase,
    MonsterState.attack,
    MonsterState.hurt,
    MonsterState.dead,
  ];

  /// Where a monster that can both walk and run is all walk, m/s, and where
  /// it is all run: the runner's own chasing speed. Between, the blend space
  /// mixes the two by speed, one stride at one phase.
  static const double walkAt = 1.5;
  static const double runAt = 5.4;

  /// The machine for a monster drawn with [clips]: idle, and moving while it
  /// chases — a walk and a run blended by its speed where the model has both,
  /// whichever it has where one; attacking, struck and dying by its brain's
  /// state, from whatever it was doing, with a fade into each. Built from
  /// the clips the model has, so the runner, which can run, and the shooter
  /// and the tank, which walk, are one definition. Null for a model with no
  /// idle to stand in.
  @override
  AnimationStateMachine? machineFor(Actor actor, List<AnimationClip> clips) {
    final have = <String>{for (final c in clips) ?c.name};
    String? pick(List<String> names) => names.where(have.contains).firstOrNull;
    final idle = pick(const <String>['Idle']);
    if (idle == null) return null;
    final walk = pick(const <String>['Walk']);
    final run = pick(const <String>['Run']);
    final attack = pick(const <String>['Punch', 'Bite_Front']);
    final hurt = pick(const <String>['HitReact', 'HitRecieve']);
    final death = pick(const <String>['Death']);
    int code(MonsterState state) => stateCodes.indexOf(state);
    CompareCondition isIn(MonsterState state) =>
        CompareCondition('state', AnimationComparison.equals, code(state));
    CompareCondition isNot(MonsterState state) =>
        CompareCondition('state', AnimationComparison.notEquals, code(state));
    final stride = walk ?? run;
    final moving = <String>['idle', if (stride != null) 'move'];
    final acting = <String>[...moving, if (attack != null) 'attack'];
    return AnimationStateMachine(
      parameters: AnimationParameterSchema(<AnimationParameter>[
        const AnimationParameter.integer('state'),
        const AnimationParameter.float('speed'),
      ]),
      entry: 'idle',
      states: <AnimationState>[
        AnimationState(name: 'idle', clip: idle),
        if (walk != null && run != null)
          AnimationState(
            name: 'move',
            blend: AnimationBlendSpace('speed', <BlendPoint>[
              BlendPoint(walkAt, walk),
              BlendPoint(runAt, run),
            ]),
          )
        else if (stride != null)
          AnimationState(name: 'move', clip: stride),
        if (attack != null) AnimationState(name: 'attack', clip: attack),
        if (hurt != null)
          AnimationState(name: 'hurt', clip: hurt, wrap: AnimationWrap.once),
        if (death != null)
          AnimationState(name: 'death', clip: death, wrap: AnimationWrap.once),
      ],
      transitions: <AnimationTransition>[
        if (stride != null) ...<AnimationTransition>[
          AnimationTransition(
            from: 'idle',
            to: 'move',
            conditions: <AnimationCondition>[
              isIn(MonsterState.chase),
              const CompareCondition('speed', AnimationComparison.greater, 0.3),
            ],
            duration: 0.2,
          ),
          AnimationTransition(
            from: 'move',
            to: 'idle',
            conditions: <AnimationCondition>[isNot(MonsterState.chase)],
            duration: 0.25,
          ),
          AnimationTransition(
            from: 'move',
            to: 'idle',
            conditions: <AnimationCondition>[
              const CompareCondition('speed', AnimationComparison.less, 0.1),
            ],
            duration: 0.25,
          ),
        ],
        if (attack != null) ...<AnimationTransition>[
          for (final from in moving)
            AnimationTransition(
              from: from,
              to: 'attack',
              conditions: <AnimationCondition>[isIn(MonsterState.attack)],
              duration: 0.1,
              priority: 1,
            ),
          AnimationTransition(
            from: 'attack',
            to: 'idle',
            conditions: <AnimationCondition>[isNot(MonsterState.attack)],
            duration: 0.2,
          ),
        ],
        if (hurt != null) ...<AnimationTransition>[
          for (final from in acting)
            AnimationTransition(
              from: from,
              to: 'hurt',
              conditions: <AnimationCondition>[isIn(MonsterState.hurt)],
              duration: 0.08,
              priority: 5,
            ),
          AnimationTransition(
            from: 'hurt',
            to: 'idle',
            conditions: <AnimationCondition>[isNot(MonsterState.hurt)],
            duration: 0.15,
          ),
        ],
        if (death != null)
          for (final from in <String>[...acting, if (hurt != null) 'hurt'])
            AnimationTransition(
              from: from,
              to: 'death',
              conditions: <AnimationCondition>[isIn(MonsterState.dead)],
              duration: 0.15,
              priority: 10,
            ),
      ],
    );
  }

  /// The brain's state and the body's speed along the floor. Dead is dead
  /// whatever the brain last said: health is the authority on that.
  @override
  void drive(Actor actor, AnimationParameters parameters) {
    final state = actor.isAlive
        ? _brainOf(actor)?.state ?? MonsterState.idle
        : MonsterState.dead;
    final code = stateCodes.indexOf(state);
    parameters.setInteger('state', code < 0 ? 0 : code);
    final v = actor.body?.velocity;
    parameters.setFloat('speed', v == null ? 0.0 : Vector2(v.x, v.z).length);
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
    'runner': 'assets_src/models/monster_runner.glb',
    'shooter': 'assets_src/models/monster_shooter.glb',
    'tank': 'assets_src/models/monster_tank.glb',
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
