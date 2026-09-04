/// Hiding the batches a camera cannot see.
///
///     flutter test test/visibility_culler_test.dart
///
/// The runtime half of the visibility table, on the three-room level the
/// table's own tests use: an eye in room A leaves room C's batch off and
/// room B's on, an eye in no cell leaves everything on, and `showAll` puts
/// a level back the way a camera that is not the player's wants it.
library;

import 'dart:convert';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Brush _box(double x, double y, double z, double sx, double sy, double sz) =>
    Brush(centre: Vector3(x, y, z), size: Vector3(sx, sy, sz));

/// Rooms A (x 0..8), B (x 10..18) and C (x 20..28); a doorway between A and
/// B, a solid wall between B and C.
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

MeshNode _node(String name) => MeshNode(
  CpuMesh(CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build()),
  Material(),
  name: name,
);

void main() {
  final table = LevelVisibility.bake(
    _rooms(),
    cellSize: 2.0,
    samplesPerAxis: 2,
  );
  VisibilityBatch room(String name, double fromX, double toX) => (
    node: _node(name),
    bounds: Aabb3.minMax(Vector3(fromX, 0.0, 0.0), Vector3(toX, 4.0, 8.0)),
  );

  test('an eye in A leaves C off and B on', () {
    final a = room('a', 0.5, 7.5);
    final b = room('b', 10.5, 17.5);
    final c = room('c', 20.5, 27.5);
    final culler = VisibilityCuller(table, <VisibilityBatch>[a, b, c]);

    final hidden = culler.apply(Vector3(2.0, 1.5, 4.0));

    expect(hidden, 1);
    expect(a.node.visible, isTrue);
    expect(b.node.visible, isTrue, reason: 'through the doorway');
    expect(c.node.visible, isFalse, reason: 'behind the wall');
    expect(culler.cell, greaterThanOrEqualTo(0));
  });

  test('an eye in no cell sees everything', () {
    final c = room('c', 20.5, 27.5);
    final culler = VisibilityCuller(table, <VisibilityBatch>[c])
      ..apply(Vector3(2.0, 1.5, 4.0));
    expect(c.node.visible, isFalse);

    final hidden = culler.apply(Vector3(19.0, 2.0, 4.0));

    expect(hidden, 0, reason: 'inside the wall, the table has no opinion');
    expect(c.node.visible, isTrue);
    expect(culler.cell, -1);
  });

  group('the loader', () {
    final device = CpuDevice(
      width: 16,
      height: 16,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final registry = EntityRegistry(<EntityKind>[]);

    test(
      'batches by cell and hands out a culler when the table matches',
      () async {
        final plain = await const LevelLoader().build(
          _rooms(),
          device: device,
          registry: registry,
        );
        final celled = await const LevelLoader().build(
          _rooms(),
          device: device,
          registry: registry,
          visibility: table,
        );

        expect(plain.culler, isNull);
        expect(celled.culler, isNotNull);
        expect(celled.drawCallCount, greaterThan(plain.drawCallCount));
        expect(
          celled.issues.map((i) => i.message),
          isNot(anyElement(contains('bake_visibility'))),
          reason: 'a fresh table is taken without a word',
        );

        // And it works on the level it just built: from A, some batch is off.
        final hidden = celled.culler!.apply(Vector3(2.0, 1.5, 4.0));
        expect(hidden, greaterThan(0));
        plain.dispose(device);
        celled.dispose(device);
      },
    );

    test('a sidecar that will not read is a warning, not a crash', () async {
      // The level plays either way; the person who wrote a table that does
      // not parse is the one who wants to hear about it.
      final loaded = await const LevelLoader().load(
        'levels/rooms.json',
        device: device,
        registry: registry,
        readDocument: (AssetRequest r) async =>
            r.uri.endsWith('.visibility.json')
            ? '{"version": 1, "cellSize": 2.0}'
            : jsonEncode(_rooms().toJson()),
      );

      expect(loaded.culler, isNull);
      expect(
        loaded.issues.map((i) => i.message),
        anyElement(contains('could not be read')),
      );
      loaded.dispose(device);
    });

    test('refuses a table baked from other brushes, with a word', () async {
      final moved = _rooms()..brushes.add(_box(4.0, 2.0, 4.0, 1.0, 4.0, 1.0));
      final loaded = await const LevelLoader().build(
        moved,
        device: device,
        registry: registry,
        visibility: table,
      );

      expect(loaded.culler, isNull, reason: 'a stale table hides real rooms');
      expect(
        loaded.issues.map((i) => i.message),
        anyElement(contains('bake_visibility')),
      );
      loaded.dispose(device);
    });
  });

  test('showAll puts every batch back', () {
    final c = room('c', 20.5, 27.5);
    final culler = VisibilityCuller(table, <VisibilityBatch>[c])
      ..apply(Vector3(2.0, 1.5, 4.0));
    expect(c.node.visible, isFalse);

    culler.showAll();

    expect(c.node.visible, isTrue);
    expect(culler.hidden, 0);
  });
}
