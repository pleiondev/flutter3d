/// Draws a parity fixture and writes it to a PNG, so a person can look at it.
///
///     flutter test tool/dump_fixture.dart
///
/// The grid in `test/engine_parity_test.dart` is what the machine checks and it
/// is deliberately coarse — sixteen cells across, averaged. It answers "is this
/// the same picture" and cannot answer "what does it look like". This does, and
/// the two questions have needed separating before in this project: a frame
/// that was upside down agreed with three pixel assertions and needed a person
/// to notice.
///
/// A test file rather than a script because the package depends on the Flutter
/// SDK, so `dart run` cannot resolve it. Nothing here asserts anything.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';

/// Bigger than the comparison runs at. The fixture's own size is chosen to keep
/// a golden cheap; this is chosen to be looked at.
const int _width = 512;
const int _height = 384;

void main() {
  test('draw the fixtures', () async {
    final out = Directory('build/fixtures')..createSync(recursive: true);

    // Only the ones this backend can honestly draw. The others need a shadow
    // pass or a bloom chain, and the stages for those refuse rather than
    // returning something — which is the point, so asking for them here would
    // be asking for a crash.
    const drawable = <ParityScene>[ParityScene.plain];

    for (final which in drawable) {
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

      final built = buildParityScene(device, which: which);
      final started = DateTime.now();
      final result = renderer.render(
        width: _width,
        height: _height,
        scene: built.scene,
        views: <RenderView>[RenderView(camera: built.camera)],
        settings: paritySettingsFor(which),
      );
      final elapsed = DateTime.now().difference(started);

      final pixels = await device.readPixels(result.frame);
      final file = File('${out.path}/${which.name}.png');
      file.writeAsBytesSync(
          encodePng(pixels!.buffer.asUint8List(), _width, _height));

      // The time, because it is the one number that separates this backend from
      // the others by orders of magnitude and nothing else here would say so.
      // ignore: avoid_print
      print('${which.name}: ${result.drawCalls} draws, '
          '${elapsed.inMilliseconds} ms at ${_width}x$_height '
          '-> ${file.path}');
    }
  });
}
