/// Draws the demo scene headlessly and writes it to a PNG.
///
///     flutter test tool/dump_cpu_shapes.dart
///
/// The same scene `cpu_main.dart` shows, through the same backend, without
/// opening a window. Worth having separately from the app: looking at what a
/// renderer drew should not require a display, a running application, or
/// anything to be in front of anything else.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_example/cpu_shapes_scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// From the environment rather than a --dart-define: a define is folded at
/// compile time and `flutter test` does not pass one through to the test's own
/// compilation, which is a thing worth finding out once.
final int _width = int.parse(Platform.environment['CPU_W'] ?? '512');
final int _height = int.parse(Platform.environment['CPU_H'] ?? '384');

void main() {
  test('draw the shapes', () async {
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
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

    final built = buildShapesScene(device);
    final started = DateTime.now();
    final result = renderer.render(
      width: _width,
      height: _height,
      scene: built.scene,
      views: <RenderView>[RenderView(camera: built.camera)],
      settings: const RenderSettings(
        bloom: BloomSettings(enabled: false),
        shadows: ShadowSettings(enabled: false),
      ),
    );
    final ms = DateTime.now().difference(started).inMilliseconds;

    final pixels = await device.readPixels(result.frame);
    final out = Directory('build/cpu')..createSync(recursive: true);
    final file = File('${out.path}/shapes.png')
      ..writeAsBytesSync(
          encodePng(pixels!.buffer.asUint8List(), _width, _height));

    // ignore: avoid_print
    print('shapes: ${result.drawCalls} draws, $ms ms at ${_width}x$_height '
        '-> ${file.path}');
  });
}
