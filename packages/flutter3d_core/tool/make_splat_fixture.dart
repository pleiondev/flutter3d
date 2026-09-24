/// Writes `test/formats/fixtures/splat/splat_grid.glb` — `C1`.
///
///     dart run tool/make_splat_fixture.dart
///
/// Nine splats on a three-by-three grid in the node's own XY plane, one
/// colour per column (red, green, blue, left to right), under a node that
/// moves them half a metre right and scales them by 0.8. The middle one is
/// long and turned a quarter about Z, so it stands taller than it is wide.
///
/// The file exercises the paths a real export takes rather than the easy
/// ones: rotations are normalized signed shorts, opacities normalized
/// unsigned bytes, and band 1 of the spherical harmonics is present, so the
/// reader has to keep it without drawing it. Checked in, so the test that
/// draws it does not depend on this script, and regenerated only on purpose.
library;

import 'dart:io';
import 'dart:math' as math;

import '../test/formats/helpers/splat_gltf.dart';

void main() {
  const k = 'KHR_gaussian_splatting';
  final positions = <double>[];
  final scales = <double>[];
  final rotations = <int>[];
  final opacities = <int>[];
  final dc = <double>[];
  final band1 = <List<double>>[<double>[], <double>[], <double>[]];

  // A quarter turn about Z, as a signed-short quaternion.
  final quarter = (math.sqrt(0.5) * 32767).round();

  for (var row = 0; row < 3; row++) {
    for (var column = 0; column < 3; column++) {
      positions.addAll(<double>[column - 1.0, 1.0 - row, 0.0]);
      final middle = row == 1 && column == 1;
      scales.addAll(
        middle ? <double>[0.4, 0.12, 0.12] : <double>[0.18, 0.18, 0.18],
      );
      rotations.addAll(
        middle ? <int>[0, 0, quarter, quarter] : <int>[0, 0, 0, 32767],
      );
      opacities.add(255);
      dc.addAll(<double>[
        coefficientFor(column == 0 ? 1.0 : 0.0),
        coefficientFor(column == 1 ? 1.0 : 0.0),
        coefficientFor(column == 2 ? 1.0 : 0.0),
      ]);
      for (var n = 0; n < 3; n++) {
        band1[n].addAll(<double>[0.01 * n, 0.02 * n, 0.03 * n]);
      }
    }
  }

  final glb = splatGlb(
    attributes: <SplatAttribute>[
      floats('POSITION', 'VEC3', positions),
      normalized('$k:ROTATION', 'VEC4', kGlShort, rotations),
      floats('$k:SCALE', 'VEC3', scales),
      normalized('$k:OPACITY', 'SCALAR', kGlUnsignedByte, opacities),
      floats('$k:SH_DEGREE_0_COEF_0', 'VEC3', dc),
      for (var n = 0; n < 3; n++)
        floats('$k:SH_DEGREE_1_COEF_$n', 'VEC3', band1[n]),
    ],
    node: <String, Object?>{
      'translation': <double>[0.5, 0.0, 0.0],
      'scale': <double>[0.8, 0.8, 0.8],
    },
  );

  final out = File('test/formats/fixtures/splat/splat_grid.glb')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(glb);
  stdout.writeln('wrote ${out.path}, ${glb.length} bytes');
}
