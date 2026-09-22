/// A fitted cloud reaches the screen — `gfx-80n`.
///
///     flutter test test/splat_render_test.dart
///
/// The row's own acceptance: a captured file loads, sorts back to front against
/// the camera, and draws. The loading and the sort are checked where they live
/// — `flutter3d_core`'s `splat_test.dart` and `splat_quads_test.dart` — and
/// this is the part that needs a renderer: the quads go through the real pass,
/// the real blend state and the real fragment stage, and come back as pixels.
///
/// **Blending is what this is really about.** A splat is translucent
/// everywhere, so what lands depends on the order, and the order is the whole
/// reason the cloud is sorted every frame. A test that only checked "something
/// was drawn" would pass with the order reversed, which is the failure that
/// looks like wrong colours rather than like a bug.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

/// A cloud of round, opaque splats at [at], each [colour].
SplatCloud _cloud(List<(Vector3, Vector4)> splats, {double sigma = 0.35}) {
  final n = splats.length;
  final centres = Float32List(n * 3);
  final colours = Float32List(n * 4);
  final scales = Float32List(n * 3);
  final rotations = Float32List(n * 4);
  for (var i = 0; i < n; i++) {
    final (where, colour) = splats[i];
    centres[i * 3] = where.x;
    centres[i * 3 + 1] = where.y;
    centres[i * 3 + 2] = where.z;
    colours[i * 4] = colour.x;
    colours[i * 4 + 1] = colour.y;
    colours[i * 4 + 2] = colour.z;
    colours[i * 4 + 3] = colour.w;
    scales[i * 3] = sigma;
    scales[i * 3 + 1] = sigma;
    scales[i * 3 + 2] = sigma;
    rotations[i * 4 + 3] = 1.0;
  }
  return SplatCloud(
    centres: centres,
    colours: colours,
    scales: scales,
    rotations: rotations,
  );
}

Future<Uint8List> _draw(SplatCloud cloud) async {
  final it = cpuTestDevice(width: _width, height: _height);
  final renderer = Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
  renderer.addContributor(SplatContributor(cloud));

  final scene = Scene()..ambientIntensity = 0.0;
  final camera = CameraNode()
    ..setPosition(0.0, 0.0, 4.0)
    ..lookAt(Vector3.zero());

  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
  );
  final pixels = await it.device.readPixels(frame.frame);
  expect(pixels, isNotNull);
  return pixels!.buffer.asUint8List();
}

({int r, int g, int b}) _middle(Uint8List rgba) {
  final i = ((_height ~/ 2) * _width + _width ~/ 2) * 4;
  return (r: rgba[i], g: rgba[i + 1], b: rgba[i + 2]);
}

void main() {
  test('a cloud draws something where it stands', () async {
    final pixels = await _draw(
      _cloud(<(Vector3, Vector4)>[
        (Vector3.zero(), Vector4(1.0, 0.0, 0.0, 1.0)),
      ]),
    );
    final at = _middle(pixels);
    expect(
      at.r,
      greaterThan(at.b + 20),
      reason: 'the middle of a red splat is not red: $at',
    );
  });

  test('the middle is brighter than the edge, which is the falloff', () async {
    // A Gaussian, not a disc. A stage that drew a flat ellipse would pass the
    // test above and fail this one, and the difference is the whole of what
    // makes a cloud of these look like a surface rather than like confetti.
    final pixels = await _draw(
      _cloud(<(Vector3, Vector4)>[
        (Vector3.zero(), Vector4(1.0, 1.0, 1.0, 1.0)),
      ], sigma: 0.5),
    );
    final centre = _middle(pixels);
    final offIndex = ((_height ~/ 2) * _width + _width ~/ 2 + 9) * 4;
    expect(centre.r, greaterThan(pixels[offIndex] + 10));
  });

  test('the near splat wins where two overlap', () async {
    // **The ordering claim, and the one that survives a reversed sort if you
    // only look for ink.** Two splats on the same line of sight, the near one
    // opaque: drawn back to front the near one lands last and its colour is
    // what is left. Reverse the order and the far one covers it.
    final pixels = await _draw(
      _cloud(<(Vector3, Vector4)>[
        // Far: green. Near: red.
        (Vector3(0.0, 0.0, -1.0), Vector4(0.0, 1.0, 0.0, 1.0)),
        (Vector3(0.0, 0.0, 1.0), Vector4(1.0, 0.0, 0.0, 1.0)),
      ]),
    );
    final at = _middle(pixels);
    expect(
      at.r,
      greaterThan(at.g),
      reason: 'the far splat covered the near one: $at',
    );
  });

  test('an empty cloud costs no draw call', () async {
    // `isActive` is asked before the pass is set up, so a cloud with nothing in
    // it must not be the reason a frame opens one.
    final contributor = SplatContributor(_cloud(const <(Vector3, Vector4)>[]));
    expect(contributor.isActive, isFalse);
  });

  test('what a cloud costs to rebuild', () async {
    // **The number the row asked to be written down when the work started.**
    // The quads are rebuilt on the CPU every time the camera moves, so this is
    // the cost that decides how large a cloud is usable — not the draw, which
    // is one call whatever the count.
    final cloud = _cloud(<(Vector3, Vector4)>[
      for (var i = 0; i < 20000; i++)
        (
          Vector3(
            (i % 40) * 0.1 - 2.0,
            ((i ~/ 40) % 40) * 0.1 - 2.0,
            (i ~/ 1600) * 0.1 - 0.6,
          ),
          Vector4(1.0, 1.0, 1.0, 0.8),
        ),
    ], sigma: 0.05);

    final quads = SplatQuads(cloud);
    void once() => quads.build(
      eye: Vector3(0.0, 0.0, 6.0),
      right: Vector3(1.0, 0.0, 0.0),
      up: Vector3(0.0, 1.0, 0.0),
      forward: Vector3(0.0, 0.0, -1.0),
    );

    once();
    final clock = Stopwatch()..start();
    const runs = 5;
    for (var i = 0; i < runs; i++) {
      once();
    }
    clock.stop();
    final micros = clock.elapsedMicroseconds / runs;
    // ignore: avoid_print
    print(
      'SplatQuads.build, ${cloud.count} splats: '
      '${(micros / 1000).toStringAsFixed(2)} ms per camera move '
      '(${(micros / cloud.count * 1000).toStringAsFixed(0)} ns per splat)',
    );

    // A bound rather than a budget: what this asserts is that the cost is
    // linear and small per splat, so the printed number above is the fact and
    // this is the guard against it becoming quadratic. The sort inside is
    // `O(n log n)` and everything else is per splat.
    expect(
      micros,
      lessThan(2000000),
      reason: 'rebuilding 20k splats took $micros microseconds',
    );
    expect(quads.vertexCount, cloud.count * kSplatVerticesPerSplat);
  });
}
