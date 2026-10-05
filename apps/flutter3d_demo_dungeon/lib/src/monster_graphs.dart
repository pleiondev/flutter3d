import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' hide Pose;
import 'package:vector_math/vector_math.dart';

import 'monster_looks.dart';

/// How the crypt's monsters move — N1: an animation graph over each
/// model's own clips, and a head that turns to watch whoever it has seen.
final class MonsterGraphs implements ActorGraphs {
  /// [lookAt] says where a watching monster looks — the player's eyes —
  /// in the world; null, or a null from it, watches nothing.
  MonsterGraphs({this.lookAt});

  final Vector3? Function()? lookAt;

  /// The states a monster turns its head to watch in.
  static final Set<MonsterState> watching = <MonsterState>{
    MonsterState.alert,
    MonsterState.chase,
    MonsterState.attack,
  };

  /// How far a head turns from the body's facing to watch, radians, and
  /// how long it takes to turn to it and away.
  static const double lookLimit = 1.0;
  static const double lookSeconds = 0.3;

  final Expando<bool> _watching = Expando<bool>('watching');

  /// What a monster is doing, as the graph's `state` parameter reads it.
  static const List<MonsterState> stateCodes = <MonsterState>[
    MonsterState.idle,
    MonsterState.alert,
    MonsterState.chase,
    MonsterState.attack,
    MonsterState.hurt,
    MonsterState.dead,
  ];

  /// A foot down at the start of a stride and another halfway: the two of a
  /// walk or a run cycle, marked on the state since the crypt's clips name
  /// none. Each is a footstep where the monster is.
  static const List<AnimationMarker> footfalls = <AnimationMarker>[
    AnimationMarker(0.0, 'step'),
    AnimationMarker(0.5, 'step'),
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
            markers: footfalls,
          )
        else if (stride != null)
          AnimationState(name: 'move', clip: stride, markers: footfalls),
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
  static void writeParameters(Actor actor, AnimationParameters parameters) {
    final state = actor.isAlive
        ? DungeonMonsters.brainOf(actor)?.state ?? MonsterState.idle
        : MonsterState.dead;
    final code = stateCodes.indexOf(state);
    parameters.setInteger('state', code < 0 ? 0 : code);
    final v = actor.body?.velocity;
    parameters.setFloat('speed', v == null ? 0.0 : Vector2(v.x, v.z).length);
  }

  /// A look on the head, where the model has one: what faced +Z at rest —
  /// where a glTF character faces — turned to whatever it watches.
  @override
  void dress(Actor actor, AnimationGraph graph, ModelInstance model) {
    final head = model.nodes.indexWhere((n) => n.name == 'Head');
    if (head < 0) return;
    graph.goals.add(
      LookGoal(
        joint: head,
        forward: Vector3(0.0, 0.0, 1.0),
        limit: lookLimit,
        weight: 0.0,
      ),
    );
  }

  @override
  void drive(Actor actor, AnimationGraph graph, ModelInstance model) {
    writeParameters(actor, graph.parameters);
    final look = graph.goals.whereType<LookGoal>().firstOrNull;
    if (look == null) return;
    final target = lookAt?.call();
    final watch = target != null && shouldWatch(actor);
    if (_watching[actor] != watch) {
      _watching[actor] = watch;
      look.fadeTo(watch ? 1.0 : 0.0, lookSeconds);
    }
    if (target != null) {
      look.target.setFrom(
        Matrix4.inverted(model.root.worldMatrix).transform3(target.clone()),
      );
    }
  }

  /// Whether [actor] watches: alive, and in a state of having seen someone.
  static bool shouldWatch(Actor actor) =>
      actor.isAlive && watching.contains(DungeonMonsters.brainOf(actor)?.state);
}
