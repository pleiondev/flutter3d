/// A moved mesh reaches the velocity buffer on this backend.
///
///     flutter test --platform chrome test/velocity_lookup_test.dart
///
/// The object velocity pass has no depth attachment. Its fragment stage looks
/// up the surface buffer's depth at the fragment's own pixel and drops a
/// fragment behind what the scene drew there, and it used to find that pixel
/// by counting rows from the top. On this backend row zero is the bottom of
/// the picture, in the surface buffer as much as in the pass, so the lookup
/// read the row mirrored about the middle: a mesh in the upper half compared
/// itself against whatever the lower half held, and against the sky every
/// fragment was dropped. `velocity-shapes` came back nearly black and the wheel
/// in `motion-blur-spin` unblurred, with nothing in the console.
///
/// So the box here sits in the upper half, over nothing but sky below the
/// middle: with the rows counted the wrong way its velocity is exactly zero.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

const int _width = 128;
const int _height = 96;

void main() {
  test('a box sliding in the upper half shows in the velocity view', () async {
    final device = WebGlDevice.create(
      width: _width,
      height: _height,
      sources: engineShaders,
    );
    if (device == null) fail('no WebGL2 context in this browser');

    TextureHandle texel(List<int> rgba) {
      final made = device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
      );
      if (made == null) fail('the device would not make a 1x1 texture');
      return made;
    }

    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
      fallbackNormal: texel(<int>[128, 128, 255, 255]),
    );

    final box = MeshNode(
      DeviceMesh.upload(device, CuboidShape().build()),
      Material(baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
      name: 'box',
    );
    final camera = CameraNode(
      projection: const PerspectiveProjection(fovYRadians: 1.0),
    )..setPosition(0.0, 0.0, 6.0);
    final scene = Scene()
      ..add(box)
      ..add(camera);

    // Rightwards a metre a frame: in this frame about a tenth of its width,
    // which the view shows as red well clear of rounding.
    late Uint8List pixels;
    for (var frame = 0; frame < 4; frame++) {
      box.setPosition(-1.5 + frame.toDouble(), 1.4, 0.0);
      final result = renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: <RenderView>[
          RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
        ],
        settings: const RenderSettings(
          bloom: BloomSettings(enabled: false),
          antiAlias: AntiAliasSettings(
            temporal: TemporalSettings(enabled: true),
          ),
          showVelocity: true,
        ),
      );
      final read = await device.readPixels(result.frame);
      pixels = read!.buffer.asUint8List();
    }

    final moving = <int>[
      for (var at = 0; at < pixels.length; at += 4)
        if (pixels[at] > 16) at ~/ 4,
    ];
    expect(
      moving.length,
      greaterThan(_width * _height ~/ 100),
      reason:
          'the box covers several percent of the frame and moves a tenth of '
          'it a frame, yet only ${moving.length} pixels carry any rightward '
          'velocity: the velocity pass dropped its fragments against the '
          'surface buffer',
    );

    device.dispose();
  });
}
