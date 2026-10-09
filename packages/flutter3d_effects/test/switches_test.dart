import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'support.dart';

Future<Elements> _open() {
  final device = elementsDevice();
  return Elements.open(
    device: device,
    renderer: Renderer.create(device: device),
    scene: Scene(),
    load: (_) async => waterBundle(),
    quality: ElementsQuality.of(phone: true),
  );
}

/// A crate burning in still air, the elements stepped [seconds] on.
Future<(Elements, TrackedBody)> _burning({double seconds = 3.0}) async {
  final elements = await _open();
  final crate = elements.addBody(
    Solid.box(
      Vector3.all(0.1),
      material: NativeMaterial.wood(),
      density: 500.0,
    ),
    at: Vector3(0.0, 0.1, 0.0),
    type: NativeBodyType.fixed,
  );
  elements.world.setTemperature(crate.native, 690.0);
  for (var i = 0; i < seconds * 30; i++) {
    elements.update(1 / 30, eye: Vector3(0.0, 1.0, 3.0));
  }
  return (elements, crate);
}

void main() {
  test('every combination of the fires\' steps draws what is left', () async {
    final (elements, _) = await _burning();
    addTearDown(elements.dispose);
    final view = elements.fireView;
    for (var mask = 0; mask < 32; mask++) {
      final steps = FireSteps(
        flames: mask & 1 != 0,
        smoke: mask & 2 != 0,
        embers: mask & 4 != 0,
        firelight: mask & 8 != 0,
        charring: mask & 16 != 0,
      );
      elements.switches = ElementsSteps(fire: steps);
      for (var i = 0; i < 30; i++) {
        elements.update(1 / 30, eye: Vector3(0.0, 1.0, 3.0));
      }
      // Mutation: leave a switched-off system's particles alive in
      // `FireView.update` — the first combination with flames off still
      // shows tongues.
      expect(view.tongues > 0, steps.flames, reason: 'flames, mask $mask');
      expect(view.puffs > 0, steps.smoke, reason: 'smoke, mask $mask');
      expect(view.embers > 0, steps.embers, reason: 'embers, mask $mask');
      expect(
        view.firelight.any((l) => l.intensity > 0.0),
        steps.firelight,
        reason: 'firelight, mask $mask',
      );
    }
    // The world burns the same whatever is drawn.
    expect(elements.world.fires(), isNotEmpty);
  });

  test('the listener is told what the core said, in its order', () async {
    final caught = <NativeBody>[];
    final exploded = <int>[];
    final elements = await _open();
    addTearDown(elements.dispose);
    elements.listener = ElementsListener(
      caught: (body, made) => caught.add(body),
      exploded: (at, pushed) => exploded.add(pushed),
    );
    final crate = elements.addBody(
      Solid.box(
        Vector3.all(0.1),
        material: NativeMaterial.wood(),
        density: 500.0,
      ),
      at: Vector3(0.0, 0.1, 0.0),
      type: NativeBodyType.fixed,
    );
    elements.world.setTemperature(crate.native, 690.0);
    elements.update(1 / 30, eye: Vector3.zero());
    // Mutation: drop `_tell` from `Elements.update` — nobody hears it catch.
    expect(caught, <NativeBody>[crate.native]);
    elements.fires.explode(
      Vector3(0.0, 0.0, 0.5),
      const NativeExplosion.tnt(0.01),
    );
    expect(exploded, hasLength(1));
  });

  test(
    'the heat on a point is each fire\'s point source, capped by its soot',
    () async {
      final (elements, _) = await _burning();
      addTearDown(elements.dispose);
      final f = elements.world.fires().single;
      final middle = f.at + f.axis * (0.5 * f.reach);
      final at = middle + Vector3(3.0, 0.0, 0.0);
      // Mutation: spread it over a hemisphere, 2π — twice the flux.
      expect(
        elements.heatFluxAt(at),
        closeTo(f.radiantShare * f.power / (4.0 * math.pi * 9.0), 1e-6),
      );
      // In the flame, no more than the soot's σT⁴.
      final t = f.sootTemperature;
      expect(
        elements.heatFluxAt(middle),
        lessThanOrEqualTo(stefanBoltzmann * t * t * t * t + 1e-6),
      );
    },
  );

  test('ISO 13571\'s burn dose: none to 2.5 kW/m², then 6.9·q^−1.56 min', () {
    expect(Elements.burnDoseRate(2500.0), 0.0);
    // Mutation: the pain law, 4·q^−1.35, in its place.
    expect(
      Elements.burnDoseRate(10000.0),
      closeTo(1.0 / (6.9 * 60.0 * math.pow(10.0, -1.56)), 1e-12),
    );
  });

  test('smoke hides what is behind its plume, and nothing beside it', () async {
    final (elements, _) = await _burning(seconds: 5.0);
    addTearDown(elements.dispose);
    final f = elements.world.fires().single;
    final high = f.at.y + math.max(f.reach, f.base) + 0.5;
    final through = elements.seenThroughSmoke(
      Vector3(-5.0, high, 0.0),
      Vector3(5.0, high, 0.0),
    );
    final beside = elements.seenThroughSmoke(
      Vector3(-5.0, high, 3.0),
      Vector3(5.0, high, 3.0),
    );
    // Mutation: take the chord as the plume's radius, not its width — the
    // line through the axis is dimmed half as much.
    final kw = f.power / 1000.0;
    final base = math.max(f.base, 0.01);
    expect(
      through,
      closeTo(
        math.exp(
          -FireView.plumeDepth(kw, base, high - f.at.y, sootYield: f.sootYield),
        ),
        1e-6,
      ),
    );
    expect(beside, 1.0);
  });

  test('every combination of the waters\' steps draws what is left', () async {
    final elements = await _open();
    addTearDown(elements.dispose);
    final pond = elements.addWater(
      ground: ElementHeightfield.flat(
        origin: Vector3(-1.0, 0.0, -1.0),
        cell: 0.25,
        nx: 8,
        nz: 8,
      ),
      liquid: Liquid.water(),
      bed: const Bed(roughness: Bed.concrete),
    )..fillBasin(from: Vector3.zero(), level: 0.3);
    final view = elements.viewOf(pond);
    for (var mask = 0; mask < 32; mask++) {
      final steps = LiquidSteps(
        surface: mask & 1 != 0,
        sheet: mask & 2 != 0,
        drops: mask & 4 != 0,
        mist: mask & 8 != 0,
        bubbles: mask & 16 != 0,
      );
      elements.switches = ElementsSteps(liquid: steps);
      // The water is stirred so it does not rest and skip its drawing.
      pond.pour(Vector3.zero(), volume: 0.001);
      elements.update(1 / 30, eye: Vector3(0.0, 2.0, 2.0));
      // Mutation: leave `surfaceNode.visible` as it was in
      // `LiquidView.update` — the surface still shows switched off.
      expect(view.surfaceNode.isVisible, steps.surface, reason: 'mask $mask');
      expect(view.sheetNode.isVisible, steps.sheet, reason: 'mask $mask');
    }
  });

  test(
    'a fire in the camera\'s picture is seen, and lost when it leaves',
    () async {
      final seen = <NativeBody>[];
      final lost = <NativeBody>[];
      final (elements, crate) = await _burning(seconds: 1.0);
      addTearDown(elements.dispose);
      elements.listener = ElementsListener(
        seen: (f) => seen.add(f.body),
        lost: lost.add,
      );
      final camera = CameraNode(name: 'eye')
        ..setPosition(0.0, 1.0, 4.0)
        ..lookAt(Vector3(0.0, 0.5, 0.0));
      elements.update(1 / 30, eye: Vector3(0.0, 1.0, 4.0), camera: camera);
      // Mutation: test the fire's base rather than its flame's middle, under
      // the picture's bottom edge — never seen.
      expect(seen, <NativeBody>[crate.native]);
      camera.lookAt(Vector3(0.0, 1.0, 10.0));
      elements.update(1 / 30, eye: Vector3(0.0, 1.0, 4.0), camera: camera);
      expect(lost, <NativeBody>[crate.native]);
    },
  );

  test('a step that wants more than it holds says so', () async {
    final budgets = <String>[];
    final (elements, _) = await _burning(seconds: 1.0);
    addTearDown(elements.dispose);
    elements.listener = ElementsListener(
      budget: (step, wanted, holds) => budgets.add(step),
    );
    elements.update(1 / 30, eye: Vector3.zero());
    // A crate heated through gives off a hundred kilowatts: its plume
    // stays dark far higher than a phone's puffs reach. Mutation: compare
    // with `>=` the wrong way round in `Elements.update` — never told.
    expect(budgets, contains('smoke'));
  });
}
