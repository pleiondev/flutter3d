import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'support.dart';

Future<Elements> _open(Scene scene) {
  final device = elementsDevice();
  return Elements.open(
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    load: (_) async => waterBundle(),
    quality: ElementsQuality.of(phone: true),
  );
}

void main() {
  test(
    'a crate floats in a pond it was put over, and its look goes with it',
    () async {
      final scene = Scene();
      final elements = await _open(scene);
      addTearDown(elements.dispose);
      final pond = elements.addWater(
        ground: ElementHeightfield.flat(
          origin: Vector3(-2.0, 0.0, -2.0),
          cell: 0.25,
          nx: 16,
          nz: 16,
        ),
        liquid: Liquid.water(),
        bed: const Bed(roughness: Bed.concrete),
      );
      expect(pond.fillBasin(from: Vector3.zero(), level: 0.5), 256);
      final look = MeshNode(
        DeviceMesh.upload(
          softwareDevice(),
          CuboidShape(size: Vector3.all(0.3)).build(),
        ),
        RenderMaterial(name: 'pine'),
      );
      final crate = elements.addBody(
        Solid.box(
          Vector3.all(0.15),
          material: NativeMaterial.wood(),
          density: 500.0,
        ),
        at: Vector3(0.0, 0.6, 0.0),
        look: look,
      );
      for (var i = 0; i < 300; i++) {
        elements.update(1 / 60, eye: Vector3(0.0, 3.0, 3.0));
      }
      // Half as dense as water, it floats half under.
      final under = elements.world.submergedOf(crate.native);
      expect(under.water, pond.native.id);
      expect(under.volume, closeTo(0.5 * 0.027, 0.004));
      expect(
        look.readPosition().y,
        closeTo(elements.world.positionOf(crate.native).y, 1e-9),
      );
    },
  );

  test('a flame held to a crate lights it in its time', () async {
    final elements = await _open(Scene());
    addTearDown(elements.dispose);
    final crate = elements.addBody(
      Solid.box(
        Vector3.all(0.05),
        material: NativeMaterial.wood(),
        density: 500.0,
      ),
      at: Vector3(0.0, 0.05, 0.0),
      type: NativeBodyType.fixed,
    );
    elements.fires.ignite(
      crate,
      by: const Igniter(
        flux: 5e4,
        area: 1e-3,
        temperature: 1300.0,
        seconds: 90.0,
      ),
    );
    var caught = -1.0;
    for (var i = 0; i < 3000 && caught < 0; i++) {
      elements.update(1 / 30, eye: Vector3(0.0, 1.0, 1.0));
      if (elements.events.any((e) => e.kind == NativeEventKind.ignited)) {
        caught = i / 30;
      }
    }
    // Not at once: a thick solid takes tens of seconds under fifty
    // kilowatts a square metre to hold a flame, as in a cone calorimeter.
    expect(caught, greaterThan(5.0));
    expect(elements.world.isBurning(crate.native), isTrue);
  });

  test(
    'a match will not light an oak block; a lighter, a torch and a pilot do',
    () async {
      // Under a match's 19 kW/m² dry oak, kρc 0.36 (kW/m² K)² s, reaches
      // 588 K after (π/4)·kρc·(ΔT/q'')² ≈ 140 s, long past the match's 20;
      // a lighter's 63 kW/m² brings it there in about 8 s, a torch's 106 in
      // about 3 (`flutter3d_elements/doc/igniters.md`). A pilot, as weak as
      // a match but left on for its five minutes, gets there in the end.
      // Mutations: the match given the lighter's flux — the block catches;
      // the pilot given half the match's — it never does.
      Future<bool> lit(Igniter by) async {
        final elements = await _open(Scene());
        addTearDown(elements.dispose);
        final block = elements.addBody(
          Solid.box(
            Vector3.all(0.05),
            material: NativeMaterial.oak(),
            density: 660.0,
          ),
          at: Vector3(0.0, 0.05, 0.0),
          type: NativeBodyType.fixed,
        );
        elements.fires.ignite(block, by: by, at: Vector3(0.0, 0.0, 0.0));
        var caught = false;
        for (var i = 0; i < (by.seconds + 10.0) * 30 && !caught; i++) {
          elements.update(1 / 30, eye: Vector3(0.0, 1.0, 1.0));
          caught = elements.events.any(
            (e) => e.kind == NativeEventKind.ignited,
          );
        }
        return caught;
      }

      expect(await lit(Igniter.match), isFalse);
      expect(await lit(Igniter.lighter), isTrue);
      expect(await lit(Igniter.propaneTorch.copyWith(seconds: 30.0)), isTrue);
      expect(await lit(Igniter.pilot), isTrue);
    },
  );

  test('a follower pushes water and is never moved back', () async {
    final elements = await _open(Scene());
    addTearDown(elements.dispose);
    final ford = elements.addWater(
      ground: ElementHeightfield.flat(
        origin: Vector3(-3.0, 0.0, -1.0),
        cell: 0.2,
        nx: 30,
        nz: 10,
      ),
      liquid: Liquid.water(),
      bed: const Bed(roughness: Bed.naturalStream),
    )..fillBasin(from: Vector3.zero(), level: 0.3);
    var x = -2.0;
    final wheel = elements.follow(
      () =>
          (position: Vector3(x, 0.3, 0.0), orientation: Quaternion.identity()),
      shape: const NativeShape.cylinder(0.3, 0.1),
    );
    // A metre a second, slower than a wave runs in water 0.3 m deep,
    // √(g h) = 1.7 m/s: what it pushes runs on ahead of it.
    for (var i = 0; i < 120; i++) {
      x += 1.0 / 60;
      elements.update(1 / 60, eye: Vector3(0.0, 2.0, 2.0));
    }
    expect(elements.world.positionOf(wheel.native).x, closeTo(x, 0.05));
    double mean(
      double from,
      double to,
      double Function(NativeShallowSample) of,
    ) {
      final at = <double>[for (var d = from; d <= to + 1e-9; d += 0.2) d];
      return at
              .map((d) => of(ford.sample(Vector3(x + d, 0.0, 0.0))!))
              .reduce((a, b) => a + b) /
          at.length;
    }

    // The water it pushed has run on ahead of it, raised over the still
    // level; behind, the water follows it.
    expect(mean(0.6, 1.4, (s) => s.surface), greaterThan(0.303));
    expect(mean(-0.8, -0.2, (s) => s.flowX), greaterThan(0.05));
  });
}
