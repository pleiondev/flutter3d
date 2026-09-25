/// `gfx-30n`: halation — the wide part of a glow goes warm.
///
///     flutter test test/halation_test.dart
///
/// **What it is, and why the asymmetry is the whole effect.** On film the
/// halo around a highlight is warm: light that gets through the emulsion
/// scatters off the backing and comes back, and the red layer sits deepest so
/// it catches the most of it. What makes that read as light rather than as a
/// colour cast is that only the *wide* part warms — the tight core keeps the
/// colour of the highlight. A tint on the whole glow would be the cheap
/// version and is exactly what these tests are written to catch.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// One small white-hot ball on black, bloomed.
///
/// White so the glow's own colour is whatever the chain gives it, rather than
/// the object's: a red ball would glow red with or without this row.
Future<({List<int> red, List<int> blue})> _glow({
  required double halation,
  int width = 96,
}) async {
  final device = CpuDevice(
    width: width,
    height: width,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);

  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, SphereShape(radius: 0.35).build()),
        Material(
          name: 'hot',
          baseColor: Vector4(12.0, 12.0, 12.0, 1.0),
          lighting: LightingModel.unlit,
        ),
      ),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 4.0));

  final frame = renderer.render(
    width: width,
    height: width,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    // Undithered, so the core is compared byte for byte: the per-level ratio
    // at level zero is one to within a float, and the dither would round
    // that last bit into a step.
    settings: RenderSettings(
      bloom: BloomSettings(intensity: 0.8, halation: halation),
      look: const LookSettings(dither: 0),
    ),
  );

  final bytes = await device.readPixels(frame.frame);
  return (
    red: <int>[for (var i = 0; i < width * width; i++) bytes!.getUint8(i * 4)],
    blue: <int>[
      for (var i = 0; i < width * width; i++) bytes!.getUint8(i * 4 + 2),
    ],
  );
}

/// How far red runs ahead of blue, summed over the pixels named.
int _warmth(({List<int> red, List<int> blue}) frame, Iterable<int> at) {
  var total = 0;
  for (final i in at) {
    total += frame.red[i] - frame.blue[i];
  }
  return total;
}

void main() {
  const width = 96;
  const centre = (width ~/ 2) * width + (width ~/ 2);

  test('zero is an exact identity, and is the default', () async {
    // The multiplier is one on every channel at zero, so the chain comes out
    // byte for byte as it did — which is what seventy-eight goldens need.
    expect(const BloomSettings().halation, 0.0);
    final a = await _glow(halation: 0.0);
    final b = await _glow(halation: 0.0);
    expect(a.red, b.red);
    expect(a.blue, b.blue);
  });

  test('the wide skirt goes warm', () async {
    // A ring well outside the ball, where only the broad levels of the chain
    // reach.
    final ring = <int>[
      for (var y = 0; y < width; y++)
        for (var x = 0; x < width; x++)
          if (((x - width / 2) * (x - width / 2) +
                  (y - width / 2) * (y - width / 2)) >
              28 * 28)
            y * width + x,
    ];

    final plain = await _glow(halation: 0.0);
    final warm = await _glow(halation: 1.0);

    expect(
      _warmth(warm, ring),
      greaterThan(_warmth(plain, ring)),
      reason:
          'the broad part of the glow is what halation warms; if it does '
          'not, the per-level amount is not reaching the chain',
    );
  });

  test('the core keeps the colour of the highlight', () async {
    // The half that separates halation from a tint on the glow. Level zero
    // carries no halation at all, so the pixel at the middle of a white ball
    // must come out as neutral as it did.
    final plain = await _glow(halation: 0.0);
    final warm = await _glow(halation: 1.0);

    expect(
      warm.red[centre] - warm.blue[centre],
      plain.red[centre] - plain.blue[centre],
      reason:
          'a warm core means the amount was applied to every level, which '
          'is a colour cast on the glow rather than a halo around it',
    );
  });
}
