import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'support.dart';

void main() {
  setUpAll(buildBundles);

  test('the sea floor material is shipped, and moves with the surface', () {
    final look = SeabedLook.of(
      ByteData.sublistView(File('assets/seabed.f3dshaders').readAsBytesSync()),
    );
    expect(
      look.material.parameters.keys,
      containsAll(<String>[
        'time',
        'chop',
        'eye',
        'level',
        'toSun',
        'sunColor',
        'absorb',
        'scatter',
      ]),
    );
    look
      ..update(seconds: 3.0, eye: Vector3(0.0, -2.0, 0.0), level: 1.5)
      ..optics = LiquidOptics.pureWater
      ..sun(along: Vector3(0.0, -1.0, 0.0), light: Vector3(2.0, 2.0, 2.0));
    expect(look.material.parameters['level'], <double>[1.5]);
    expect(look.material.parameters['toSun'], <double>[0.0, 1.0, 0.0]);
  });
}
