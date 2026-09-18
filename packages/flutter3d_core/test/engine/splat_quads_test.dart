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
import 'package:flutter3d_core/formats.dart';
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
  forward: Vector3(0.0, 0.0, -1.0),
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

  test('an empty cloud builds nothing at all', () {
    final quads = SplatQuads(_cloud(centres: <Vector3>[], scales: <Vector3>[]));
    _build(quads);
    expect(quads.vertexCount, 0);
  });
}
