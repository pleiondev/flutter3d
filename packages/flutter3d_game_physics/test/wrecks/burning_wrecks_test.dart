/// Wrecks that burn and sink.
///
///     dart test test/wrecks/burning_wrecks_test.dart
///
/// In the physics core's elements, with no device: timbers lit by the
/// fireball heat up and burn; the oil floats as a slick, published where it
/// lies and drawn from that black and glossy; a
/// wreck far enough behind the player is let go, along whichever way the
/// game travels; a rewind puts the list back with the world; and clearing
/// puts every fire out.
library;

import 'dart:convert';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_game_physics/wrecks.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ElementsSimulation _open() {
  final elements = ElementsSimulation.open();
  addTearDown(elements.dispose);
  return elements;
}

void _run(ElementsSimulation elements, double seconds) {
  for (var i = 0; i < seconds * 30; i++) {
    elements.step(1 / 30);
  }
}

void main() {
  test('timbers lit by the fireball heat up and burn', () {
    final elements = _open();
    final wrecks = BurningWrecks(elements)..timbers(Vector3(0.0, 0.5, 0.0));
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
    // And it is published burning.
    expect(wrecks.published.single.burning, isTrue);
    expect(wrecks.published.single.oil, isFalse);
  });

  test('the oil is a slick, published where it lies and drawn from that '
      'black and glossy', () {
    final elements = _open();
    final wrecks = BurningWrecks(elements)..oil(Vector3(3.0, 7.0, -2.0));
    final slick = wrecks.bodies.single;
    // Laid on the water, wherever the blast was.
    expect(elements.world.positionOf(slick.native).y, closeTo(0.05, 1e-3));

    // The view draws from the rows alone: through their JSON, as another
    // isolate would have them.
    final rows = <BurningWreck>[
      for (final row in wrecks.published)
        BurningWreck.fromJson(jsonDecode(jsonEncode(row.toJson())))!,
    ];
    final scene = Scene();
    final looks = WreckLooks(scene, FakeBackend())..show(rows);
    addTearDown(looks.dispose);
    final look = looks.slickOf(slick.native.raw)!;
    // Mutation: the hull's grey in place of the crude.
    expect(look.material.baseColor.toSrgb().r, lessThan(0.05));
    expect(look.material.roughness, lessThan(0.1));
    // Placed where the step left it. Mutation: leave the slick where it was
    // made — it does not follow the row.
    expect(look.readPosition().x, closeTo(3.0, 1e-3));
    expect(scene.meshes, hasLength(1));

    // A wreck no longer published is no longer drawn.
    looks.show(const <BurningWreck>[]);
    expect(scene.meshes, isEmpty);
  });

  test('a wreck far enough behind is let go', () {
    final elements = _open();
    final wrecks = BurningWrecks(elements)
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

  test('the way the game travels is its own', () {
    final elements = _open();
    final wrecks =
        BurningWrecks(elements, along: Vector3(1.0, 0.0, 0.0), behind: 5.0)
          ..timbers(Vector3(2.0, 0.5, 0.0))
          ..timbers(Vector3(20.0, 0.5, 0.0));
    // Mutation: read the distance off −z whatever [along] says, and both
    // heaps, at z = 0, go at once.
    wrecks.step(10.0);
    expect(wrecks.bodies, hasLength(1));
  });

  test('a rewind puts the wrecks back with the world', () {
    final elements = _open();
    final wrecks = BurningWrecks(elements)..timbers(Vector3(0.0, 0.5, -10.0));
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
    // longer has while the heap the world has again burns unheld.
    final back = wrecks.bodies.single;
    expect(back.native.raw, heap.native.raw);
    expect(elements.world.contains(back.native), isTrue);
    expect(elements.bodies, contains(back));
    expect(elements.bodies, isNot(contains(slick)));
  });

  test('a slick let go since comes back published as oil', () {
    final elements = _open();
    final wrecks = BurningWrecks(elements)..oil(Vector3(0.0, 0.0, -10.0));
    final slick = wrecks.bodies.single;
    final part = wrecks.snapshotPart();
    final world = elements.world.snapshot();
    final saved = part.capture();
    wrecks.step(55.0);
    expect(wrecks.bodies, isEmpty);

    elements.world.restore(world);
    part.restore(saved, part.version);

    // Mutation: take a wreck back in as timbers, and the slick burns on the
    // water with nothing drawn for it.
    final back = wrecks.published.single;
    expect(back.body, slick.native.raw);
    expect(back.oil, isTrue);
  });

  test('clearing puts every fire out', () {
    final elements = _open();
    final wrecks = BurningWrecks(elements)
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
