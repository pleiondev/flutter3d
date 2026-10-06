import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'support.dart';

void main() {
  test('a burning block is drawn alight, chars, and goes out wet', () {
    final world = NativeWorld();
    addTearDown(world.dispose);
    final device = softwareDevice();
    final block = world.addBody(
      position: Vector3(0.0, 0.05, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.6,
    );
    world
      ..setShape(block, NativeShape.box(Vector3(0.05, 0.05, 0.05)))
      ..setMaterial(block, NativeMaterial.wood())
      ..setTemperature(block, 650.0);
    final look = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(0.1, 0.1, 0.1)).build(),
      ),
      Material(name: 'wood', baseColor: Vector4(0.42, 0.28, 0.16, 1.0)),
    );
    final view = FireView(
      world: world,
      device: device,
      scene: Scene(),
      renderer: Renderer.create(device: device),
      detail: FireDetail.light,
      baseWidth: 0.1,
    )..watch(block, look);
    for (var i = 0; i < 600; i++) {
      world.step(0.1);
      view.update(0.1);
    }
    expect(view.burning, 1);
    expect(view.watts, greaterThan(0.0));
    expect(view.tongues, greaterThan(0));
    expect(view.puffs, greaterThan(0));
    expect(view.light.intensity, greaterThan(0.0));
    // A minute in, a twelfth of its fuel gone, it is a third of the way to
    // black, and glows.
    expect(look.material.baseColor.x, inInclusiveRange(0.25, 0.35));
    expect(look.material.emissive.x, greaterThan(0.0));
    world.addWater(block, 0.5);
    for (var i = 0; i < 100; i++) {
      world.step(0.1);
      view.update(0.1);
    }
    // Out: nothing more sent up, and what was sent has gone.
    expect(view.burning, 0);
    expect(view.light.intensity, 0.0);
    expect(view.tongues, 0);
    expect(look.material.emissive.x, 0.0);
  });
}
