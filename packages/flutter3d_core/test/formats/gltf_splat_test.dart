/// `KHR_gaussian_splatting` primitives decode into `ModelDocument.splats` —
/// `C1`.
///
///     dart test test/formats/gltf_splat_test.dart
///
/// The conventions that differ from a PLY capture are the ones held here:
/// linear opacity, linear scale, `xyzw` quaternions, and a declared colour
/// space. Each is a way to load a cloud that draws and is wrong.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

import 'helpers/splat_gltf.dart';

const _k = 'KHR_gaussian_splatting';

/// One splat, every attribute a float, with the values given.
List<SplatAttribute> _one({
  double opacity = 1.0,
  List<double> scale = const <double>[0.1, 0.2, 0.3],
  List<double> rotation = const <double>[0.0, 0.0, 0.0, 1.0],
  List<double> colour = const <double>[0.5, 0.5, 0.5],
  List<SplatAttribute> extra = const <SplatAttribute>[],
}) => <SplatAttribute>[
  floats('POSITION', 'VEC3', <double>[1.0, 2.0, 3.0]),
  floats('$_k:ROTATION', 'VEC4', rotation),
  floats('$_k:SCALE', 'VEC3', scale),
  floats('$_k:OPACITY', 'SCALAR', <double>[opacity]),
  floats('$_k:SH_DEGREE_0_COEF_0', 'VEC3', <double>[
    for (final c in colour) coefficientFor(c),
  ]),
  ...extra,
];

Future<GltfAsset> _load(List<int> bytes) =>
    GltfLoader().load(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));

void main() {
  group('the checked-in grid', () {
    late GltfAsset asset;
    setUpAll(() async {
      asset = await _load(
        File('test/formats/fixtures/splat/splat_grid.glb').readAsBytesSync(),
      );
    });

    test('is one cloud of nine on node 0, and no surface', () {
      expect(asset.splats, hasLength(1));
      final splat = asset.splats.single;
      expect(splat.node, 0);
      expect(splat.cloud.count, 9);
      expect(splat.colourSpace, SplatColourSpace.srgb);
      expect(asset.surfaces, isEmpty);
      expect(
        asset.warnings,
        isEmpty,
        reason: 'a splat primitive is not a point cloud to warn about',
      );
    });

    test('carries the node placement', () {
      final t = asset.splats.single.transform;
      expect(t.getTranslation().x, closeTo(0.5, 1e-6));
      expect(t.getMaxScaleOnAxis(), closeTo(0.8, 1e-6));
    });

    test('colours by column, red, green, blue', () {
      final colours = asset.splats.single.cloud.colours;
      for (var i = 0; i < 9; i++) {
        final column = i % 3;
        for (var c = 0; c < 3; c++) {
          expect(
            colours[i * 4 + c],
            closeTo(c == column ? 1.0 : 0.0, 1e-5),
            reason: 'splat $i channel $c',
          );
        }
        expect(colours[i * 4 + 3], closeTo(1.0, 1e-6), reason: 'opacity');
      }
    });

    test('reads the normalized-short quaternion as a unit one', () {
      // The middle splat is a quarter turn about Z. Mutation: drop the
      // renormalisation — 23170 / 32767 squared twice is not quite one, and
      // the length check below fails.
      final r = asset.splats.single.cloud.rotations;
      final q = 4 * 4;
      expect(r[q + 2], closeTo(math.sqrt(0.5), 1e-4));
      expect(r[q + 3], closeTo(math.sqrt(0.5), 1e-4));
      final length = math.sqrt(
        r[q] * r[q] +
            r[q + 1] * r[q + 1] +
            r[q + 2] * r[q + 2] +
            r[q + 3] * r[q + 3],
      );
      expect(length, closeTo(1.0, 1e-6));
    });

    test('keeps band 1 of the harmonics without drawing it', () {
      final cloud = asset.splats.single.cloud;
      expect(cloud.shDegree, 1);
      expect(cloud.shRestFloatsPerSplat, 9);
      // Coefficient 2 of band 1, blue, of splat 0: 0.03 × 2.
      expect(cloud.shRest[2 * 3 + 2], closeTo(0.06, 1e-6));
    });
  });

  test('opacity is linear, not a logit', () async {
    // Mutation: pass the opacity through `splatOpacity` as the PLY reader
    // does — 0.25 becomes 0.56.
    final asset = await _load(splatGlb(attributes: _one(opacity: 0.25)));
    expect(asset.splats.single.cloud.colours[3], closeTo(0.25, 1e-6));
  });

  test('scale is linear, not a logarithm', () async {
    final asset = await _load(splatGlb(attributes: _one()));
    final scales = asset.splats.single.cloud.scales;
    expect(scales[0], closeTo(0.1, 1e-6));
    expect(scales[2], closeTo(0.3, 1e-6));
  });

  test('an sRGB cloud is decoded to linear, a linear one is not', () async {
    // Mutation: skip `srgbToLinear` — the sRGB grey stays at 0.5.
    final srgb = await _load(splatGlb(attributes: _one()));
    expect(srgb.splats.single.cloud.colours[0], closeTo(0.2140, 1e-4));

    final linear = await _load(
      splatGlb(
        attributes: _one(),
        extension: const <String, Object?>{
          'kernel': 'ellipse',
          'colorSpace': 'lin_rec709_display',
        },
      ),
    );
    expect(linear.splats.single.colourSpace, SplatColourSpace.linear);
    expect(linear.splats.single.cloud.colours[0], closeTo(0.5, 1e-6));
  });

  test('a negative colour clamps to nought', () async {
    final asset = await _load(
      splatGlb(
        attributes: _one(colour: const <double>[-0.4, 0.5, 0.5]),
        extension: const <String, Object?>{
          'kernel': 'ellipse',
          'colorSpace': 'lin_rec709_display',
        },
      ),
    );
    expect(asset.splats.single.cloud.colours[0], 0.0);
  });

  test('a file that requires the extension loads', () async {
    final asset = await _load(
      splatGlb(attributes: _one(), extensionsRequired: const <String>[_k]),
    );
    expect(asset.splats, hasLength(1));
  });

  test(
    'a primitive missing a required attribute is skipped, by name',
    () async {
      final asset = await _load(
        splatGlb(
          attributes: <SplatAttribute>[
            for (final a in _one())
              if (a.semantic != '$_k:OPACITY') a,
          ],
        ),
      );
      expect(asset.splats, isEmpty);
      expect(asset.warnings.join('\n'), contains('$_k:OPACITY'));
    },
  );

  test('a band only partly there is dropped with the ones above it', () async {
    final asset = await _load(
      splatGlb(
        attributes: _one(
          extra: <SplatAttribute>[
            for (var n = 0; n < 3; n++)
              floats('$_k:SH_DEGREE_1_COEF_$n', 'VEC3', <double>[0, 0, 0]),
            // Two of band 2's five.
            for (var n = 0; n < 2; n++)
              floats('$_k:SH_DEGREE_2_COEF_$n', 'VEC3', <double>[0, 0, 0]),
          ],
        ),
      ),
    );
    expect(asset.splats.single.cloud.shDegree, 1);
    expect(asset.warnings.join('\n'), contains('degree 2 is partly defined'));
  });

  test('an unknown kernel is read as the ellipse, and said so', () async {
    final asset = await _load(
      splatGlb(
        attributes: _one(),
        extension: const <String, Object?>{
          'kernel': 'customShape',
          'colorSpace': 'srgb_rec709_display',
        },
      ),
    );
    expect(asset.splats, hasLength(1));
    expect(asset.warnings.join('\n'), contains('customShape'));
  });
}
