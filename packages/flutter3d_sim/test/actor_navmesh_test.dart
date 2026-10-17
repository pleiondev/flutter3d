/// Actors walking to a point over a navigation mesh: through a doorway, over
/// a pit, and the same from a snapshot taken on the way.
///
///     dart test test/actor_navmesh_test.dart
///
/// The tree is one `goTo` leaf. What changes between the runs is only
/// whether the system has a mesh, and the claim is the difference: with it
/// the actor gets there, without it the actor walks into the wall between
/// and stays.
library;

import 'dart:convert';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// Meshes baked for the width of the bodies here, a default controller's
/// 0.35: a body is not given a mesh baked for anything narrower.
const NavMeshSettings _body = NavMeshSettings(agentRadius: 0.35);

Brush _box(double x0, double y0, double z0, double x1, double y1, double z1) =>
    Brush(
      center: Vector3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
      size: Vector3(x1 - x0, y1 - y0, z1 - z0),
    );

/// Two rooms either side of a wall, the doorway at its north end, so the
/// straight line between the rooms' middles meets the wall.
List<Brush> _rooms() => <Brush>[
  _box(-6, -1, -4, 6, 0, 4),
  _box(0, 0, -4, 0.5, 3, 1.5),
  _box(0, 2.5, 1.5, 0.5, 3, 3.5),
  _box(0, 0, 3.5, 0.5, 3, 4),
];

/// Two platforms either side of a pit a metre and a half wide.
List<Brush> _pit() => <Brush>[
  _box(-6, -1, -2, -0.75, 0, 2),
  _box(0.75, -1, -2, 6, 0, 2),
];

final BehaviorTree _toPost = BehaviorTree.read(const <String, Object?>{
  'kind': 'goTo',
  'key': 'post',
  'within': 0.5,
}, BehaviorKinds()).tree!;

/// One actor that walks to `post`, in a world built from [brushes].
final class _Walk {
  _Walk(
    List<Brush> brushes, {
    required Vector3 from,
    required Vector3 post,
    NavMesh? mesh,
  }) {
    for (final brush in brushes) {
      world.addBox(brush.center, brush.size);
    }
    world.update();
    if (mesh != null) system.navMeshes = <NavMesh>[mesh];
    final actor = system.spawn(
      body: CharacterController(world: world, position: from),
      brain: BehaviorBrain(_toPost),
      facing: Facing(),
      name: 'walker',
    );
    system.entities.set(
      actor.entity,
      Blackboard(
        values: <String, Object?>{
          'post': <double>[post.x, post.y, post.z],
        },
      ),
    );
  }

  final CollisionWorld world = CollisionWorld(properties: _world);
  late final ActorSystem system = ActorSystem(
    world: world,
    random: GameRandom(3),
  );

  Actor get walker => system.actors.single;
  Vector3 get position => walker.body!.position;

  void step() {
    system
      ..beginStep()
      ..step(_dt, focus: Vector3(0, -50, 0));
  }

  void steps(int n) {
    for (var i = 0; i < n; i++) {
      step();
    }
  }

  Map<String, Object?> state() => <String, Object?>{
    'ecs': system.entities.save(),
    'system': system.save(),
  };

  void restore(Map<Object?, Object?> state) {
    system.entities.restore((state['ecs']! as Map).cast<String, Object?>());
    system.restore(state['system']);
  }
}

double _flat(Vector3 a, Vector3 b) {
  final dx = a.x - b.x;
  final dz = a.z - b.z;
  return dx * dx + dz * dz;
}

/// The world the walks are made in: falling at 24 m/s², the gravity the
/// characters here were tuned under before they fell by their world's.
final WorldProperties _world = WorldProperties(
  gravity: Vector3(0.0, -24.0, 0.0),
);

void main() {
  group('a post in the next room', () {
    final from = Vector3(-4, 0.9, -2);
    final post = Vector3(4, 0.9, -2);

    test('is reached through the doorway over a mesh', () {
      final walk = _Walk(
        _rooms(),
        from: from,
        post: post,
        mesh: NavMesh.bake(_rooms(), config: _body),
      )..steps(360);
      expect(_flat(walk.position, post), lessThan(0.5 * 0.5));
    });

    test('is not reached walking straight at it', () {
      // Mutation: ignoring the mesh in `steerTowards` walks into the wall.
      final walk = _Walk(_rooms(), from: from, post: post)..steps(360);
      expect(walk.position.x, lessThan(0.0));
    });

    test('a run restored on the way steps on to the same bits', () {
      final mesh = NavMesh.bake(_rooms(), config: _body);
      final original = _Walk(_rooms(), from: from, post: post, mesh: mesh)
        ..steps(90);
      final saved = jsonDecode(jsonEncode(original.state())) as Map;
      final restored = _Walk(_rooms(), from: from, post: post, mesh: mesh)
        ..restore(saved);
      for (var i = 0; i < 200; i++) {
        original.step();
        restored.step();
        expect(
          restored.position.storage,
          original.position.storage,
          reason: 'step ${90 + i + 1}',
        );
      }
    });
  });

  group('meshes by width', () {
    test('one per erosion of the radii, each for the widest of its own', () {
      // At a quarter-metre lattice 0.35 erodes two cells and 0.38 and 0.62
      // erode three, so three bodies get two meshes. The 0.38 is listed
      // after the 0.62, so the widest is not simply the last met.
      final meshes = NavMesh.bakeLevelFor(
        Level(name: 'rooms', brushes: _rooms()),
        const <(double, double)>[(0.62, 2.4), (0.35, 1.7), (0.38, 1.8)],
        config: const NavMeshSettings(cellSize: 0.25),
      );
      expect(meshes.map((m) => m.config.agentRadius), <double>[0.35, 0.62]);
      // The 0.38 body is 1.8 tall and the 0.62 one 2.4: the mesh they share
      // keeps the room the taller needs. Mutation: keeping the first height
      // met for a class rather than the tallest.
      expect(meshes.map((m) => m.config.agentHeight), <double>[1.7, 2.4]);
    });

    test('a body walks on the narrowest mesh still as wide as it is', () {
      final system = ActorSystem(world: CollisionWorld(), random: GameRandom(1))
        ..navMeshes = NavMesh.bakeLevelFor(
          Level(name: 'rooms', brushes: _rooms()),
          const <(double, double)>[(0.62, 2.4), (0.35, 1.7)],
          config: const NavMeshSettings(cellSize: 0.25),
        ).reversed.toList();
      // Listed widest first. Mutation: taking the first mesh at least as
      // wide, not the narrowest, or one narrower than the body, gives the
      // wrong one here.
      expect(system.navMeshFor(0.3)!.config.agentRadius, 0.35);
      expect(system.navMeshFor(0.35)!.config.agentRadius, 0.35);
      expect(system.navMeshFor(0.4)!.config.agentRadius, 0.62);
      expect(system.navMeshFor(0.7), isNull);
    });
  });

  group('a post across a pit', () {
    final from = Vector3(-4, 0.9, 0);
    final post = Vector3(4, 0.9, 0);

    test('is jumped to over a mesh baked with the body\'s reach', () {
      const tuning = MovementSettings();
      final walk = _Walk(
        _pit(),
        from: from,
        post: post,
        mesh: NavMesh.bake(
          _pit(),
          config: _body,
          jumps: JumpReach.of(tuning, world: _world),
        ),
      )..steps(300);
      // Mutation: never asking for the jump walks the body off the edge.
      expect(walk.position.y, greaterThan(0.5));
      expect(_flat(walk.position, post), lessThan(0.5 * 0.5));
    });

    test('is not tried over a mesh baked without one', () {
      final walk = _Walk(
        _pit(),
        from: from,
        post: post,
        mesh: NavMesh.bake(_pit(), config: _body),
      )..steps(300);
      // The route ends at the near edge, and the body waits there.
      expect(walk.position.y, greaterThan(0.5));
      expect(walk.position.x, lessThan(-0.75));
      // Mutation: not stopping at an incomplete route's end paces the body
      // back and forth across it.
      final v = walk.walker.body!.velocity;
      expect(v.x * v.x + v.z * v.z, lessThan(1e-6));
    });
  });
}
