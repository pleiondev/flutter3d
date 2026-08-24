/// Every lighting model draws something on this backend.
///
///     flutter test --platform chrome test/lighting_models_test.dart
///
/// **The weakest possible assertion, and it caught a model drawing nothing.**
/// `lighting-unlit` came back as an empty frame — the background colour in every
/// pixel — while the other five drew a sphere. The golden set found it, once
/// there was a golden set; this says the same thing in one second instead of a
/// browser run over thirty-two scenes, and says it per model rather than per
/// picture.
///
/// It deliberately does not compare against a reference. What a shader *should*
/// draw is the golden set's question, and it needs a recorded picture to answer;
/// whether a pipeline the engine builds produces any pixels at all is this one's,
/// and it needs nothing. A shader that links, binds and draws an empty frame
/// passes every check this package had before.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 128;
const int _height = 96;

/// A lit sphere filling most of the view, and a light to see it by.
({Scene scene, CameraNode camera}) _sphere(
    GraphicsDevice device, LightingModel model) {
  final scene = Scene(name: 'one sphere');
  scene.root.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        const SphereShape(radius: 1.0, segments: 32, rings: 16).build(),
      ),
      Material(
        name: 'ball',
        baseColor: Vector4(0.85, 0.55, 0.25, 1.0),
        lighting: model,
        // Emissive as well as lit, so a model that ignores lights entirely —
        // which is what Unlit is — still has something to show.
        emissive: Vector3(0.2, 0.13, 0.06),
      ),
      name: 'ball',
    ),
  );
  scene.root.add(
    LightNode(name: 'key', type: LightType.directional)
      ..intensity = 3.5
      ..setPosition(1.5, 3.0, 2.0)
      ..lookAt(Vector3.zero()),
  );
  final camera = CameraNode(name: 'eye')..setPosition(0.0, 0.0, 3.2);
  camera.lookAt(Vector3.zero());
  scene.root.add(camera);
  return (scene: scene, camera: camera);
}

void main() {
  for (final model in LightingModel.builtIn) {
    test('${model.shaderName} draws something', () async {
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

      final built = _sphere(device, model);
      final result = renderer.render(
        width: _width,
        height: _height,
        scene: built.scene,
        views: <RenderView>[
          RenderView(
            camera: built.camera,
            // Black, so "drew nothing" and "drew something" cannot be confused
            // by a background that is already bright.
            clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
          ),
        ],
        settings: const RenderSettings(
          bloom: BloomSettings(enabled: false),
          shadows: ShadowSettings(enabled: false),
        ),
      );

      final pixels = await device.readPixels(result.frame);
      expect(pixels, isNotNull, reason: 'the frame could not be read back');
      final bytes = pixels!.buffer.asUint8List();

      var lit = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i] > 8 || bytes[i + 1] > 8 || bytes[i + 2] > 8) lit++;
      }
      final share = 100.0 * lit / (_width * _height);
      // ignore: avoid_print
      print('${model.shaderName}: ${share.toStringAsFixed(1)}% of the frame '
          'is not the clear colour, ${result.drawCalls} draws');

      // A sphere of this radius at this distance covers roughly a fifth of the
      // frame. Ten percent is well under that and well over nothing, so this
      // fails on an empty frame and not on a shading difference.
      expect(share, greaterThan(10.0),
          reason: '${model.shaderName} drew an empty frame: the pipeline links '
              'and the draw is issued, and no pixel changed');
    });
  }
}
