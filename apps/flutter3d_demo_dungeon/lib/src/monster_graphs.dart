import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' hide Pose;
import 'package:vector_math/vector_math.dart';

import 'monster_looks.dart';

/// How the crypt's monsters move — N1: an animation graph over each
/// model's own clips, a head that turns to watch whoever it has seen, and
/// feet put on whatever floor is under them.
final class MonsterGraphs implements ActorGraphs {
  /// [lookAt] says where a watching monster looks — the player's eyes —
  /// in the world; null, or a null from it, watches nothing. [groundAt] says
  /// how high the floor is under a point in the world, or null where there
  /// is none near; without it the feet stay where the clips put them.
  MonsterGraphs({this.lookAt, this.groundAt});

  final Vector3? Function()? lookAt;
  final double? Function(Vector3 at)? groundAt;

  /// The most a foot is put up or down, m: a stair's riser. Past it the
  /// floor under a foot is a ledge it is not standing on, and the foot is
  /// left where the clip put it — as it is where there is no floor near.
  static const double mostStep = 0.4;

  /// How long feet take to plant or let go, s.
  static const double plantSeconds = 0.2;

  /// Scratch for an ankle's place, asked twice a step per monster.
  final Matrix4 _ankle = Matrix4.identity();

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
  ///
  /// The speed is the body's along the floor — unless [wish] is given, for a
  /// body its own stride moves: then its velocity is the last stride, and a
  /// graph asked to walk by it would never leave its idle. How fast the
  /// brain asked to go is the body's walking speed by the wish's length.
  static void writeParameters(
    Actor actor,
    AnimationParameters parameters, {
    Vector3? wish,
  }) {
    final state = actor.isAlive
        ? DungeonMonsters.brainOf(actor)?.state ?? MonsterState.idle
        : MonsterState.dead;
    final code = stateCodes.indexOf(state);
    parameters.setInteger('state', code < 0 ? 0 : code);
    final body = actor.body;
    final double speed;
    if (body == null) {
      speed = 0.0;
    } else if (wish != null) {
      speed =
          body.tuning.walkSpeed * math.min(1.0, Vector2(wish.x, wish.z).length);
    } else {
      speed = Vector2(body.velocity.x, body.velocity.z).length;
    }
    parameters.setFloat('speed', speed);
  }

  /// A look on the head, where the model has one: what faced +Z at rest —
  /// where a glTF character faces — turned to whatever it watches.
  ///
  /// And a plant on the legs, where the model has the Quaternius legs: hip,
  /// knee and ankle under the body, and each foot a bone of its own on the
  /// root that the clips put where the ankle is.
  @override
  void dress(Actor actor, AnimationGraph graph, ModelInstance model) =>
      dressNamed(graph, <String?>[for (final n in model.nodes) n.name]);

  /// [dress] by the nodes' [names], in the pose's order — from a model on
  /// screen or from its document, read before there is one.
  static void dressNamed(AnimationGraph graph, List<String?> names) {
    int joint(String name) => names.indexOf(name);
    final head = joint('Head');
    if (head >= 0) {
      graph.goals.add(
        LookGoal(
          joint: head,
          forward: Vector3(0.0, 0.0, 1.0),
          limit: lookLimit,
          weight: 0.0,
        ),
      );
    }
    final legs = <FootLeg>[
      for (final side in const <String>['L', 'R'])
        if (<int>[
              joint('UpperLeg.$side'),
              joint('LowerLeg.$side'),
              joint('LowerLeg.${side}_end'),
            ]
            case [final hip, final knee, final ankle]
            when hip >= 0 && knee >= 0 && ankle >= 0)
          FootLeg(
            root: hip,
            mid: knee,
            tip: ankle,
            foot: switch (joint('Foot.$side')) {
              < 0 => null,
              final foot => foot,
            },
            poleJoint: switch (joint('PoleTarget.$side')) {
              < 0 => null,
              final pole => pole,
            },
          ),
    ];
    final hips = joint('Body');
    if (legs.length == 2 && hips >= 0) {
      graph.goals.add(FootPlantGoal(hips: hips, legs: legs, weight: 0.0));
    }
  }

  @override
  void drive(Actor actor, AnimationGraph graph, ModelInstance model) =>
      _aim(actor, graph, model.root.worldMatrix);

  /// The graph [actor] is animated by in the simulation's step, over
  /// [document]'s clips and nodes, dressed as [dress] dresses one on screen;
  /// null for a model with no idle, which keeps naming its clips.
  AnimationGraph? graphOver(Actor actor, ModelDocument document) {
    final machine = machineFor(actor, document.animations);
    if (machine == null) return null;
    final graph = AnimationGraph(
      machine: machine,
      clips: document.animations,
      pose: Pose.fromNodes(document.nodes),
    );
    dressNamed(graph, <String?>[for (final n in document.nodes) n.name]);
    return graph;
  }

  /// `ActorAnimations.write`: what [actor]'s brain decided into its graph,
  /// and where its head looks and its feet stand, before the step moves it
  /// — the model placed where `ActorVisuals` places it, from the actor
  /// alone, since the simulation has no model to ask.
  void step(Actor actor, AnimationGraph graph, Vector3 wish) => _aim(
    actor,
    graph,
    modelOf(actor),
    wish: graph.rootNode == null ? null : wish,
  );

  /// Where `ActorVisuals` draws [actor]'s model, from the body alone.
  static Matrix4 modelOf(Actor actor) => switch (actor.body) {
    final body? => ActorVisuals.modelMatrixAt(actor, body.position),
    null => Matrix4.identity(),
  };

  /// Parameters, the look and the feet, for a model placed by [toWorld].
  ///
  /// **Fades decided from the goals themselves** — fading towards one or
  /// towards nought already — rather than from a flag kept beside them: the
  /// goals are in a snapshot and a flag is not, and a restored run must
  /// decide the same as the run it restores.
  void _aim(
    Actor actor,
    AnimationGraph graph,
    Matrix4 toWorld, {
    Vector3? wish,
  }) {
    writeParameters(actor, graph.parameters, wish: wish);
    final toPose = Matrix4.inverted(toWorld);
    _plant(actor, graph, toWorld, toPose);
    final look = graph.goals.whereType<LookGoal>().firstOrNull;
    if (look == null) return;
    final target = lookAt?.call();
    final watch = target != null && shouldWatch(actor);
    if (look.fadingTo != (watch ? 1.0 : 0.0)) {
      look.fadeTo(watch ? 1.0 : 0.0, lookSeconds);
    }
    if (target != null) look.target.setFrom(toPose.transform3(target.clone()));
  }

  /// Each foot's floor, from [groundAt] under where the last pose left the
  /// ankle, brought into the model's space; planted while the monster is
  /// alive and on the ground, let go in the air and when it dies.
  void _plant(
    Actor actor,
    AnimationGraph graph,
    Matrix4 toWorld,
    Matrix4 toPose,
  ) {
    final plant = graph.goals.whereType<FootPlantGoal>().firstOrNull;
    final ground = groundAt;
    if (plant == null || ground == null) return;
    final on = actor.isAlive && (actor.body?.isGrounded ?? false);
    if (plant.fadingTo != (on ? 1.0 : 0.0)) {
      plant.fadeTo(on ? 1.0 : 0.0, plantSeconds);
    }
    // Let go and fading no more: nothing to aim, so no rays.
    if (!on && plant.weight == 0.0) return;
    for (final leg in plant.legs) {
      final at = toWorld.transform3(
        graph.pose.worldMatrixOf(leg.tip, _ankle).getTranslation(),
      );
      final floor = ground(at);
      final under = floor == null
          ? 0.0
          : toPose.transform3(Vector3(at.x, floor, at.z)).y;
      leg.ground = under.abs() > mostStep ? 0.0 : under;
    }
  }

  /// Whether [actor] watches: alive, and in a state of having seen someone.
  static bool shouldWatch(Actor actor) =>
      actor.isAlive && watching.contains(DungeonMonsters.brainOf(actor)?.state);
}
