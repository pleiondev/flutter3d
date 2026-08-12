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

import 'dart:convert';
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
          _png(pixels!.buffer.asUint8List(), _width, _height));

      // The time, because it is the one number that separates this backend from
      // the others by orders of magnitude and nothing else here would say so.
      // ignore: avoid_print
      print('${which.name}: ${result.drawCalls} draws, '
          '${elapsed.inMilliseconds} ms at ${_width}x$_height '
          '-> ${file.path}');
    }
  });
}

/// The smallest PNG that is a real PNG: 8-bit RGBA, one IDAT, zlib from
/// `dart:io`. Written out rather than taking a dependency, because a package
/// whose test tooling pulls in an image library for one call is a package with
/// a heavier dependency graph than its actual job.
Uint8List _png(Uint8List rgba, int width, int height) {
  // Filter byte 0 (none) in front of each row, which is what the format wants
  // and what makes this short.
  final raw = Uint8List(height * (width * 4 + 1));
  for (var y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0;
    raw.setRange(y * (width * 4 + 1) + 1, y * (width * 4 + 1) + 1 + width * 4,
        rgba, y * width * 4);
  }

  final out = BytesBuilder();
  out.add(<int>[137, 80, 78, 71, 13, 10, 26, 10]);

  void chunk(String type, List<int> data) {
    final body = <int>[...ascii.encode(type), ...data];
    out.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
    out.add(body);
    out.add((ByteData(4)..setUint32(0, _crc32(body))).buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6); // colour type: RGBA
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().convert(raw));
  chunk('IEND', const <int>[]);
  return out.toBytes();
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final byte in bytes) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
