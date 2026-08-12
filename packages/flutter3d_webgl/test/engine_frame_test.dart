/// The engine's own renderer, drawing through this backend, checked by pixel.
///
///     flutter test --platform chrome test/engine_frame_test.dart
///
/// **Chrome only.** There is no WebGL on the Dart VM, so this file is skipped
/// there rather than failing — but a suite that only ever runs on the VM would
/// silently stop covering the one thing this package exists to do.
///
/// Everything here above `WebGlDevice.create` is the ordinary flutter3d frame.
/// That is the claim: a backend is a package, not an edit to the renderer.
///
/// Checked by reading pixels rather than by eye, because the failure that
/// matters looks like success from a distance. A frame that draws nothing comes
/// back the clear colour, uniformly, with no error raised anywhere — which is
/// exactly what a black rectangle in a browser window looks like, and exactly
/// what a screenshot would have to be squinted at to disprove.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

const int _width = 128;
const int _height = 128;

void main() {
  late WebGlDevice device;

  setUp(() {
    final made = WebGlDevice.create(
      width: _width,
      height: _height,
      sources: engineShaders,
    );
    if (made == null) fail('no WebGL2 context in this browser');
    device = made;
  });

  test('every shader the engine asks for is answered', () {
    // Renderer.create resolves each by name and throws naming the missing one.
    // Doing it here means a shader that fails to translate is a failed test
    // rather than a blank frame somewhere later.
    expect(() => _renderer(device), returnsNormally);
  });

  test('a lit sphere is drawn, and it is not the clear colour', () async {
    final renderer = _renderer(device);
    final scene = Scene();

    scene.root.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          const SphereShape(radius: 1.0, segments: 24, rings: 12).build(),
        ),
        Material(
          name: 'ball',
          baseColor: Vector4(0.9, 0.2, 0.1, 1.0),
          lighting: LightingModel.lambert,
        ),
        name: 'ball',
      ),
    );

    final light = LightNode(name: 'key', type: LightType.directional)
      ..intensity = 4.0
      ..setPosition(2.0, 3.0, 2.0)
      ..lookAt(Vector3.zero());
    scene.root.add(light);

    final camera = CameraNode(name: 'eye')
      ..setPosition(0.0, 0.0, 3.5)
      ..lookAt(Vector3.zero());
    scene.root.add(camera);

    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
    );
    expect(result.drawCalls, greaterThan(0));

    final pixels = await device.readPixels(result.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');

    final bytes = pixels!.buffer.asUint8List();
    expect(bytes.length, _width * _height * 4);

    // Three claims, and each one fails a different way of drawing nothing.
    //
    // Distinct colours: a frame that is one colour everywhere is the clear,
    // whatever that colour happens to be.
    final distinct = <int>{};
    for (var i = 0; i < bytes.length; i += 4) {
      distinct.add(bytes[i] << 16 | bytes[i + 1] << 8 | bytes[i + 2]);
    }
    expect(distinct.length, greaterThan(8),
        reason: 'the frame is flat — nothing was drawn into it');

    // The sphere is red and lit, so the middle is brighter in red than the
    // corner. This is what fails if the mesh draws in the wrong place, or the
    // light never reaches the shader, or the material bindings land in the
    // wrong slots and everything comes out grey.
    int redAt(int x, int y) => bytes[(y * _width + x) * 4];
    expect(redAt(_width ~/ 2, _height ~/ 2), greaterThan(redAt(2, 2) + 16),
        reason: 'the middle of the frame is no brighter than its corner');

    // And it is red rather than some other channel, which catches a component
    // order swapped between the engine and the backend — a mistake that leaves
    // every check above passing.
    final cx = (_height ~/ 2 * _width + _width ~/ 2) * 4;
    expect(bytes[cx], greaterThan(bytes[cx + 1]),
        reason: 'red should dominate green at the centre');
    expect(bytes[cx], greaterThan(bytes[cx + 2]),
        reason: 'red should dominate blue at the centre');
  });
}

Renderer _renderer(WebGlDevice device) {
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

  return Renderer.create(
    device: device,
    fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
    fallbackNormal: texel(<int>[128, 128, 255, 255]),
  );
}
