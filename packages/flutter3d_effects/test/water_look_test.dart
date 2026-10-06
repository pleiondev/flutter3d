import 'dart:io';

import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'support.dart';

void main() {
  test(
    'the shipped bundle is the water material, and it moves',
    skip: File('assets/water.f3dshaders').existsSync()
        ? false
        : 'no bundle: run `dart run tool/build_materials.dart`, which a build '
              'of any application using the package also does',
    () {
      final look = WaterLook.of(waterBundle());
      expect(
        look.material.parameters.keys,
        containsAll(<String>[
          'time',
          'chop',
          'eye',
          'toSun',
          'sunColor',
          'zenith',
          'horizon',
        ]),
      );
      look
        ..update(seconds: 2.5, eye: Vector3(1.0, 2.0, 3.0))
        ..chop = 1.6
        ..sun(along: Vector3(0.0, -2.0, 0.0), light: Vector3(2.0, 2.0, 2.0));
      // Held as 32-bit floats, as the material's block is.
      expect(look.material.parameters['time'], <double>[2.5]);
      expect(look.material.parameters['eye'], <double>[1.0, 2.0, 3.0]);
      expect(look.material.parameters['chop']!.single, closeTo(1.6, 1e-6));
      // Towards the sun, a unit vector, whatever length it was given as.
      expect(look.material.parameters['toSun'], <double>[0.0, 1.0, 0.0]);
    },
  );
}
