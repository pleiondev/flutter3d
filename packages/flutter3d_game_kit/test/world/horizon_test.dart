/// The world past the simulated square, out to the horizon.
///
///     dart test test/horizon_test.dart
///
/// The far floor starts at the height the game's ground gives its edge, so
/// the two meet without a seam, and sinks to the far depth; the far surface
/// is level and carries the depth under it; the rings reach kilometres out;
/// and both meshes are added to the scene by name.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_game_kit/world.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

/// A square of 16 m, ground sloping up towards +x from two metres down.
Horizon _horizon({double farDepth = Horizon.defaultFarDepth}) => Horizon(
  size: 16.0,
  floorCell: 1.0,
  surfaceCell: 2.0,
  ground: (x, z) => -2.0 + 0.1 * x,
  farDepth: farDepth,
);

/// Vertex [i]'s position in [mesh].
(double, double, double) _at(MeshData mesh, int i) => (
  mesh.vertices[i * 16],
  mesh.vertices[i * 16 + 1],
  mesh.vertices[i * 16 + 2],
);

void main() {
  test('the far floor meets the ground at the edge and sinks to the depth', () {
    final horizon = _horizon();
    final floor = horizon.floorMesh();
    // The first ring stands on the edge, at the cells' middles.
    final edge = floor.vertices.length ~/ 16 ~/ 13;
    for (var i = 0; i < edge; i++) {
      final (x, y, z) = _at(floor, i);
      // Mutation: start the far floor at nought rather than the ground's
      // height, and a cliff stands at the edge of the drawn world.
      expect(y, closeTo(-2.0 + 0.1 * x, 1e-4), reason: '($x, $z)');
    }
    final last = floor.vertices.length ~/ 16 - 1;
    final (fx, fy, fz) = _at(floor, last);
    // Mutation: drop the easing towards the far depth.
    expect(fy, closeTo(-Horizon.defaultFarDepth, 3.0));
    // A kilometre and a half out.
    expect(fx * fx + fz * fz, greaterThan(1400.0 * 1400.0));
  });

  test('the far surface is level, and carries the depth under it', () {
    final surface = _horizon(farDepth: 20.0).surfaceMesh();
    final count = surface.vertices.length ~/ 16;
    for (var i = 0; i < count; i++) {
      expect(surface.vertices[i * 16 + 1], 0.0);
    }
    // Mutation: write the depth at its sign, and the deep reads as dry land.
    expect(surface.vertices[(count - 1) * 16 + 6], closeTo(20.0, 3.0));
    // Never shallower than half a metre, so the edge is never dry.
    for (var i = 0; i < count; i++) {
      expect(surface.vertices[i * 16 + 6], greaterThanOrEqualTo(0.5));
    }
  });

  test('every normal faces up', () {
    final floor = _horizon().floorMesh();
    for (var i = 0; i < floor.vertices.length ~/ 16; i++) {
      // Mutation: keep the cross product's sign as it falls, and half the
      // far floor is lit from beneath.
      expect(floor.vertices[i * 16 + 4], greaterThan(0.0));
    }
  });

  test('both are added to the scene by name', () {
    final scene = Scene();
    _horizon().addTo(
      FakeBackend(),
      scene,
      floor: RenderMaterial(name: 'far sand'),
      surface: RenderMaterial(name: 'sea'),
    );
    final names = <String?>[for (final n in scene.root.childrenView) n.name];
    expect(names, containsAll(<String>['far floor', 'far sea']));
  });
}
