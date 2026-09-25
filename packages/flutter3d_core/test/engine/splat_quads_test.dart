/// The quads a cloud is drawn as — `gfx-80n`.
///
///     dart test test/engine/splat_quads_test.dart
///
/// A splat reaches the screen as an ellipse, and this is where a point becomes
/// one. The arithmetic is separated from the drawing exactly so that it can be
/// checked without a device, the split `MeshOverlay` already makes; what the
/// tests below hold is the shape of the ellipse, the order the quads come out
/// in, and the corner coordinates the fragment stage evaluates its falloff
/// from.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A cloud of [scales]-sized splats at [centres], unrotated and opaque.
SplatCloud _cloud({
  required List<Vector3> centres,
  required List<Vector3> scales,
  List<Quaternion>? rotations,
}) {
  final n = centres.length;
  final c = Float32List(n * 3);
  final colours = Float32List(n * 4);
  final s = Float32List(n * 3);
  final r = Float32List(n * 4);
  for (var i = 0; i < n; i++) {
    c[i * 3] = centres[i].x;
    c[i * 3 + 1] = centres[i].y;
    c[i * 3 + 2] = centres[i].z;
    colours[i * 4] = 1.0;
    colours[i * 4 + 1] = 1.0;
    colours[i * 4 + 2] = 1.0;
    colours[i * 4 + 3] = 1.0;
    s[i * 3] = scales[i].x;
    s[i * 3 + 1] = scales[i].y;
    s[i * 3 + 2] = scales[i].z;
    final q = rotations?[i] ?? Quaternion.identity();
    r[i * 4] = q.x;
    r[i * 4 + 1] = q.y;
    r[i * 4 + 2] = q.z;
    r[i * 4 + 3] = q.w;
  }
  return SplatCloud(centres: c, colours: colours, scales: s, rotations: r);
}

/// The camera looking down −Z from the origin, with its own basis.
const _right = (x: 1.0, y: 0.0, z: 0.0);

void _build(SplatQuads quads) => quads.build(
  eye: Vector3.zero(),
  right: Vector3(_right.x, _right.y, _right.z),
  up: Vector3(0.0, 1.0, 0.0),
);

/// The [component]th float of vertex [vertex].
double _at(SplatQuads quads, int vertex, int component) =>
    quads.vertices[vertex * kSplatFloatsPerVertex + component];

void main() {
  test('one splat becomes two triangles', () {
    final quads = SplatQuads(
      _cloud(
        centres: <Vector3>[Vector3(0.0, 0.0, -5.0)],
        scales: <Vector3>[Vector3(0.1, 0.1, 0.1)],
      ),
    );
    _build(quads);
    expect(quads.vertexCount, kSplatVerticesPerSplat);
  });

  test('the corners carry standard deviations, not texture coordinates', () {
    // What `splat.frag` evaluates `exp(-½ dᵀd)` from. A quad whose corners said
    // zero to one would put the Gaussian's middle in a corner and its tail
    // across the whole quad, which draws as a smear rather than as a blob.
    final quads = SplatQuads(
      _cloud(
        centres: <Vector3>[Vector3(0.0, 0.0, -5.0)],
        scales: <Vector3>[Vector3(0.2, 0.2, 0.2)],
      ),
    );
    _build(quads);

    for (var v = 0; v < kSplatVerticesPerSplat; v++) {
      expect(_at(quads, v, 7).abs(), closeTo(kSplatReach, 1e-5));
      expect(_at(quads, v, 8).abs(), closeTo(kSplatReach, 1e-5));
    }
  });

  test('a round splat makes a square quad of three standard deviations', () {
    // The size claim, against a number worked out rather than read back: an
    // isotropic splat of σ has a quad reaching 3σ each way, so the whole quad
    // is 6σ across.
    const sigma = 0.25;
    final quads = SplatQuads(
      _cloud(
        centres: <Vector3>[Vector3(0.0, 0.0, -5.0)],
        scales: <Vector3>[Vector3(sigma, sigma, sigma)],
      ),
    );
    _build(quads);

    var minX = double.infinity, maxX = double.negativeInfinity;
    var minY = double.infinity, maxY = double.negativeInfinity;
    for (var v = 0; v < kSplatVerticesPerSplat; v++) {
      minX = math.min(minX, _at(quads, v, 0));
      maxX = math.max(maxX, _at(quads, v, 0));
      minY = math.min(minY, _at(quads, v, 1));
      maxY = math.max(maxY, _at(quads, v, 1));
    }
    expect(maxX - minX, closeTo(2 * kSplatReach * sigma, 1e-5));
    expect(maxY - minY, closeTo(2 * kSplatReach * sigma, 1e-5));
  });

  test(
    'a splat stretched along one axis makes a quad stretched the same way',
    () {
      // The ellipse, and that it is the *projected* one: a splat three times as
      // long in world X must be three times as wide on a screen whose right is
      // world X, and no taller.
      final quads = SplatQuads(
        _cloud(
          centres: <Vector3>[Vector3(0.0, 0.0, -5.0)],
          scales: <Vector3>[Vector3(0.6, 0.2, 0.2)],
        ),
      );
      _build(quads);

      var minX = double.infinity, maxX = double.negativeInfinity;
      var minY = double.infinity, maxY = double.negativeInfinity;
      for (var v = 0; v < kSplatVerticesPerSplat; v++) {
        minX = math.min(minX, _at(quads, v, 0));
        maxX = math.max(maxX, _at(quads, v, 0));
        minY = math.min(minY, _at(quads, v, 1));
        maxY = math.max(maxY, _at(quads, v, 1));
      }
      expect(maxX - minX, closeTo(2 * kSplatReach * 0.6, 1e-5));
      expect(maxY - minY, closeTo(2 * kSplatReach * 0.2, 1e-5));
    },
  );

  test('a splat seen end on is as small as its narrow axis', () {
    // The statement that the third axis is projected away rather than added in.
    // A splat long along Z, seen along Z, is a small round dot — a builder that
    // took the largest extent whatever direction it pointed would draw it as a
    // large one.
    final quads = SplatQuads(
      _cloud(
        centres: <Vector3>[Vector3(0.0, 0.0, -5.0)],
        scales: <Vector3>[Vector3(0.1, 0.1, 2.0)],
      ),
    );
    _build(quads);

    var maxX = double.negativeInfinity;
    for (var v = 0; v < kSplatVerticesPerSplat; v++) {
      maxX = math.max(maxX, _at(quads, v, 0));
    }
    expect(maxX, closeTo(kSplatReach * 0.1, 1e-5));
  });

  test('the far splat is written first', () {
    // Back to front, in the buffer as well as in the sort: the draw is one
    // call over the whole array, so the order the vertices sit in *is* the
    // blending order.
    final quads = SplatQuads(
      _cloud(
        centres: <Vector3>[Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, -9.0)],
        scales: <Vector3>[Vector3(0.1, 0.1, 0.1), Vector3(0.1, 0.1, 0.1)],
      ),
    );
    _build(quads);

    expect(quads.vertexCount, 2 * kSplatVerticesPerSplat);
    // The first vertex belongs to the splat at −9, which is the far one.
    expect(_at(quads, 0, 2), lessThan(-5.0));
    expect(_at(quads, kSplatVerticesPerSplat, 2), greaterThan(-5.0));
  });

  test('the colour rides on every corner', () {
    final cloud = _cloud(
      centres: <Vector3>[Vector3(0.0, 0.0, -5.0)],
      scales: <Vector3>[Vector3(0.1, 0.1, 0.1)],
    );
    cloud.colours[0] = 0.25;
    cloud.colours[3] = 0.5;
    final quads = SplatQuads(cloud);
    _build(quads);

    for (var v = 0; v < kSplatVerticesPerSplat; v++) {
      expect(_at(quads, v, 3), closeTo(0.25, 1e-6), reason: 'red');
      expect(_at(quads, v, 6), closeTo(0.5, 1e-6), reason: 'alpha');
    }
  });

  test('rebuilding reuses the buffer', () {
    // A cloud is rebuilt every time the camera moves. Allocating the whole
    // vertex array per frame is what makes a million splats unusable rather
    // than merely expensive.
    final quads = SplatQuads(
      _cloud(
        centres: <Vector3>[Vector3(0.0, 0.0, -5.0)],
        scales: <Vector3>[Vector3(0.1, 0.1, 0.1)],
      ),
    );
    _build(quads);
    final first = quads.vertices;
    _build(quads);
    expect(identical(quads.vertices, first), isTrue);
  });

  group('when it sorts — C1', () {
    SplatQuads grid() => SplatQuads(
      _cloud(
        centres: <Vector3>[
          for (var i = 0; i < 10; i++) Vector3(0.0, 0.0, -1.0 - i),
        ],
        scales: <Vector3>[for (var i = 0; i < 10; i++) Vector3.all(0.1)],
      ),
    );

    test('a camera that only turns does not sort again', () {
      // Mutation: make `_needsSort` return true — `sorts` counts every build.
      final quads = grid();
      _build(quads);
      quads.build(
        eye: Vector3.zero(),
        right: Vector3(0.0, 0.0, 1.0),
        up: Vector3(0.0, 1.0, 0.0),
      );
      expect(quads.sorts, 1);
    });

    test('a small step does not sort again and a long one does', () {
      // The range is 9 m, so the default 0.2 % allows 18 mm.
      final quads = grid();
      _build(quads);
      void at(double x) => quads.build(
        eye: Vector3(x, 0.0, 0.0),
        right: Vector3(1.0, 0.0, 0.0),
        up: Vector3(0.0, 1.0, 0.0),
      );
      at(0.01);
      expect(quads.sorts, 1, reason: '10 mm is inside the threshold');
      at(0.05);
      expect(quads.sorts, 2, reason: '50 mm is outside it');
    });

    test('a threshold of nought sorts on every move', () {
      final quads = grid()..resortFraction = 0.0;
      _build(quads);
      quads.build(
        eye: Vector3(0.001, 0.0, 0.0),
        right: Vector3(1.0, 0.0, 0.0),
        up: Vector3(0.0, 1.0, 0.0),
      );
      expect(quads.sorts, 2);
    });

    test('invalidateSort and a moved model both force one', () {
      final quads = grid();
      _build(quads);
      quads.invalidateSort();
      _build(quads);
      expect(quads.sorts, 2);
      quads.build(
        eye: Vector3.zero(),
        right: Vector3(1.0, 0.0, 0.0),
        up: Vector3(0.0, 1.0, 0.0),
        model: Matrix4.translationValues(0.0, 0.0, 20.0),
      );
      expect(quads.sorts, 3);
    });

    test('the order a skipped sort keeps is still the one drawn', () {
      // The far splat at −10 is first in the buffer, and stays first when
      // the camera turns without the sort running.
      final quads = grid();
      _build(quads);
      quads.build(
        eye: Vector3.zero(),
        right: Vector3(0.0, 0.0, 1.0),
        up: Vector3(0.0, 1.0, 0.0),
      );
      expect(_at(quads, 0, 2), closeTo(-10.0, 1.0));
    });
  });

  test('a cloud placed by a matrix builds what the placed cloud builds', () {
    // The claim `SplatQuads.build` makes for `model`: the ellipse of a cloud
    // placed by `M` is the ellipse of the cloud whose covariance is
    // `M Σ Mᵀ`. Checked against a cloud placed by hand — centres moved,
    // quaternions turned, extents scaled — for a turn, a uniform scale and a
    // move together.
    // Mutation: use the world `right` in place of `Mᵀ right` in the 2×2 —
    // the placed quad keeps the unscaled, unturned extents.
    final turn = Quaternion.axisAngle(Vector3(0.3, 1.0, 0.2).normalized(), 0.7);
    const s = 1.7;
    final move = Vector3(0.4, -0.2, -3.0);
    final model = Matrix4.compose(move, turn, Vector3.all(s));

    final local = <Vector3>[Vector3(0.1, 0.2, 0.3), Vector3(-0.5, 0.0, 0.8)];
    final extents = <Vector3>[Vector3(0.3, 0.1, 0.05), Vector3(0.05, 0.2, 0.1)];
    final spins = <Quaternion>[
      Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), 0.4),
      Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), 1.1),
    ];

    final placed = SplatQuads(
      _cloud(centres: local, scales: extents, rotations: spins),
    );
    final byHand = SplatQuads(
      _cloud(
        centres: <Vector3>[for (final c in local) model.transformed3(c)],
        scales: <Vector3>[for (final e in extents) e * s],
        rotations: <Quaternion>[for (final q in spins) turn * q],
      ),
    );

    final eye = Vector3(0.2, 0.5, 4.0);
    final right = Vector3(1.0, 0.0, 0.2)..normalize();
    final up = Vector3(0.0, 1.0, 0.0);
    placed.build(eye: eye, right: right, up: up, model: model);
    byHand.build(eye: eye, right: right, up: up);

    expect(placed.vertexCount, byHand.vertexCount);
    for (var k = 0; k < placed.vertexCount * kSplatFloatsPerVertex; k++) {
      expect(
        placed.vertices[k],
        closeTo(byHand.vertices[k], 1e-4),
        reason: 'float $k',
      );
    }
  });

  group('through a lens', () {
    // A 60° camera at the origin looking down −Z into a viewport 480 pixels
    // tall: `f = 240 / tan 30°` pixels at unit depth.
    const height = 480.0;
    final projection = makePerspectiveMatrix(math.pi / 3, 4 / 3, 0.1, 100.0);
    final lens = SplatLens.of(projection, Vector3(0.0, 0.0, -1.0), height);
    final focal = 0.5 * height / math.tan(math.pi / 6);

    /// The quad's half extents along world X and Y.
    (double, double) extents(SplatQuads quads, Vector3 centre) {
      var x = 0.0, y = 0.0;
      for (var v = 0; v < kSplatVerticesPerSplat; v++) {
        x = math.max(x, (_at(quads, v, 0) - centre.x).abs());
        y = math.max(y, (_at(quads, v, 1) - centre.y).abs());
      }
      return (x, y);
    }

    void build(SplatQuads quads, {SplatLens? through}) => quads.build(
      eye: Vector3.zero(),
      right: Vector3(1.0, 0.0, 0.0),
      up: Vector3(0.0, 1.0, 0.0),
      lens: through,
    );

    test('the lens is read out of the projection', () {
      expect(lens.focal, closeTo(focal, 1e-3));
      expect(lens.depthWeight, 1.0);
      expect(lens.depthOffset, 0.0);
      expect(lens.tanHalfHeight, closeTo(math.tan(math.pi / 6), 1e-6));
      final ortho = SplatLens.of(
        makeOrthographicMatrix(-2, 2, -1.5, 1.5, 0.1, 100.0),
        Vector3(0.0, 0.0, -1.0),
        height,
      );
      expect(ortho.depthWeight, 0.0);
      expect(ortho.depthOffset, 1.0);
      // Half the viewport's height covers 1.5 world units.
      expect(1.0 / ortho.focal, closeTo(1.5 / (0.5 * height), 1e-9));
    });

    test('a splat long along the view ray and off to the side is a streak', () {
      // `J W Σ Wᵀ Jᵀ` with `J`'s shear: half as far to the side as it is deep,
      // a splat reaching σ = 1 along the ray should cover `(x/z)·σ` = 0.5 in
      // the plane through its centre, across the screen. Projected onto right
      // and up alone it is the 0.02 its narrow axes are — a dot.
      // Mutation: drop the lean (`leanR = 0`) and the quad is 3 × 0.02 wide.
      const sx = 0.02, sz = 1.0;
      final centre = Vector3(2.5, 0.0, -5.0);
      final quads = SplatQuads(
        _cloud(
          centres: <Vector3>[centre],
          scales: <Vector3>[Vector3(sx, sx, sz)],
        ),
      );
      build(quads, through: lens);

      const lean = 2.5 / 5.0;
      final pixel = 5.0 / focal;
      final (x, y) = extents(quads, centre);
      final wide = sx * sx + lean * lean * sz * sz + 0.3 * pixel * pixel;
      expect(x, closeTo(kSplatReach * math.sqrt(wide), 1e-5));
      final tall = sx * sx + 0.3 * pixel * pixel;
      expect(y, closeTo(kSplatReach * math.sqrt(tall), 1e-5));
    });

    test('on the view axis the lens changes nothing but the filter', () {
      // Exact at the middle of the frame, as the header says: the lean is
      // nought there, and what is left is the low-pass filter.
      final centre = Vector3(0.0, 0.0, -5.0);
      final quads = SplatQuads(
        _cloud(
          centres: <Vector3>[centre],
          scales: <Vector3>[Vector3(0.1, 0.3, 2.0)],
        ),
      );
      build(quads, through: lens);
      final filter = 0.3 * math.pow(5.0 / focal, 2);
      final (x, y) = extents(quads, centre);
      expect(x, closeTo(kSplatReach * math.sqrt(0.01 + filter), 1e-5));
      expect(y, closeTo(kSplatReach * math.sqrt(0.09 + filter), 1e-5));
    });

    test('a flat splat seen edge on keeps half a pixel of width', () {
      // A disc in the XZ plane, seen along its own plane, has no extent up the
      // screen at all; without the screen's low-pass filter its quad is a
      // zero-width sliver that rasterises nothing. With it the quad reaches
      // `3 · √0.3` pixels either side of the line. Mutation: drop the
      // dilation and `y` is nought.
      final centre = Vector3(0.0, 0.0, -8.0);
      final quads = SplatQuads(
        _cloud(
          centres: <Vector3>[centre],
          scales: <Vector3>[Vector3(0.2, 0.0, 0.2)],
        ),
      );
      build(quads);
      expect(extents(quads, centre).$2, 0.0);

      build(quads, through: lens);
      final (_, y) = extents(quads, centre);
      expect(y * focal / 8.0, closeTo(kSplatReach * math.sqrt(0.3), 1e-4));
    });

    test('an orthographic lens leans nothing and filters evenly', () {
      // `w` is one everywhere, so the Jacobian has no shear and a pixel is the
      // same size at every depth.
      final ortho = SplatLens.of(
        makeOrthographicMatrix(-2, 2, -1.5, 1.5, 0.1, 100.0),
        Vector3(0.0, 0.0, -1.0),
        height,
      );
      final filter = 0.3 * math.pow(1.5 / (0.5 * height), 2);
      for (final centre in <Vector3>[
        Vector3(0.0, 0.0, -5.0),
        Vector3(1.5, 0.0, -30.0),
      ]) {
        final quads = SplatQuads(
          _cloud(
            centres: <Vector3>[centre],
            scales: <Vector3>[Vector3(0.02, 0.02, 1.0)],
          ),
        );
        build(quads, through: ortho);
        final (x, _) = extents(quads, centre);
        expect(
          x,
          closeTo(kSplatReach * math.sqrt(0.0004 + filter), 1e-5),
          reason: '$centre',
        );
      }
    });

    test('the lean is bounded outside the frame', () {
      // A splat far off to the side and close to the eye would otherwise
      // become a streak the width of the screen.
      final centre = Vector3(50.0, 0.0, -1.0);
      final quads = SplatQuads(
        _cloud(
          centres: <Vector3>[centre],
          scales: <Vector3>[Vector3(0.0, 0.0, 1.0)],
        ),
      );
      build(quads, through: lens);
      final limit = kSplatLeanLimit * lens.tanHalfWidth;
      final filter = 0.3 * math.pow(1.0 / focal, 2);
      expect(
        extents(quads, centre).$1,
        closeTo(kSplatReach * math.sqrt(limit * limit + filter), 1e-5),
      );
    });
  });

  test('an empty cloud builds nothing at all', () {
    final quads = SplatQuads(_cloud(centres: <Vector3>[], scales: <Vector3>[]));
    _build(quads);
    expect(quads.vertexCount, 0);
  });
}
