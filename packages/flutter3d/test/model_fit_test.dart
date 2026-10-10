/// `ModelAsset.instantiateFitted`: a model in whatever unit its author used,
/// placed at the length a game asks for.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A box nine hundred units long, off to one side and above its origin: the
/// shape of a free model authored in centimetres by somebody who never
/// centred it.
ModelAsset _awkwardModel() {
  final mesh = CuboidShape(
    size: Vector3(300.0, 120.0, 900.0),
  ).build().transformed(Matrix4.translationValues(50.0, 200.0, -40.0));
  return ModelAsset.fromMesh(cpuTestDevice(width: 4, height: 4).device, mesh);
}

void main() {
  test('fitted to a length along z, centred on the parent', () {
    final scene = Scene();
    final holder = SceneNode(name: 'holder')..setPosition(10.0, 0.0, 5.0);
    scene.add(holder);
    _awkwardModel().instantiateFitted(scene, length: 3.0, parent: holder);

    final bounds = scene.computeBounds();
    expect(bounds.max.z - bounds.min.z, closeTo(3.0, 1e-4));
    // Proportions kept: 300 by 120 by 900 is 1 by 0.4 by 3.
    expect(bounds.max.x - bounds.min.x, closeTo(1.0, 1e-4));
    expect(bounds.max.y - bounds.min.y, closeTo(0.4, 1e-4));
    final center = (bounds.min + bounds.max)..scale(0.5);
    expect(center.x, closeTo(10.0, 1e-4));
    expect(center.y, closeTo(0.0, 1e-4));
    expect(center.z, closeTo(5.0, 1e-4));
  });

  test('on the ground, it stands on the parent instead', () {
    final scene = Scene();
    _awkwardModel().instantiateFitted(scene, length: 3.0, onGround: true);

    final bounds = scene.computeBounds();
    expect(bounds.min.y, closeTo(0.0, 1e-4));
    expect(bounds.max.y, closeTo(0.4, 1e-4));
    expect((bounds.min.x + bounds.max.x) / 2.0, closeTo(0.0, 1e-4));
  });

  test('another axis can be the length', () {
    final scene = Scene();
    _awkwardModel().instantiateFitted(scene, length: 1.2, axis: 1);

    final bounds = scene.computeBounds();
    expect(bounds.max.y - bounds.min.y, closeTo(1.2, 1e-4));
    expect(bounds.max.z - bounds.min.z, closeTo(9.0, 1e-3));
  });
}
