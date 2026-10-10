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
    // Two seconds after the fireball has gone, the heap burns by itself.
    //
    // Read as a fire — burning, and the heat it gives off — not as its
    // surface temperature: a bed of splinters takes heat a few centimetres
    // deep, and the surface it reports is the bed's, 358 K while the fire
    // on it gives off half a megawatt. Measured: 350 kW two seconds after
    // the hold, 0.56 MW from five seconds on, still burning at thirty.
    const afterHold = 2.0;
    _run(elements, BurningWrecks.fireball.seconds + afterHold);
    // Mutation: the one-second flash it was, or the heap a block of solid
    // wood, and it never catches or goes out as the fireball does.
    expect(elements.world.isBurning(heap.native), isTrue);
    // Mutation: add the heap and never hold the fireball to it, and it
    // gives off nothing.
    expect(elements.world.heatReleaseOf(heap.native), greaterThan(1e5));
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

  test('a rewind puts the wrecks back with the world', () async {
    final (elements, device) = await _open();
    addTearDown(elements.dispose);
    final wrecks = BurningWrecks(elements, device)
      ..timbers(Vector3(0.0, 0.5, -10.0));
    final heap = wrecks.bodies.single;
    final part = wrecks.snapshotPart();
    final world = elements.world.snapshot();
    final saved = part.capture();

    // After the snapshot: a slick lit, and the heap let go.
    wrecks
      ..oil(Vector3(2.0, 0.0, -30.0))
      ..step(55.0);
    final slick = wrecks.bodies.single;
    expect(elements.world.contains(heap.native), isFalse);

    elements.world.restore(world);
    part.restore(saved, part.version);

    // Mutation: restore nothing, and the list holds the slick the world no
    // longer has while the heap the world has again burns undrawn and
    // unheld.
    final back = wrecks.bodies.single;
    expect(back.native.raw, heap.native.raw);
    expect(elements.world.contains(back.native), isTrue);
    expect(elements.simulation.bodies, contains(back));
    expect(elements.simulation.bodies, isNot(contains(slick)));
    expect(elements.lookOf(slick), isNull);
  });

  test('a slick let go since comes back drawn', () async {
    final (elements, device) = await _open();
    addTearDown(elements.dispose);
    final wrecks = BurningWrecks(elements, device)
      ..oil(Vector3(0.0, 0.0, -10.0));
    final slick = wrecks.bodies.single;
    final part = wrecks.snapshotPart();
    final world = elements.world.snapshot();
    final saved = part.capture();
    wrecks.step(55.0);
    expect(wrecks.bodies, isEmpty);

    elements.world.restore(world);
    part.restore(saved, part.version);

    // Mutation: take a wreck back in without its look, and the slick burns
    // on the water with nothing drawn for it.
    final back = wrecks.bodies.single;
    expect(back.native.raw, slick.native.raw);
    final look = elements.lookOf(back)! as MeshNode;
    expect(look.material.baseColor.toSrgb().r, lessThan(0.05));
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
