/// The objective beacon: what already glows, raised to a glow that can be
/// found in the dark.
///
///     flutter test test/objective_beacon_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game_ui/hud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

MeshNode _part(Vector3 emissive) => MeshNode(
  CpuMesh(CuboidShape().build()),
  RenderMaterial(emissive: emissive.toLinearColor()),
);

void main() {
  test('the glowing part is raised to the beacon, in its own hue', () {
    final inside = _part(Vector3(0.05, 0.025, 0.0));
    lightBeacon(<MeshNode>[inside]);
    final glow = inside.material.emissive;
    // Mutation: multiply by the beacon rather than normalise — 0.02.
    expect(glow.r, closeTo(beaconGlow, 1e-9));
    expect(glow.g, closeTo(beaconGlow / 2, 1e-9));
    expect(glow.b, 0.0);
  });

  test('a part that does not glow stays dark', () {
    final frame = _part(Vector3.zero());
    lightBeacon(<MeshNode>[frame]);
    // Mutation: raise every part — the frame becomes a rectangle of light,
    // or a division by nought.
    expect(frame.material.emissive, Vector3.zero());
  });

  test('running it twice leaves the same brightness', () {
    final inside = _part(Vector3(0.0, 0.0, 0.05));
    lightBeacon(<MeshNode>[inside, inside]);
    lightBeacon(<MeshNode>[inside], brightness: beaconGlow);
    // Mutation: scale by the brightness instead of to it — this grows with
    // each call.
    expect(inside.material.emissive.b, closeTo(beaconGlow, 1e-9));
  });

  test('a brightness of its own', () {
    final inside = _part(Vector3(0.1, 0.0, 0.0));
    lightBeacon(<MeshNode>[inside], brightness: 0.8);
    expect(inside.material.emissive.r, closeTo(0.8, 1e-9));
  });
}
