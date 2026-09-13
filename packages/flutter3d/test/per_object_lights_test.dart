/// Two ends of one room, lit by different lamps, in pixels.
///
///     flutter test test/per_object_lights_test.dart
///
/// The fragment shaders read eight light slots and that number is compiled into
/// the bundle, so for as long as one packing served a whole frame the eight were
/// a limit on the *scene*: the ninth lamp of a night map did nothing, anywhere.
/// The packing is now made per draw, out of the same four arrays, and no shader
/// changed — which is a claim about a picture, and the software rasteriser is
/// the one backend that can produce a picture here without a window or a
/// browser.
///
/// The room is arranged so the two answers cannot be confused. Eight blue lamps
/// stand at one end and are written down first, so a frame-wide packing spends
/// every slot on them; one red lamp stands at the other end and is written down
/// ninth. Neither set's range reaches the far end. Ambient is off and the view
/// clears to black, so every photon in the frame came from a lamp: a ball handed
/// the wrong list is not merely the wrong colour, it is not there.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 128;
const int _height = 48;

/// Where each ball stands, and how far a lamp reaches.
const double _apart = 8.0;
const double _reach = 6.0;

({Scene scene, CameraNode camera}) _room() {
  // Every photon from a lamp: with ambient on, a ball handed no lights at all
  // still comes back grey, and grey is exactly the reading this has to be able
  // to tell from blue.
  final scene = Scene(name: 'two ends')..ambientIntensity = 0.0;
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final ball = DeviceMesh.upload(device, SphereShape(radius: 1.5).build());

  for (final at in <double>[-_apart, _apart]) {
    scene.add(
      MeshNode(
        ball,
        Material(
          name: 'ball',
          baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
          lighting: LightingModel.lambert,
        ),
        name: 'ball',
      )..setPosition(at, 0.0, 0.0),
    );
  }

  // Written first, and there are exactly enough of them to fill every slot.
  // In front of the ball rather than beside it — a lamp standing inside the
  // bounding sphere lights the far side of a surface the camera cannot see.
  for (var i = 0; i < 8; i++) {
    scene.add(
      LightNode(
        type: LightType.point,
        color: Vector3(0.1, 0.2, 1.0),
        intensity: 4.0,
        range: _reach,
        name: 'blue$i',
      )..setPosition(-_apart + (i - 4) * 0.05, 0.0, -3.5),
    );
  }
  // The ninth.
  scene.add(
    LightNode(
      type: LightType.point,
      color: Vector3(1.0, 0.15, 0.05),
      intensity: 4.0,
      range: _reach,
      name: 'red',
    )..setPosition(_apart, 0.0, -3.5),
  );

  final camera = CameraNode(name: 'eye')
    ..setPosition(0.0, 0.0, -16.0)
    ..lookAt(Vector3.zero());
  return (scene: scene, camera: camera);
}

/// Average colour of the lit pixels in one half of the frame.
///
/// Lit rather than all: the view clears to black and half a frame is mostly
/// background, so averaging it in would drag both halves toward each other,
/// which is the one thing this must not do. [litPixels] comes back with it,
/// because "no lit pixels at all" is the reading that matters most.
({Vector3 colour, int litPixels}) _half(Uint8List rgba, {required bool left}) {
  var r = 0.0, g = 0.0, b = 0.0;
  var n = 0;
  for (var y = 0; y < _height; y++) {
    final from = left ? 0 : _width ~/ 2;
    final to = left ? _width ~/ 2 : _width;
    for (var x = from; x < to; x++) {
      final i = (y * _width + x) * 4;
      if (rgba[i] + rgba[i + 1] + rgba[i + 2] < 24) continue;
      r += rgba[i];
      g += rgba[i + 1];
      b += rgba[i + 2];
      n++;
    }
  }
  if (n == 0) return (colour: Vector3.zero(), litPixels: 0);
  return (
    colour: Vector3(r / n / 255.0, g / n / 255.0, b / n / 255.0),
    litPixels: n,
  );
}

void main() {
  test('the ninth lamp lights the ball it stands beside', () async {
    // MUTATION: return the frame's own buffer unconditionally from
    // `Renderer._drawLightsFor`. Both balls are then handed the eight blue
    // lamps, the far one is outside every one of their ranges, and its half of
    // the frame comes back with no lit pixels at all — which is exactly what
    // the ninth lamp of a night map used to do.
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    );
    final room = _room();
    final frame = renderer.render(
      width: _width,
      height: _height,
      scene: room.scene,
      views: <RenderView>[
        RenderView(
          camera: room.camera,
          clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
        ),
      ],
      settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
    );
    final pixels = await it.device.readPixels(frame.frame);
    expect(pixels, isNotNull);
    final rgba = pixels!.buffer.asUint8List();

    final left = _half(rgba, left: true);
    final right = _half(rgba, left: false);
    expect(left.litPixels, greaterThan(20), reason: 'one end is dark');
    expect(right.litPixels, greaterThan(20), reason: 'the other end is dark');

    // One end blue, the other red, and neither in doubt. Which half of the
    // frame holds which ball depends on the projection's handedness, so this
    // asks only that the two ends disagree and that each reads as the colour of
    // exactly one lamp set.
    final blue = left.colour.z > left.colour.x ? left.colour : right.colour;
    final red = identical(blue, left.colour) ? right.colour : left.colour;

    // A difference between channels rather than a ratio between them: the tone
    // curve and the sRGB encode both lift a dark channel hard, so a lamp of
    // (1.0, 0.15, 0.05) reads as (0.67, 0.25, 0.09) on the way out and a ratio
    // test would be a test of the transfer function. The recorded reading is
    // blue (0.54, 0.61, 0.92) at one end and red (0.67, 0.25, 0.09) at the
    // other; a quarter of the range is well inside both and well outside any
    // mixture of the two.
    expect(
      blue.z - blue.x,
      greaterThan(0.25),
      reason: 'the blue end is not lit blue',
    );
    expect(
      red.x - red.z,
      greaterThan(0.25),
      reason: 'the red end is not lit red',
    );

    // And the frame says which regime it is in: nine lamps, eight slots, so
    // one beyond what a single packing carries.
    expect(room.scene.lights, hasLength(9));
    expect(frame.lightsDropped, 1);
  });
}
