import 'dart:io';

import 'package:flutter3d_core/formats.dart' show parseMaterial;
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'support.dart';

void main() {
  test('the water takes the scene\'s shadows', () {
    // The sun on the water reaches it through the engine's light loop, which
    // multiplies each light by its shadow: a hull, a bridge or a helicopter
    // over the river darkens what the water scatters and puts out the
    // glint. Mutation: drop the `light` block from `liquid.f3dmat` — the
    // water lights itself and no shadow ever falls on it.
    final program = parseMaterial(
      File('assets_src/liquid.f3dmat').readAsStringSync(),
    );
    expect(program.light, isNotNull);
    final body = File('assets_src/liquid.f3dmat').readAsStringSync();
    expect(body, contains('(ambient + lit)'));
  });

  test(
    'the shipped bundle is the water material, and it moves',
    skip: File('assets/liquid.f3dshaders').existsSync()
        ? false
        : 'no bundle: run `dart run tool/build_materials.dart`, which a build '
              'of any application using the package also does',
    () {
      final look = LiquidLook.of(waterBundle());
      expect(
        look.material.parameters.keys,
        containsAll(<String>[
          'time',
          'chop',
          'eye',
          'pixel',
          'toSun',
          'sunColor',
          'zenith',
          'horizon',
          'absorb',
          'scatter',
          'glow',
        ]),
      );
      look
        ..update(seconds: 2.5, eye: Vector3(1.0, 2.0, 3.0))
        ..wind = 5.0
        ..sun(along: Vector3(0.0, -2.0, 0.0), light: Vector3(2.0, 2.0, 2.0));
      // Held as 32-bit floats, as the material's block is.
      expect(look.material.parameters['time'], <double>[2.5]);
      expect(look.material.parameters['eye'], <double>[1.0, 2.0, 3.0]);
      // Cox and Munk's mean square slope at 5 m/s over the ripples' own.
      expect(
        look.material.parameters['chop']!.single,
        closeTo(rippleSteepness(5.0), 1e-6),
      );
      // Towards the sun, a unit vector, whatever length it was given as.
      expect(look.material.parameters['toSun'], <double>[0.0, 1.0, 0.0]);
    },
  );
}
