/// Which way an actor's model faces, and how its animation ends.
///
///     flutter test test/actor_visuals_test.dart
///
/// **Both of these arrived with the models and neither could have arrived
/// before them**, which is what makes them worth a file. A capsule is round
/// about the axis it spins on, so it cannot face the wrong way; a capsule has
/// no clips, so it cannot loop the wrong one. Every monster in the crypt did
/// both from the moment it stopped being a capsule, and both were reported by
/// somebody playing rather than by anything here:
///
/// * "лягушка движется (и падает) спиной вперёд" — an actor's yaw points down
///   -Z and a glTF character faces +Z, half a turn apart.
/// * "почему анимация падения зациклена была?" — `AnimationPlayer.wrap`
///   defaults to looping, so a death clip restarted the instant it ended.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show Issue;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// One actor with a body and health, in a world with nothing else in it.
Actor _actor({double health = 10.0}) {
  final world = CollisionWorld();
  final system = ActorSystem(world: world, random: GameRandom(1));
  return system.spawn(
    body: CharacterController(world: world),
    health: Health(health),
  );
}

void main() {
  group('what is drawn faces where the actor is going', () {
    test('a capsule is turned by the actor yaw and nothing else', () {
      // Round about the axis it spins on, so a capsule cannot show a facing
      // error — which is why this one arrived with the models.
      final actor = _actor();
      expect(ActorVisuals.yawFor(actor, model: false), equals(actor.yaw));
    });

    test('and a model is turned half a turn further', () {
      // Reported from play: "лягушка движется (и падает) спиной вперёд".
      // An actor's yaw points down -Z at nought and a glTF character faces +Z.
      //
      // Mutation: return `actor.yaw` for a model too — fails, and so does the
      // round trip below.
      final actor = _actor();
      final turned = ActorVisuals.yawFor(actor, model: true);

      expect(turned - actor.yaw, closeTo(math.pi, 1e-9));
    });

    test('and half a turn is exactly the wrong way round', () {
      // The property worth pinning rather than the number: what a model is
      // turned by must send its own forward to the actor's. Mutation: a
      // quarter turn — the dot product comes out nought and this fails, while
      // a test comparing against `pi` would only fail on the constant.
      final actor = _actor();
      final drawn = ActorVisuals.yawFor(actor, model: true);
      // Where the actor is going, and where the model's own +Z ends up.
      final going = Vector3(-math.sin(actor.yaw), 0.0, -math.cos(actor.yaw));
      final faces = Vector3(math.sin(drawn), 0.0, math.cos(drawn));

      expect(going.dot(faces), closeTo(1.0, 1e-9));
    });
  });

  group('an animation ends the way the actor did', () {
    test('a living actor loops', () {
      // Idle, walking and running all have to come round again; a monster that
      // held the last frame of its run would slide down the corridor in a pose.
      expect(ActorVisuals.wrapFor(_actor()), equals(AnimationWrap.loop));
    });

    test('and a dead one holds its final pose', () {
      // Mutation: return `AnimationWrap.loop` unconditionally, which is what
      // the default did and what the bug was — fails here and nowhere else.
      final actor = _actor();
      actor.health!.damage(999.0);

      expect(actor.isAlive, isFalse, reason: 'the fixture must actually die');
      expect(ActorVisuals.wrapFor(actor), equals(AnimationWrap.once));
    });

    test('and it is dying that decides it, not the clip it is playing', () {
      // The name belongs to the export — two of the crypt's three models spell
      // their hit clip differently. Mutation: switch on a clip named 'Death'
      // and this still passes, which is the point: nothing here mentions a
      // clip, so a fourth model whose artist called it `die` is covered too.
      final actor = _actor();
      final alive = ActorVisuals.wrapFor(actor);
      actor.health!.damage(999.0);

      expect(alive, isNot(equals(ActorVisuals.wrapFor(actor))));
    });
  });

  group('drawn between two steps', () {
    test('an actor is halfway across at half an alpha', () {
      // **Nothing here interpolated at all.** `sync` read the authoritative
      // post-step position, so every monster moved in 60 Hz jumps while the
      // player's own camera was smooth — `Player.eyeFrom` documents needing
      // the interpolated position and gets it. On a 60 Hz display the two are
      // indistinguishable, which is why this survived; on anything faster the
      // difference is the whole reason `InterpolatedVector3` exists.
      //
      // Mutation: return `actor.position!` from `_drawAt` regardless. The node
      // lands on 2.0 rather than halfway, because a frame between two steps
      // draws where the later step already put it.
      final device = FakeBackend();
      final scene = Scene();
      final visuals = ActorVisuals(
        scene,
        appearance: const _PlainLook(),
        device: device,
      );
      final actor = _actor();
      visuals.add(actor);

      actor.body!.teleport(Vector3(0.0, 0.0, 0.0));
      visuals.recordStep();
      actor.body!.teleport(Vector3(2.0, 0.0, 0.0));
      visuals.recordStep();

      visuals.sync(0.5);

      expect(scene.meshes.single.readPosition().x, closeTo(1.0, 1e-6));
    });

    test('and a game that records nothing draws where it always did', () {
      // The default keeps every existing caller exactly as it was: an
      // application that has not wired the per-step call up gets the
      // authoritative position, which is what this class did before.
      final device = FakeBackend();
      final scene = Scene();
      final visuals = ActorVisuals(
        scene,
        appearance: const _PlainLook(),
        device: device,
      );
      final actor = _actor();
      visuals.add(actor);
      actor.body!.teleport(Vector3(2.0, 0.0, 0.0));

      visuals.sync();

      expect(scene.meshes.single.readPosition().x, closeTo(2.0, 1e-6));
    });
  });

  group('the layers an actor is drawn on', () {
    test('a capsule goes on the layers the game names', () {
      // The sensor's whole premise: `RenderSettings.xray` names a layer, and
      // the actors have to be on it for the silhouettes to be theirs and not
      // the furniture's. On the node the render list asks, not on the actor.
      //
      // Mutation: drop `..layerMask = layerMask` from `add`. The capsule stays
      // on the default layer alone, and the mask below reads as one.
      final scene = Scene();
      final visuals = ActorVisuals(
        scene,
        appearance: const _PlainLook(),
        device: FakeBackend(),
        layerMask: 1 | (1 << 1),
      )..add(_actor());

      expect(scene.meshes.single.layerMask, 1 | (1 << 1));
      visuals.dispose();
    });

    test('and on the default layer alone when the game says nothing', () {
      // Every game before the sensor named no layer, and every one of them
      // draws exactly as it did.
      final scene = Scene();
      final visuals = ActorVisuals(
        scene,
        appearance: const _PlainLook(),
        device: FakeBackend(),
      )..add(_actor());

      expect(scene.meshes.single.layerMask, 1);
      visuals.dispose();
    });
  });

  group('letting a level go', () {
    test('an actor removed takes its node out of the scene', () {
      // **There was `add` and no counterpart.** An actor removed through
      // `ActorSystem.remove` kept its node here for ever, and the next `sync`
      // read `actor.position!` on an entity whose `Body` was gone — a throw
      // from inside the render path. Latent only because nothing calls that
      // method today, which is the worst kind of latent.
      //
      // Mutation: drop the `_nodes.remove` line. The node stays in the scene
      // and the count below does not fall.
      final device = FakeBackend();
      final scene = Scene();
      final visuals = ActorVisuals(
        scene,
        appearance: const _PlainLook(),
        device: device,
      );
      final actor = _actor();
      visuals.add(actor);
      expect(scene.meshes, hasLength(1));

      visuals.remove(actor);

      expect(scene.meshes, isEmpty);
      visuals.sync();
    });

    test('and disposing empties the scene and hands the meshes back', () {
      // `SharedMeshes` has said in its own doc since it was written that "a GPU
      // resource that outlives the level owning it is a leak nobody notices",
      // and offered no way to end one — so every level load uploaded another
      // capsule and nothing ever released one.
      //
      // Mutation: make `SharedMeshes.dispose` clear the map without releasing.
      // The scene empties and the device is handed nothing back, which is
      // exactly the shape of the bug: it looks torn down.
      final device = FakeBackend();
      final scene = Scene();
      final visuals = ActorVisuals(
        scene,
        appearance: const _PlainLook(),
        device: device,
      )..add(_actor());

      visuals.dispose();

      expect(scene.meshes, isEmpty);
      expect(
        device.releasedGeometry,
        hasLength(2),
        reason: 'a mesh is a vertex buffer and an index buffer',
      );
    });
  });

  group('a corpse a game takes over', () {
    test('is handed over once with the pose it died in, then left alone, '
        'and let go with the level', () async {
      // N1: a game that gives its monsters ragdolls takes a dead modelled
      // actor's pose over through `ActorCorpses`.
      //
      // Mutations: drop the `_taken` check in `animate` (the player keeps
      // playing: the clip time moves), in `sync` (the root moves), or the
      // kept pose (`previous` arrives null).
      // The bundle is asked first and must be able to say no; then, in a
      // debug build, a source under `assets_src/` is read from the disk.
      // This package ships none, so the hero is put there for the test.
      TestWidgetsFlutterBinding.ensureInitialized();
      final sources = Directory('assets_src');
      expect(sources.existsSync(), isFalse, reason: 'left from another run');
      File('../flutter3d/test/fixtures/hero.glb').copySync(
        (File('assets_src/models/hero.glb')..createSync(recursive: true)).path,
      );
      addTearDown(() => sources.deleteSync(recursive: true));
      final corpses = _Corpses();
      final visuals = ActorVisuals(
        Scene(),
        appearance: const _HeroLook(),
        device: FakeBackend(),
        corpses: corpses,
        onIssue: (Issue issue) => fail('$issue'),
      );
      final actor = _actor();
      visuals.add(actor);
      await visuals.settled;
      for (var i = 0; i < 3; i++) {
        visuals
          ..animate(1.0 / 60.0)
          ..sync();
      }
      expect(corpses.begun, isEmpty, reason: 'alive');
      expect(corpses.steps, 3);

      actor.health!.damage(100.0);
      visuals.animate(1.0 / 60.0);
      expect(corpses.begun, <Actor>[actor]);
      expect(corpses.previous, isNotNull);
      expect(
        corpses.previous,
        hasLength(corpses.model!.skeletons.first.jointCount),
      );

      final player = corpses.model!.player!;
      final clock = player.time;
      final root = corpses.model!.root.worldMatrix.getTranslation();
      actor.body!.teleport(Vector3(5.0, 0.0, 5.0));
      for (var i = 0; i < 5; i++) {
        visuals
          ..animate(1.0 / 60.0)
          ..sync();
      }
      expect(corpses.begun, hasLength(1), reason: 'asked once');
      expect(player.time, clock, reason: 'its clip is not played on');
      expect(corpses.model!.root.worldMatrix.getTranslation(), root);

      visuals.remove(actor);
      expect(corpses.ended, <Actor>[actor]);
      visuals.dispose();
      expect(corpses.disposed, isTrue);
    });
  });

  group('an actor a game animates by a graph', () {
    test('gets one over its model, driven and written once a frame', () async {
      // N1. Mutations: skip `drive` (the graph never leaves idle), or the
      // `writeTo` (the joints never move).
      TestWidgetsFlutterBinding.ensureInitialized();
      final sources = Directory('assets_src');
      expect(sources.existsSync(), isFalse, reason: 'left from another run');
      File('../flutter3d/test/fixtures/hero.glb').copySync(
        (File('assets_src/models/hero.glb')..createSync(recursive: true)).path,
      );
      addTearDown(() => sources.deleteSync(recursive: true));
      final graphs = _Graphs();
      final visuals = ActorVisuals(
        Scene(),
        appearance: const _HeroLook(),
        device: FakeBackend(),
        graphs: graphs,
      );
      final actor = _actor();
      visuals.add(actor);
      await visuals.settled;
      final graph = visuals.graphOf(actor)!;
      expect(graph.state, 'stand');
      expect(graphs.dressed, 1);
      final before = <Matrix4>[
        for (final j in _skeletonOf(visuals, actor).joints)
          j.localMatrix.clone(),
      ];
      graphs.running = true;
      for (var i = 0; i < 30; i++) {
        visuals.animate(1.0 / 60.0);
      }
      expect(graphs.driven, 30);
      expect(graph.state, 'run');
      final joints = _skeletonOf(visuals, actor).joints;
      final moved = <int>[
        for (var i = 0; i < joints.length; i++)
          if (!_near(joints[i].localMatrix, before[i])) i,
      ];
      expect(moved, isNotEmpty, reason: 'the run is written into the joints');
      // The run's markers are heard, whose and in which state.
      final heard = <({Actor actor, String state, String name})>[];
      for (var i = 0; i < 60; i++) {
        visuals.animate(1.0 / 60.0);
        heard.addAll(visuals.markersPassed);
      }
      expect(heard, isNotEmpty);
      expect(heard.first, (actor: actor, state: 'run', name: 'step'));
    });
  });

  group('a loading screen', () {
    test('settles once every model it asked for has been answered', () async {
      // `N3`: a warm-up run before the models arrive never sees their
      // meshes. A model that will not load is an answer too — the actor
      // stays a capsule — and it is one a test can wait for without a file
      // to read. A source path, so the answer comes from the disk and takes
      // real time rather than a microtask or two.
      final order = <String>[];
      final visuals = ActorVisuals(
        Scene(),
        appearance: const _ModelLook(),
        device: FakeBackend(),
        onIssue: (Issue issue) => order.add('answered'),
      )..add(_actor());
      final settled = visuals.settled.then((_) => order.add('settled'));
      expect(order, isEmpty, reason: 'the load has only just begun');

      await settled;

      // Mutation: complete `settled` at once. It then settles before the
      // load has answered.
      expect(order, <String>['answered', 'settled']);
    });
  });
}

/// Asks for a model nobody packaged.
final class _ModelLook implements ActorAppearance {
  const _ModelLook();

  @override
  String meshKeyFor(Actor actor) => 'modelled';

  @override
  Material materialFor(Actor actor) => Material();

  @override
  String? modelFor(Actor actor) => 'assets_src/models/nobody_packaged_this.glb';

  @override
  List<String> clipsFor(Actor actor) => const <String>[];
}

/// One capsule, one material, no models — the least a bridge needs to draw.
final class _PlainLook implements ActorAppearance {
  const _PlainLook();

  @override
  String meshKeyFor(Actor actor) => 'plain';

  @override
  Material materialFor(Actor actor) => Material();

  @override
  String? modelFor(Actor actor) => null;

  @override
  List<String> clipsFor(Actor actor) => const <String>[];
}

/// The hero from flutter3d's fixtures: a rigged model with clips.
final class _HeroLook implements ActorAppearance {
  const _HeroLook();

  @override
  String meshKeyFor(Actor actor) => 'hero';

  @override
  Material materialFor(Actor actor) => Material();

  @override
  String? modelFor(Actor actor) => 'assets_src/models/hero.glb';

  @override
  List<String> clipsFor(Actor actor) => const <String>[
    'CharacterArmature|Idle',
  ];
}

/// Takes every corpse, and remembers what it was told.
final class _Corpses implements ActorCorpses {
  final List<Actor> begun = <Actor>[];
  final List<Actor> ended = <Actor>[];
  ModelInstance? model;
  List<Matrix4>? previous;
  int steps = 0;
  bool disposed = false;

  @override
  bool begin(
    Actor actor,
    ModelInstance model, {
    List<Matrix4>? previous,
    double dt = 1.0 / 60.0,
  }) {
    begun.add(actor);
    this.model = model;
    this.previous = previous;
    return true;
  }

  @override
  void step(double dt) => steps++;

  @override
  void end(Actor actor) => ended.add(actor);

  @override
  void dispose() => disposed = true;
}

/// The hero's first skeleton, as [visuals] dressed [actor] in it.
Skeleton _skeletonOf(ActorVisuals visuals, Actor actor) =>
    visuals.modelOf(actor)!.skeletons.first;

bool _near(Matrix4 a, Matrix4 b) {
  for (var i = 0; i < 16; i++) {
    if ((a.storage[i] - b.storage[i]).abs() > 1e-5) return false;
  }
  return true;
}

/// Stands, and runs when told to.
final class _Graphs implements ActorGraphs {
  bool running = false;
  int driven = 0;
  int dressed = 0;

  @override
  AnimationStateMachine? machineFor(Actor actor, List<AnimationClip> clips) =>
      AnimationStateMachine(
        parameters: AnimationParameterSchema(<AnimationParameter>[
          const AnimationParameter.boolean('running'),
        ]),
        entry: 'stand',
        states: const <AnimationState>[
          AnimationState(name: 'stand', clip: 'CharacterArmature|Idle'),
          AnimationState(
            name: 'run',
            clip: 'CharacterArmature|Run',
            markers: <AnimationMarker>[AnimationMarker(0.0, 'step')],
          ),
        ],
        transitions: <AnimationTransition>[
          AnimationTransition(
            from: 'stand',
            to: 'run',
            conditions: const <AnimationCondition>[BoolCondition('running')],
            duration: 0.1,
          ),
        ],
      );

  @override
  void dress(Actor actor, AnimationGraph graph, ModelInstance model) =>
      dressed++;

  @override
  void drive(Actor actor, AnimationGraph graph, ModelInstance model) {
    driven++;
    graph.parameters.setBool('running', running);
  }
}
