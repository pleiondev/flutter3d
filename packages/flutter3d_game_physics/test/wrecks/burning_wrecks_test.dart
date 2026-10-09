/// Wrecks that burn and sink.
///
///     dart test test/burning_wrecks_test.dart
///
/// In the physics core's elements on the software device: timbers lit by
/// the fireball heat up and burn; the oil floats as a slick drawn black and
/// glossy; a wreck far enough behind the player is let go, along whichever
/// way the game travels; and clearing puts every fire out.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_game_physics/wrecks.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A software device that takes the water's bundle, with an unlit stage in
/// the water material's place: these tests are of what burns, not of how.
GraphicsDevice _device() => CpuDevice(
  width: 32,
  height: 32,
  shaders: CpuShaderLibrary(<String, CpuStage>{
    ...builtinCpuShaders(),
    'Liquid': cpuUnlitStage,
  }),
);

Future<(Elements, GraphicsDevice)> _open() async {
  final device = _device();
  final elements = await Elements.open(
    device: device,
    renderer: Renderer.create(device: device),
    scene: Scene(),
    load: (_) async => ByteData.sublistView(
      File('../flutter3d_effects/assets/liquid.f3dshaders').readAsBytesSync(),
    ),
    quality: ElementsQuality.of(phone: true),
  );
  return (elements, device);
}

void _run(Elements elements, double seconds) {
  for (var i = 0; i < seconds * 30; i++) {
    elements.update(1 / 30, eye: Vector3(0.0, 2.0, 4.0));
  }
}

void main() {
  test('timbers lit by the fireball heat up and burn', () async {
    final (elements, device) = await _open();
    addTearDown(elements.dispose);
    final wrecks = BurningWrecks(elements, device)
      ..timbers(Vector3(0.0, 0.5, 0.0));
    final heap = wrecks.bodies.single;
    final cold = elements.world.surfaceTemperatureOf(heap.native);
    _run(elements, 2.0);
    // Mutation: add the heap and never hold the fireball to it, and the
    // wood sits at the air's temperature.
    expect(
      elements.world.surfaceTemperatureOf(heap.native),
      greaterThan(cold + 100.0),
    );
  });

  test('the oil is a slick drawn black and glossy', () async {
    final (elements, device) = await _open();
    addTearDown(elements.dispose);
    final wrecks = BurningWrecks(elements, device)
      ..oil(Vector3(3.0, 7.0, -2.0));
    final slick = wrecks.bodies.single;
    // Laid on the water, wherever the blast was.
    expect(elements.world.positionOf(slick.native).y, closeTo(0.05, 1e-3));
    final look = elements.lookOf(slick)! as MeshNode;
    // Mutation: the hull's grey in place of the crude.
    expect(look.material.baseColor.toSrgb().r, lessThan(0.05));
    expect(look.material.roughness, lessThan(0.1));
  });

  test('a wreck far enough behind is let go', () async {
    final (elements, device) = await _open();
    addTearDown(elements.dispose);
    final wrecks = BurningWrecks(elements, device)
      ..timbers(Vector3(0.0, 0.5, -10.0))
      ..timbers(Vector3(0.0, 0.5, -60.0));
    wrecks.step(45.0);
    // Mutation: compare against the distance itself rather than the
    // distance less `behind`, and the near heap goes the moment it is
    // passed.
    expect(wrecks.bodies, hasLength(2));
    wrecks.step(55.0);
    expect(wrecks.bodies, hasLength(1));
    expect(
      elements.world.positionOf(wrecks.bodies.single.native).z,
      closeTo(-60.0, 1e-3),
    );
  });

  test('the way the game travels is its own', () async {
    final (elements, device) = await _open();
    addTearDown(elements.dispose);
    final wrecks =
        BurningWrecks(
            elements,
            device,
            along: Vector3(1.0, 0.0, 0.0),
            behind: 5.0,
          )
          ..timbers(Vector3(2.0, 0.5, 0.0))
          ..timbers(Vector3(20.0, 0.5, 0.0));
    // Mutation: read the distance off −z whatever [along] says, and both
    // heaps, at z = 0, go at once.
    wrecks.step(10.0);
    expect(wrecks.bodies, hasLength(1));
  });

  test('clearing puts every fire out', () async {
    final (elements, device) = await _open();
    addTearDown(elements.dispose);
    final wrecks = BurningWrecks(elements, device)
      ..timbers(Vector3.zero())
      ..oil(Vector3(2.0, 0.0, 0.0));
    final lit = wrecks.bodies;
    wrecks.clear();
    // Mutation: forget the list without taking the bodies out of the
    // elements, and the old run's fires burn under the new one.
    expect(wrecks.bodies, isEmpty);
    for (final body in lit) {
      expect(elements.world.contains(body.native), isFalse);
    }
  });
}
