/// Brands a fire lofts: by the fuel it burns, as hot as its flame, up its
/// plume and off on the wind — no dice.
///
///     dart test test/firebrands_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1 / 60;

/// A tree's crown of dry thatch alight, in a breeze along x.
({ElementsSimulation elements, NativeBody crown}) _burningCrown() {
  final elements = ElementsSimulation.open();
  elements.world.wind = Vector3(4.0, 0.0, 0.0);
  final crown = elements.track(
    elements.addBody(
      Solid.cylinder(
        0.8,
        1.2,
        material: NativeMaterial.thatch(),
        density: 40.0,
      ),
      at: Vector3(0.0, 3.0, 0.0),
      type: NativeBodyType.fixed,
    ),
  );
  elements.fires.ignite(
    crown,
    by: Igniter.propaneTorch,
    at: Vector3(0.0, 2.0, 0.0),
  );
  return (elements: elements, crown: crown.native);
}

/// A brand: a pine twig's end, a centimetre across, as dense as the
/// catalogue's pine.
final Solid _brand = Solid.of(const NativeShape.sphere(0.01), Materials.pine);

void main() {
  test('a fire lofts its share of what it burns, brand by brand', () {
    // Mutation: a die per step (the strategy map's way) — the count no
    // longer follows the fuel burnt.
    final (:elements, :crown) = _burningCrown();
    addTearDown(elements.dispose);
    final brands = Firebrands(
      elements.world,
      brand: _brand,
      share: 0.2,
      most: 1000,
    );
    // The crown's brands, from what it burns; a brand burning on its way
    // down lofts none.
    var due = 0.0;
    final seen = <NativeBody>{};
    for (var i = 0; i < 1200; i++) {
      for (final fire in elements.world.fires()) {
        if (fire.body != crown) continue;
        final perKg = elements.world.materialOf(fire.body).heatOfCombustion;
        due += 0.2 * fire.power / perKg * _dt / _brand.mass;
      }
      brands.step(_dt);
      seen.addAll(brands.brands);
      elements.step(_dt);
    }
    expect(elements.world.fires(), isNotEmpty, reason: 'it must burn');
    expect(seen.length, due.floor());
    expect(seen.length, greaterThan(3));
  });

  test('a brand leaves as hot as the flame, up the plume and with the '
      'wind', () {
    // Mutation: lofted at the air's temperature — it lights nothing.
    final (:elements, crown: _) = _burningCrown();
    addTearDown(elements.dispose);
    final brands = Firebrands(elements.world, brand: _brand, share: 0.2);
    NativeBody? first;
    for (var i = 0; i < 1200 && first == null; i++) {
      brands.step(_dt);
      first = brands.brands.firstOrNull;
      if (first == null) elements.step(_dt);
    }
    expect(first, isNotNull);
    final world = elements.world;
    expect(
      world.temperatureOf(first!),
      closeTo(NativeMaterial.thatch().flameTemperature, 1.0),
      reason: 'as hot as the crown\'s flame',
    );
    final v = world.velocityOf(first);
    expect(v.y, greaterThan(1.0));
    expect(v.x, greaterThan(3.0), reason: 'the wind carries it');
  });

  test('no more than the game\'s budget is alight at once', () {
    // Mutation: loft past `most` — the second brand of a pair is lofted
    // while the first still burns.
    final (:elements, crown: _) = _burningCrown();
    addTearDown(elements.dispose);
    final brands = Firebrands(
      elements.world,
      brand: _brand,
      share: 0.5,
      most: 1,
    );
    for (var i = 0; i < 600; i++) {
      brands.step(_dt);
      expect(brands.brands.length, lessThanOrEqualTo(1));
      elements.step(_dt);
    }
    expect(brands.skipped, greaterThan(0));
  });

  test('a save puts back the brands and the fuel owed towards the next', () {
    // Mutation: leave `owed` out of the save — the restored fire lofts its
    // next brand later than the run did.
    final (:elements, crown: _) = _burningCrown();
    addTearDown(elements.dispose);
    final world = elements.world;
    final brands = Firebrands(world, brand: _brand, share: 0.2);
    void run(int steps) {
      for (var i = 0; i < steps; i++) {
        brands.step(_dt);
        elements.step(_dt);
      }
    }

    run(300);
    final snapshot = world.snapshot();
    final saved = jsonDecode(jsonEncode(brands.save()));
    final held = jsonEncode(elements.saveElements());
    String onward() {
      run(300);
      return '${brands.brands.map((b) => b.raw)}'
          '${base64Encode(world.snapshot())}';
    }

    final first = onward();
    world.restore(snapshot);
    elements.restoreElements(
      (jsonDecode(held) as Map<Object?, Object?>).cast<String, Object?>(),
    );
    brands.restore(saved);
    expect(onward(), first);
  });
}
