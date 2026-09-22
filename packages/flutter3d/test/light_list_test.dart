/// `gfx-74n`: more than eight lights reach one draw.
///
///     flutter test test/light_list_test.dart
///
/// **What the cap actually was.** Eight is the cap on one *draw*, not on a
/// scene: `gfx-12n` already picks the eight lights that reach each object, so a
/// night map may carry two hundred torches with every object lit by its own
/// eight. What it could not do is light one object with more than eight, and
/// where that shows is a surface large enough to touch many at once — a ground
/// plane whose bounding sphere reaches every torch scores them all at distance
/// zero and keeps the eight brightest.
///
/// **Why a texture and not a wider block.** The four `vec4` arrays in
/// `FragInfo` are uploaded on every draw, so widening them to thirty-two lights
/// would be a two-kilobyte upload per draw in every scene, including every
/// scene with one light. The light data is the same for every draw in the
/// frame; only which of them reach it differs, and that is six `vec4`s of row
/// numbers and six of fade scales.
///
/// The third test is the half that lets this land, and it is the same shape
/// `gfx-60n`'s was: a scene inside eight takes the path it always took, so the
/// forty-four recorded frames cannot move — by construction rather than by
/// comparison afterwards.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 48;

/// A white floor under [lamps] lights in a ring above it.
///
/// One mesh, so every lamp competes for the same draw's slots — which is the
/// case the row is about. The ring is tight enough that all of them reach the
/// floor and wide enough that the eight the selection keeps are not the only
/// ones contributing anything.
Future<({List<int> pixels, FrameResult frame})> _draw({
  required int lamps,
  bool tinted = true,
}) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);

  final scene = Scene()
    ..ambientIntensity = 0.0
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(8, 0.2, 8)).build(),
        ),
        Material(
          name: 'floor',
          baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
          lighting: LightingModel.lambert,
        ),
      )..setPosition(0.0, -1.0, 0.0),
    );

  for (var i = 0; i < lamps; i++) {
    final angle = i * 2.0 * math.pi / lamps;
    scene.add(
      LightNode(
        type: LightType.point,
        intensity: 6.0,
        range: 12.0,
        // Every lamp a different hue, so a frame that lost some of them is a
        // frame of a different colour rather than one of a different
        // brightness — which a tone map could have hidden.
        color: tinted
            ? Vector3(
                0.5 + 0.5 * math.cos(angle),
                0.5 + 0.5 * math.cos(angle + 2.1),
                0.5 + 0.5 * math.cos(angle + 4.2),
              )
            : Vector3(1.0, 1.0, 1.0),
      )..setPosition(math.cos(angle) * 2.5, 1.2, math.sin(angle) * 2.5),
    );
  }

  scene.add(
    CameraNode()
      ..setPosition(0.0, 5.0, 0.01)
      ..lookAt(Vector3.zero()),
  );

  final frame = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: const RenderSettings(),
  );
  final bytes = await device.readPixels(frame.frame);
  return (
    pixels: <int>[
      for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
    ],
    frame: frame,
  );
}

/// The summed brightness of the frame, as a stand-in for how much light
/// reached it.
int _brightness(List<int> pixels) {
  var total = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    total += pixels[i] + pixels[i + 1] + pixels[i + 2];
  }
  return total;
}

/// How many pixels differ in any colour channel.
int _differing(List<int> a, List<int> b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) count++;
  }
  return count;
}

void main() {
  test('a ninth light reaches a draw the eighth already filled', () async {
    // **The row's own acceptance.** Eight lamps and sixteen, on one floor. The
    // ring is the same shape either way, so the extra eight can only add what
    // they add: a frame that stopped at eight is dimmer than one that did not.
    final eight = await _draw(lamps: 8);
    final sixteen = await _draw(lamps: 16);

    expect(
      _brightness(sixteen.pixels),
      greaterThan(_brightness(eight.pixels)),
      reason: 'the lamps past the eighth reached nothing',
    );
    expect(sixteen.frame.lightsDropped, 0);
  });

  test('and the ones past the list are still turned away', () async {
    // The tail is bounded, and the bound is a promise rather than a surprise:
    // `LightBuffer.maxExtraLights` and `kExtraLights` in `lib/surface.glsl` are
    // one number written twice, and a scene past it reports what it dropped
    // instead of quietly drawing the difference.
    final many = await _draw(lamps: 48);

    expect(
      many.frame.lightsDropped,
      greaterThan(0),
      reason:
          'forty-eight lamps on one draw fit, so the bound is not the '
          'bound this test names',
    );
  });

  test('a scene inside eight takes the path it always took', () async {
    // **The half that lets this land**, and the reason the forty-four recorded
    // frames did not move: a draw with eight lights or fewer never samples the
    // texture, because the loop stops before the ninth index.
    final first = await _draw(lamps: 6);
    final second = await _draw(lamps: 6);

    expect(second.pixels, first.pixels);
    expect(second.frame.lightsDropped, 0);
  });

  test('the tail is the lights the slots turned away, not a repeat', () async {
    // A list that handed back the same eight would brighten the frame too, and
    // pass the first test. Colouring every lamp differently is what separates
    // them: sixteen hues over the floor is a different *picture* from eight,
    // not a brighter one.
    final tinted = await _draw(lamps: 16);
    final white = await _draw(lamps: 16, tinted: false);

    expect(
      _differing(tinted.pixels, white.pixels),
      greaterThan(100),
      reason: 'the hues did not reach the picture',
    );
  });
}
