/// A fitted Gaussian cloud loads and sorts — `gfx-80n`.
///
///     dart test test/formats/splat_test.dart
///
/// **Three conventions the PLY header does not mention, and each is a way to
/// load a cloud that draws and is wrong.** `opacity` is a logit, `scale_*` are
/// logarithms, `f_dc_*` are the zeroth spherical-harmonic band. A reader that
/// takes any of the three literally produces a picture that reads as a bad
/// capture rather than as a bad reader, which is exactly the failure that
/// survives review — so each one is checked here against a number worked out by
/// hand rather than against the reader's own output.
///
/// The fixtures are assembled here, byte by byte, from the format's own layout.
/// That is legitimate where it was not for a block-compressed texture: a binary
/// PLY is a text header and packed rows, so a file built here is verifiably the
/// file the format describes, and what the test is really checking is the
/// arithmetic on top of it — which is formulas, not a bit-packing puzzle.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// One splat's worth of stored parameters, in the file's own units.
typedef _Row = ({
  double x,
  double y,
  double z,
  double dc0,
  double dc1,
  double dc2,
  double opacity,
  double s0,
  double s1,
  double s2,
  double rotW,
  double rotX,
  double rotY,
  double rotZ,
});

_Row _row({
  double x = 0,
  double y = 0,
  double z = 0,
  double dc0 = 0,
  double dc1 = 0,
  double dc2 = 0,
  double opacity = 0,
  double s0 = 0,
  double s1 = 0,
  double s2 = 0,
  double rotW = 1,
  double rotX = 0,
  double rotY = 0,
  double rotZ = 0,
}) => (
  x: x,
  y: y,
  z: z,
  dc0: dc0,
  dc1: dc1,
  dc2: dc2,
  opacity: opacity,
  s0: s0,
  s1: s1,
  s2: s2,
  rotW: rotW,
  rotX: rotX,
  rotY: rotY,
  rotZ: rotZ,
);

/// A binary little-endian PLY holding [rows], in the property order every
/// trainer writes.
Uint8List _ply(List<_Row> rows, {String format = 'binary_little_endian'}) {
  const names = <String>[
    'x', 'y', 'z', //
    'f_dc_0', 'f_dc_1', 'f_dc_2', //
    'opacity', //
    'scale_0', 'scale_1', 'scale_2', //
    'rot_0', 'rot_1', 'rot_2', 'rot_3', //
  ];
  final header = StringBuffer()
    ..writeln('ply')
    ..writeln('format $format 1.0')
    ..writeln('element vertex ${rows.length}');
  for (final name in names) {
    header.writeln('property float $name');
  }
  header.writeln('end_header');

  final head = header.toString().codeUnits;
  final body = Float32List(rows.length * names.length);
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final at = i * names.length;
    body[at] = r.x;
    body[at + 1] = r.y;
    body[at + 2] = r.z;
    body[at + 3] = r.dc0;
    body[at + 4] = r.dc1;
    body[at + 5] = r.dc2;
    body[at + 6] = r.opacity;
    body[at + 7] = r.s0;
    body[at + 8] = r.s1;
    body[at + 9] = r.s2;
    body[at + 10] = r.rotW;
    body[at + 11] = r.rotX;
    body[at + 12] = r.rotY;
    body[at + 13] = r.rotZ;
  }
  return Uint8List.fromList(<int>[
    ...head,
    ...body.buffer.asUint8List(body.offsetInBytes, body.lengthInBytes),
  ]);
}

void main() {
  group('the three conventions the header leaves out', () {
    test('opacity is a logit, not an alpha', () {
      // Zero stored is a half shown, which is the whole point: a reader that
      // passed the number through would draw a cloud of invisible splats
      // wherever the trainer converged on a negative logit.
      final cloud = parseSplatPly(_ply(<_Row>[_row(opacity: 0.0)]));
      expect(cloud.colours[3], closeTo(0.5, 1e-6));

      final opaque = parseSplatPly(_ply(<_Row>[_row(opacity: 4.0)]));
      expect(opaque.colours[3], closeTo(1.0 / (1.0 + math.exp(-4.0)), 1e-6));
      expect(opaque.colours[3], greaterThan(0.98));
    });

    test('scale is a logarithm, not an extent', () {
      // Zero stored is one unit of reach. Taken literally it would be a splat
      // with no size at all, and a cloud of them draws as nothing — which is
      // the version of this bug that at least announces itself.
      final cloud = parseSplatPly(
        _ply(<_Row>[_row(s0: 0.0, s1: math.ln2, s2: -1.0)]),
      );
      expect(cloud.scales[0], closeTo(1.0, 1e-6));
      expect(cloud.scales[1], closeTo(2.0, 1e-6));
      expect(cloud.scales[2], closeTo(math.exp(-1.0), 1e-6));
    });

    test('colour is a spherical-harmonic coefficient, not a channel', () {
      // Zero stored is mid grey, because the zeroth band is an offset from a
      // half. A reader that took it as a channel would make every flat-lit
      // capture come out black.
      // Read as linear (the file says nothing, so the test says it), which
      // leaves the offset alone to check.
      final cloud = parseSplatPly(
        _ply(<_Row>[_row(dc0: 0.0, dc1: 1.0)]),
        colourSpace: SplatColourSpace.linear,
      );
      expect(cloud.colours[0], closeTo(0.5, 1e-6));
      expect(cloud.colours[1], closeTo(0.5 + kSplatShC0, 1e-6));
    });

    test('colour is sRGB-encoded, and decoded to linear by default', () {
      // A trainer fits band 0 to sRGB photographs, so a stored grey of a half
      // is a displayed grey of a half. Taken as linear it is encoded again on
      // the way out and shows as about 0.735: the capture washed out.
      // Mutation: drop the decode in `splatColour` and this reads 0.5.
      final cloud = parseSplatPly(_ply(<_Row>[_row(dc0: 0.0, dc1: 1.0)]));
      expect(cloud.colours[0], closeTo(_srgbToLinear(0.5), 1e-6));
      expect(cloud.colours[1], closeTo(_srgbToLinear(0.5 + kSplatShC0), 1e-6));
      expect(cloud.colours[0], closeTo(0.2140, 1e-4));
    });

    test('a colour below nought clamps, as the fit did', () {
      // The reference rasteriser returns `max(0.5 + C0·c, 0)`, so nothing in
      // training pushed such a coefficient back up and trained files are full
      // of them. Left negative, the splat subtracts light under the
      // premultiplied blend: a dark speck. Mutation: drop the `max` and these
      // come out negative.
      for (final space in SplatColourSpace.values) {
        final cloud = parseSplatPly(
          _ply(<_Row>[_row(dc0: -3.0, dc1: -1.7724538509055159 - 0.5)]),
          colourSpace: space,
        );
        expect(cloud.colours[0], 0.0, reason: '$space');
        expect(cloud.colours[1], 0.0, reason: '$space');
      }
    });

    test('an sRGB colour clamps at one, and a linear one keeps its light', () {
      // The sRGB curve is defined on [0, 1]; a linear channel above one is a
      // highlight, which the tone curve and not the reader deals with.
      final srgb = parseSplatPly(_ply(<_Row>[_row(dc0: 4.0)]));
      expect(srgb.colours[0], closeTo(1.0, 1e-6));
      final linear = parseSplatPly(
        _ply(<_Row>[_row(dc0: 4.0)]),
        colourSpace: SplatColourSpace.linear,
      );
      expect(linear.colours[0], closeTo(0.5 + 4.0 * kSplatShC0, 1e-6));
    });
  });

  test('the quaternion is reordered from the file, not copied', () {
    // The file writes `w` first and this engine writes it last. A copy turns
    // every splat by whatever rotation the misreading names, which looks like
    // a capture full of streaks rather than like a swapped component.
    final cloud = parseSplatPly(
      _ply(<_Row>[_row(rotW: 0.0, rotX: 1.0, rotY: 0.0, rotZ: 0.0)]),
    );
    expect(cloud.rotations[0], closeTo(1.0, 1e-6), reason: 'x');
    expect(cloud.rotations[3], closeTo(0.0, 1e-6), reason: 'w');
  });

  test('an unnormalised quaternion is normalised on the way in', () {
    // A trainer writes whatever it converged to. Left alone it would scale the
    // ellipsoid as well as turn it, so a cloud would grow or shrink according
    // to how close its rotations happened to land.
    final cloud = parseSplatPly(
      _ply(<_Row>[_row(rotW: 2.0, rotX: 2.0, rotY: 0.0, rotZ: 0.0)]),
    );
    final length = math.sqrt(
      cloud.rotations[0] * cloud.rotations[0] +
          cloud.rotations[1] * cloud.rotations[1] +
          cloud.rotations[2] * cloud.rotations[2] +
          cloud.rotations[3] * cloud.rotations[3],
    );
    expect(length, closeTo(1.0, 1e-6));
  });

  group('the covariance', () {
    test('an unrotated splat has its extents squared on the diagonal', () {
      final cloud = parseSplatPly(
        _ply(<_Row>[_row(s0: 0.0, s1: math.ln2, s2: math.log(3.0))]),
      );
      final sigma = Float32List(6);
      cloud.covarianceOf(0, sigma);
      expect(sigma[0], closeTo(1.0, 1e-5), reason: 'xx');
      expect(sigma[3], closeTo(4.0, 1e-5), reason: 'yy');
      expect(sigma[5], closeTo(9.0, 1e-5), reason: 'zz');
      // Nothing off the diagonal, because nothing is turned.
      expect(sigma[1].abs(), lessThan(1e-5), reason: 'xy');
      expect(sigma[2].abs(), lessThan(1e-5), reason: 'xz');
      expect(sigma[4].abs(), lessThan(1e-5), reason: 'yz');
    });

    test('a quarter turn about Z swaps the x and y extents', () {
      // The statement that the rotation is applied at all, and applied the
      // right way round: `R S Sᵀ Rᵀ` and not `S R Rᵀ Sᵀ`, which is the same
      // matrix for a sphere and a different one for everything else.
      final half = math.sqrt(0.5);
      final cloud = parseSplatPly(
        _ply(<_Row>[_row(s0: 0.0, s1: math.log(3.0), rotW: half, rotZ: half)]),
      );
      final sigma = Float32List(6);
      cloud.covarianceOf(0, sigma);
      expect(sigma[0], closeTo(9.0, 1e-4), reason: 'xx took the y extent');
      expect(sigma[3], closeTo(1.0, 1e-4), reason: 'yy took the x extent');
    });
  });

  group('the sort', () {
    test('is far to near, which is the order blending needs', () {
      // Back to front and not a depth test: a Gaussian is translucent
      // everywhere, so two overlapping ones give a different colour depending
      // on which was drawn first. Getting it backwards does not look like an
      // ordering bug, it looks like the wrong colours.
      final cloud = parseSplatPly(
        _ply(<_Row>[_row(z: -2.0), _row(z: -9.0), _row(z: -5.0)]),
      );
      final order = cloud.sortedBackToFront(
        Vector3.zero(),
        Vector3(0.0, 0.0, -1.0),
      );
      expect(order, orderedEquals(<int>[1, 2, 0]));
    });

    test('is along the view axis, so turning the camera reorders it', () {
      final cloud = parseSplatPly(_ply(<_Row>[_row(x: 1.0), _row(x: 5.0)]));
      final looking = cloud.sortedBackToFront(
        Vector3.zero(),
        Vector3(1.0, 0.0, 0.0),
      );
      expect(looking, orderedEquals(<int>[1, 0]));

      final away = cloud.sortedBackToFront(
        Vector3.zero(),
        Vector3(-1.0, 0.0, 0.0),
      );
      expect(away, orderedEquals(<int>[0, 1]));
    });

    test('writes into a buffer it is given', () {
      // A frame sorts every time the camera moves, so a million splats must
      // not be a million allocations per turn of the mouse.
      final cloud = parseSplatPly(_ply(<_Row>[_row(z: -1.0), _row(z: -2.0)]));
      final into = Int32List(2);
      final result = cloud.sortedBackToFront(
        Vector3.zero(),
        Vector3(0.0, 0.0, -1.0),
        into: into,
      );
      expect(identical(result, into), isTrue);
      expect(into, orderedEquals(<int>[1, 0]));
    });
  });

  group('what is refused, and why the message says so', () {
    test('a plain point cloud is not a fitted one', () {
      final header =
          'ply\nformat binary_little_endian 1.0\nelement vertex 1\n'
          'property float x\nproperty float y\nproperty float z\nend_header\n';
      final bytes = Uint8List.fromList(<int>[
        ...header.codeUnits,
        ...Float32List.fromList(<double>[1, 2, 3]).buffer.asUint8List(),
      ]);
      expect(
        () => parseSplatPly(bytes),
        throwsA(
          isA<SplatPlyException>().having(
            (e) => e.message,
            'message',
            contains('f_dc_0'),
          ),
        ),
      );
    });

    test('an ASCII PLY is refused with the reason', () {
      expect(
        () => parseSplatPly(_ply(<_Row>[_row()], format: 'ascii')),
        throwsA(
          isA<SplatPlyException>().having(
            (e) => e.message,
            'message',
            contains('binary_little_endian'),
          ),
        ),
      );
    });

    test('a file that is not a PLY at all', () {
      expect(
        () => parseSplatPly(Uint8List.fromList('not a ply'.codeUnits)),
        throwsA(isA<SplatPlyException>()),
      );
    });

    test('a header claiming more rows than the file holds', () {
      final whole = _ply(<_Row>[_row(), _row()]);
      expect(
        () => parseSplatPly(Uint8List.sublistView(whole, 0, whole.length - 20)),
        throwsA(
          isA<SplatPlyException>().having(
            (e) => e.message,
            'message',
            contains('past the end'),
          ),
        ),
      );
    });
  });

  test('a cloud with mismatched arrays cannot be built at all', () {
    // The invariant every loop in the renderer relies on, checked where the
    // object is made rather than where it is drawn.
    expect(
      () => SplatCloud(
        centres: Float32List(6),
        colours: Float32List(4),
        scales: Float32List(6),
        rotations: Float32List(8),
      ),
      throwsArgumentError,
    );
  });
}

/// IEC 61966-2-1's decode, written out here so the test does not check the
/// engine's curve against itself.
double _srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
