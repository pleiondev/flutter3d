/// A bright thing above the middle does not light the bottom of the frame.
///
///     flutter test --platform chrome test/bloom_orientation_test.dart
///
/// **The weakest thing that would have caught it, and thirty-two goldens did
/// not.** A full-screen pass pairs clip positions with texture coordinates
/// directly — there is no projection in one to put a backend's convention right
/// — so on a backend whose row zero is at the bottom, every full-screen pass
/// turns its input over. One pass that reads the frame and writes the frame
/// survives that, because the flip going in cancels the flip coming out. The
/// bloom chain is a threshold, a ladder down and a ladder back: an odd number of
/// passes however many levels it is given, and the glow came back mirrored about
/// the middle of the frame.
///
/// Every scene in the golden set has its subject in the middle, which is where a
/// mirrored glow lands almost on top of the real one. `bloom-sphere` recorded a
/// halo that was merely too weak and too narrow, and read as a filter that
/// differed rather than as a picture that was upside down; every synthetic probe
/// written to chase it — level counts, thresholds, filter radii, exposures,
/// textures, frame counts — agreed to the last digit, because each of them was
/// symmetric too. Moving the sphere off centre answered it in one frame.
///
/// So this test does the one thing the golden set structurally cannot: it puts
/// the subject somewhere other than the middle. Written by breaking what it
/// covers, as everything here is: with `_fullscreenTriangle` pinned back to the
/// pairing it had, the band below the middle goes from 22 of 255 to 252.
///
/// It asserts nothing about what bloom looks like — that is the golden set's
/// question, and it needs a recorded picture to answer. It asks only which half
/// of the frame the glow is in.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 480;
const int _height = 360;

/// How far above the middle the sphere sits, in world units.
const double _lift = 0.9;

void main() {
  test('the glow is on the same side of the frame as what is glowing', () async {
    final device = WebGlDevice.create(
      width: _width,
      height: _height,
      sources: engineShaders,
    );
    if (device == null) fail('no WebGL2 context in this browser');

    TextureHandle texel(List<int> rgba) => device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
    )!;

    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
      fallbackNormal: texel(<int>[128, 128, 255, 255]),
    );

    final scene = Scene(name: 'one bright ball, high up');
    scene.root.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          const SphereShape(radius: 0.6, segments: 32, rings: 16).build(),
        ),
        // Unlit and far above display white, so what reaches the bloom
        // threshold is the sphere and nothing else in the frame — no light rig
        // to place, no specular to depend on.
        Material(
          name: 'ball',
          baseColor: Vector4(4.0, 4.0, 4.0, 1.0),
          lighting: LightingModel.unlit,
        ),
        name: 'ball',
      )..setPosition(0.0, _lift, 0.0),
    );
    final camera = CameraNode(name: 'eye')..setPosition(0.0, 0.0, 3.2);
    camera.lookAt(Vector3.zero());
    scene.root.add(camera);

    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[
        // Black, so "glowing" and "not glowing" cannot be confused by a
        // background that is already lit.
        RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
      ],
      settings: const RenderSettings(
        // Low, so the sphere is nowhere near clipping and the glow around it
        // has somewhere to show.
        exposure: 0.12,
        shadows: ShadowSettings(enabled: false),
        // Threshold at zero and the intensity up: the point is to put as much
        // light into the chain as it will carry, not to reproduce a look.
        bloom: BloomSettings(threshold: 0.0, intensity: 1.0),
      ),
    );

    final pixels = await device.readPixels(result.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');
    final bytes = pixels!.buffer.asUint8List();

    double brightest(int fromRow, int toRow) {
      var most = 0.0;
      for (var y = fromRow; y < toRow; y++) {
        for (var x = 0; x < _width; x++) {
          final at = (y * _width + x) * 4;
          final lum = (bytes[at] + bytes[at + 1] + bytes[at + 2]) / 3.0;
          if (lum > most) most = lum;
        }
      }
      return most;
    }

    // A band well clear of the middle on each side, so neither the sphere's own
    // edge nor the glow immediately around it lands in the wrong one.
    const margin = 40;
    final above = brightest(0, _height ~/ 2 - margin);
    final below = brightest(_height ~/ 2 + margin, _height);

    // ignore: avoid_print
    print(
      'brightest above the middle: ${above.toStringAsFixed(1)}, '
      'below: ${below.toStringAsFixed(1)}',
    );

    // The sphere is up there, and it is lit. Without this the test would also
    // pass on a frame with nothing in it at all.
    expect(
      above,
      greaterThan(64.0),
      reason:
          'the sphere did not draw, so the half below it being dark says '
          'nothing',
    );

    // And barely anything is down here. Not nothing: the chain's coarsest level
    // is a handful of texels across the whole frame, so a real glow does reach
    // this far, and it measured 22 of 255. A mirrored one puts the sphere's
    // entire brightness in this band — 252 of 255, the sphere itself, upside
    // down — so the two are an order of magnitude apart and the line between
    // them does not need to be a fine one.
    expect(
      below,
      lessThan(64.0),
      reason:
          'the bottom of the frame is lit by a sphere in the top of it: '
          'the bloom chain is composited upside down. See '
          '`Renderer._fullscreenTriangle`',
    );
  });
}
