/// A probe per `reflection_probe` entity, and the culling that waits for it.
///
///     flutter test test/level_probes_test.dart
///
/// The loader's half is one node per entity, kept rather than rolling, with
/// the document's numbers where it gave any. The half worth a test of its
/// own is the order: a kept probe is drawn on the first frame it is seen,
/// and a visibility culler applied from the player's cell before that has
/// already hidden every room but the player's — so the probe in the vault
/// would capture the vault's walls with nothing behind them. `LoadedLevel.cull`
/// holds the culler until every probe stands, and does not hold it at all on a
/// device that builds none, or a level there would never cull again.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// One lit wall, and whatever [entities] the test puts beside it.
Level _level({List<Map<String, Object?>> entities = const []}) =>
    Level.fromJson(<String, Object?>{
      'version': 1,
      'materials': <String, Object?>{
        'wall': <String, Object?>{
          'color': <double>[0.8, 0.8, 0.8],
        },
      },
      'brushes': <Object?>[
        <String, Object?>{
          'material': 'wall',
          'at': <double>[0.0, 1.5, -1.5],
          'size': <double>[4.0, 3.0, 1.0],
        },
      ],
      'lights': <Object?>[
        <String, Object?>{
          'type': 'point',
          'at': <double>[0.0, 2.0, 0.0],
          'color': <double>[1.0, 1.0, 1.0],
          'range': 8.0,
        },
      ],
      'entities': entities,
    });

Brush _box(double x, double y, double z, double sx, double sy, double sz) =>
    Brush(centre: Vector3(x, y, z), size: Vector3(sx, sy, sz));

/// Rooms A (x 0..8), B (x 10..18) and C (x 20..28); a doorway between A and
/// B, a solid wall between B and C — the level the culler's own tests use.
Level _rooms() => Level(
  brushes: <Brush>[
    _box(14.0, -0.5, 4.0, 30.0, 1.0, 10.0),
    _box(14.0, 4.5, 4.0, 30.0, 1.0, 10.0),
    _box(14.0, 2.0, -0.5, 30.0, 4.0, 1.0),
    _box(14.0, 2.0, 8.5, 30.0, 4.0, 1.0),
    _box(-0.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    _box(28.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    _box(9.0, 2.0, 1.5, 2.0, 4.0, 3.0),
    _box(9.0, 2.0, 6.5, 2.0, 4.0, 3.0),
    _box(19.0, 2.0, 4.0, 2.0, 4.0, 8.0),
  ],
);

void main() {
  final device = CpuDevice(
    width: 16,
    height: 16,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final registry = EntityRegistry(<EntityKind>[const ReflectionProbeKind()]);

  test(
    'a reflection_probe entity is a kept probe where the document put it',
    () async {
      final loaded = await const LevelLoader().build(
        _level(
          entities: <Map<String, Object?>>[
            <String, Object?>{
              'type': 'reflection_probe',
              'name': 'hall',
              'at': <double>[3.0, 2.0, -1.0],
              'radius': 6.0,
              'intensity': 1.5,
              'faceSize': 32,
              'levels': 3,
              'near': 0.5,
              'far': 40.0,
            },
          ],
        ),
        device: device,
        registry: registry,
      );

      expect(loaded.issues.where((LevelIssue i) => i.isError), isEmpty);
      final probe = loaded.probes.single;
      expect(probe.name, 'hall');
      expect(probe.readWorldPosition(), Vector3(3.0, 2.0, -1.0));
      expect(probe.radius, 6.0);
      expect(probe.intensity, 1.5);
      expect(probe.faceSize, 32);
      expect(probe.levels, 3);
      expect(probe.near, 0.5);
      expect(probe.far, 40.0);
      expect(
        probe.refreshFaceEveryFrame,
        isFalse,
        reason: 'a room does not move, so its probe is kept',
      );
      expect(
        loaded.scene.probes,
        contains(probe),
        reason: 'in the scene, where the renderer finds it',
      );
    },
  );

  test('and one that says nothing gets the probe\'s own defaults', () async {
    final loaded = await const LevelLoader().build(
      _level(
        entities: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'reflection_probe',
            'at': <double>[0.0, 2.0, 0.0],
          },
        ],
      ),
      device: device,
      registry: registry,
    );

    final probe = loaded.probes.single;
    final own = ReflectionProbeNode();
    expect(probe.radius, own.radius);
    expect(probe.intensity, own.intensity);
    expect(probe.faceSize, own.faceSize);
    expect(probe.levels, own.levels);
    expect(probe.near, own.near);
    expect(probe.far, own.far);
  });

  test('a level that asks for none has none', () async {
    final loaded = await const LevelLoader().build(
      _level(),
      device: device,
      registry: registry,
    );
    expect(loaded.probes, isEmpty);
    expect(loaded.scene.probes, isEmpty);
  });

  test('a breach invalidates every probe: the wall it holds is gone', () async {
    // Mutation: forget the loop in `rebuildBrushes` — a rocket through a
    // wall leaves the wall standing in every reflection in the room.
    final loaded = await const LevelLoader().build(
      _level(
        entities: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'reflection_probe',
            'at': <double>[0.0, 2.0, 0.0],
          },
        ],
      ),
      device: device,
      registry: registry,
    );
    final probe = loaded.probes.single..markCaptured();
    expect(probe.isCaptured, isTrue);

    const LevelLoader().rebuildBrushes(
      loaded,
      device: device,
      brushes: loaded.level.brushes,
    );

    expect(probe.isCaptured, isFalse);
  });

  group('the culler', () {
    final table = LevelVisibility.bake(
      _rooms(),
      cellSize: 2.0,
      samplesPerAxis: 2,
    );
    // Room C's batch, which an eye in room A cannot see.
    VisibilityBatch roomC() => (
      node: MeshNode(
        CpuMesh(CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build()),
        Material(),
        name: 'c',
      ),
      bounds: Aabb3.minMax(Vector3(20.5, 0.0, 0.0), Vector3(27.5, 4.0, 8.0)),
    );
    final inRoomA = Vector3(2.0, 1.5, 4.0);

    LoadedLevel level({
      required ReflectionProbeNode probe,
      required VisibilityBatch batch,
    }) => LoadedLevel(
      level: _rooms(),
      scene: Scene()..add(probe),
      collision: CollisionWorld(),
      issues: const <LevelIssue>[],
      drawCallCount: 1,
      probes: <ReflectionProbeNode>[probe],
      culler: VisibilityCuller(table, <VisibilityBatch>[batch]),
    );

    test('waits until every probe stands, then hides what it always hid', () {
      // Mutation: apply the culler regardless — the first frame hides room
      // C, and a probe standing in it captures its walls with nothing beyond.
      final probe = ReflectionProbeNode();
      final c = roomC();
      final loaded = level(probe: probe, batch: c);

      loaded.cull(inRoomA, device: device);
      expect(c.node.visible, isTrue, reason: 'held for the probe');
      expect(loaded.culler!.hidden, 0);

      probe.markCaptured();
      loaded.cull(inRoomA, device: device);
      expect(c.node.visible, isFalse, reason: 'behind the wall, as before');
      expect(loaded.culler!.hidden, 1);
    });

    test('and shows a room it had hidden while a probe is stale again', () {
      final probe = ReflectionProbeNode()..markCaptured();
      final c = roomC();
      final loaded = level(probe: probe, batch: c);
      loaded.cull(inRoomA, device: device);
      expect(c.node.visible, isFalse);

      probe.invalidate();
      loaded.cull(inRoomA, device: device);
      expect(c.node.visible, isTrue, reason: 'the redraw wants every wall');
    });

    test('does not wait for a device that builds no probe', () {
      // flutter_gpu over OpenGL ES draws no probe and never marks one
      // captured. Mutation: wait anyway — every level with a table stops
      // culling on every phone that cannot render into a mip.
      final c = roomC();
      final loaded = level(probe: ReflectionProbeNode(), batch: c);

      loaded.cull(inRoomA, device: FakeBackend(supportsRenderToMip: false));
      expect(c.node.visible, isFalse);
    });
  });
}
