/// What the elements give a game so it keeps no numbers of its own: the heat
/// on a body read from the field, a burner fed what was spilt and no more,
/// and a body weighed from the catalogue.
///
///     dart test test/fire_and_bodies_test.dart
///
/// Each test names the mutation it was written against.
library;

import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A stone post with a fire fed on top of it, at the origin.
NativeBody _brazier(ElementsSimulation elements) {
  final post = elements.track(
    elements.addBody(
      Solid.box(
        Vector3(0.2, 0.5, 0.2),
        material: NativeMaterial.stone(),
        density: 2700.0,
      ),
      at: Vector3(0.0, 0.5, 0.0),
      type: NativeBodyType.fixed,
    ),
  );
  elements.fires.setBurner(post, NativeBurner.campfire());
  return post.native;
}

/// A person-sized column standing [far] metres from the brazier along x.
NativeBody _stander(ElementsSimulation elements, double far) =>
    elements.addBody(
      Solid.capsule(
        0.3,
        0.55,
        material: NativeMaterial.inert(),
        density: 985.0,
      ),
      at: Vector3(far, 0.9, 0.0),
      type: NativeBodyType.kinematic,
    );

void main() {
  group('the heat on a body, from the field', () {
    test('is the flames\' radiation on the side of it facing each', () {
      // What a game's character is burnt by: the crypt worked it out for
      // its player from every fire by hand. Mutation: measure from the
      // body's middle, not its surface — the flux falls by the square of a
      // distance 0.3 m longer.
      final elements = ElementsSimulation.open();
      addTearDown(elements.dispose);
      _brazier(elements);
      final stander = _stander(elements, 2.0);
      elements.step(1 / 60);

      final fields = NativeElementFields(elements.world);
      final flux = fields.radiantFluxOn(ElementBody.of(stander));
      final fire = elements.world.fires().single;
      final middle = FireExposure.middleOf(fire);
      final hit = elements.world.rayCast(
        middle,
        (elements.world.localPositionOf(stander) - middle).normalized(),
        10.0,
        ignore: fire.body,
      )!;
      expect(hit.body, stander);
      expect(flux, closeTo(FireExposure.fluxFrom(fire, hit.at * hit.at), 1e-6));
      expect(
        flux,
        greaterThan(FireExposure.fluxAt(<NativeFire>[fire], hit.point) - 1e-9),
      );
      // And by quantity, in watts a square metre.
      final q = fields.quantityOf(
        ElementBody.of(stander),
        FieldQuantity.radiantFlux,
      );
      expect(q.value, flux);
      expect(q.unit.dimension, FieldQuantity.radiantFlux.unit.dimension);
    });

    test('and nothing from a fire a wall stands between', () {
      // Mutation: drop the ray — the wall lets the whole flame through.
      final elements = ElementsSimulation.open();
      addTearDown(elements.dispose);
      _brazier(elements);
      final stander = _stander(elements, 3.0);
      elements.addBody(
        Solid.box(
          Vector3(0.1, 2.0, 2.0),
          material: NativeMaterial.stone(),
          density: 2700.0,
        ),
        at: Vector3(1.5, 2.0, 0.0),
        type: NativeBodyType.fixed,
      );
      elements.step(1 / 60);
      expect(elements.world.fires(), isNotEmpty);
      expect(
        NativeElementFields(
          elements.world,
        ).radiantFluxOn(ElementBody.of(stander)),
        0.0,
      );
    });

    test('and a backend that has no fires refuses it by name', () {
      expect(
        () => const _Silent().radiantFluxOn(const ElementBody(1)),
        throwsA(isA<UnsupportedCapabilityException>()),
      );
    });
  });

  group('a burner fed what was spilt', () {
    test('burns as long as its fuel lasts, then goes out and says so', () {
      // Racing's wrecks burnt until a timer had the marshals put them out.
      // Mutation: never take the fuel off — the burner burns for ever.
      final elements = ElementsSimulation.open();
      addTearDown(elements.dispose);
      final out = <NativeBody>[];
      elements.listener = ElementsListener(burnerOut: (e) => out.add(e.body));
      final heap = elements.track(
        elements.addBody(
          Solid.box(
            Vector3.all(0.3),
            material: NativeMaterial.stone(),
            density: 2700.0,
          ),
          at: Vector3(0.0, 0.3, 0.0),
          type: NativeBodyType.fixed,
        ),
      );
      final burner = NativeBurner.brazier();
      // Two seconds' worth.
      elements.fires.setBurner(heap, burner, fuel: burner.rate * 2.0);
      for (var i = 0; i < 60; i++) {
        elements.step(1 / 60);
      }
      expect(elements.world.isBurning(heap.native), isTrue);
      expect(elements.fires.fuelLeft(heap), closeTo(burner.rate, 1e-9));
      for (var i = 0; i < 90; i++) {
        elements.step(1 / 60);
      }
      expect(out, <NativeBody>[heap.native]);
      expect(elements.fires.fuelLeft(heap), isNull);
      expect(elements.world.heatReleaseOf(heap.native), 0.0);
    });

    test('and a save carries what is left of it', () {
      // Mutation: leave the fuel out of the save — the restored burner
      // burns for ever.
      final elements = ElementsSimulation.open();
      addTearDown(elements.dispose);
      final heap = elements.track(
        elements.addBody(
          Solid.box(
            Vector3.all(0.3),
            material: NativeMaterial.stone(),
            density: 2700.0,
          ),
          at: Vector3(0.0, 0.3, 0.0),
          type: NativeBodyType.fixed,
        ),
      );
      final burner = NativeBurner.brazier();
      elements.fires.setBurner(heap, burner, fuel: 1.0);
      elements.step(1 / 60);
      final saved = elements.saveElements();
      elements.fires.setBurner(heap, null);
      expect(elements.fires.fuelLeft(heap), isNull);
      elements.restoreElements(saved);
      expect(
        elements.fires.fuelLeft(heap),
        closeTo(1.0 - burner.rate / 60, 1e-9),
      );
    });
  });

  group('a body weighed from the catalogue', () {
    test('is as heavy as its material is dense', () {
      // Reef's finds were weighed by hand. Mutation: keep the stone preset's
      // density — the bronze weighs a third of what it does.
      final bell = Solid.of(
        const NativeShape.cylinder(0.18, 0.17),
        Materials.phosphorBronze,
      );
      final density = Materials.phosphorBronze.mechanical!.density!.value;
      expect(bell.density, density);
      expect(bell.mass, closeTo(density * bell.volume, 1e-9));
    });

    test('and a hollow one by its wall, displacing all of itself', () {
      // A bronze head is cast hollow: it sinks by its bronze and is lifted
      // by the water its whole outside displaces. Mutation: take the shell's
      // volume as what it displaces — it would weigh its own bronze in
      // water.
      const radius = 0.2, wall = 0.008;
      final head = Solid.of(
        const NativeShape.sphere(radius),
        Materials.phosphorBronze,
        wall: wall,
      );
      final rho = Materials.phosphorBronze.mechanical!.density!.value;
      const outside = 4 / 3 * 3.141592653589793 * radius * radius * radius;
      const inside =
          4 /
          3 *
          3.141592653589793 *
          (radius - wall) *
          (radius - wall) *
          (radius - wall);
      expect(head.volume, closeTo(outside, 1e-12));
      expect(head.mass, closeTo(rho * (outside - inside), 1e-9));
    });

    test('and at the temperature it is put in at, not the air\'s', () {
      // A volcano's bomb is torn from its melt: as hot as the melt is in the
      // catalogue. Mutation: drop the temperature in `addBody` — the bomb
      // starts as cold as the air.
      final elements = ElementsSimulation.open();
      addTearDown(elements.dispose);
      final melt = Materials.basaltMelt;
      final bomb = elements.addBody(
        Solid.of(const NativeShape.sphere(0.3), melt).at(melt.temperature),
        at: Vector3(0.0, 5.0, 0.0),
      );
      expect(
        elements.world.temperatureOf(bomb),
        closeTo(melt.temperature, 0.5),
      );
      expect(elements.world.materialOf(bomb).specificHeat, closeTo(1480, 1));
    });
  });
}

/// Fields that say nothing.
final class _Silent extends ElementFields {
  const _Silent();
}
