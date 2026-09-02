/// `uploadEncodedImage` routes KTX2 to `Ktx2Texture` before `dart:ui` ever
/// sees the bytes — this proves the routing itself, not the transcoder
/// (`ktx2_etc1s_test.dart` already proves that against a real encoder's
/// output pixel for pixel).
///
/// Runs off-device: [FakeBackend] records rather than draws, and the KTX2
/// path never reaches `ui.instantiateImageCodec`, so nothing here needs a
/// live Flutter binding.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/texture_upload.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _readSample(String name) =>
    File('$kSamplesPath/$name').readAsBytesSync();

void main() {
  test('a Basis Universal KTX2 file uploads as plain RGBA8', () async {
    final device = FakeBackend();
    final bytes = _readSample('ktx2/etc1s_gradient_quadrants.ktx2');

    final handle = await uploadEncodedImage(device, bytes);

    expect(handle, isNotNull);
    expect(device.uploadedTextures, hasLength(1));
    final spec = device.uploadedTextures.single;
    expect(spec.width, 8);
    expect(spec.height, 8);
    expect(spec.format, TextureFormat.r8g8b8a8UNormInt);

    // The same ground truth `ktx2_etc1s_test.dart` checks the transcoder
    // against directly — this test is about the wiring, not the codec, so one
    // corner pixel of each quadrant is enough to know the right bytes made it
    // through `uploadEncodedImage` rather than, say, the source PNG bytes
    // misread as an image of the wrong format.
    final pixels = device.uploadedPixels.single;
    int at(int x, int y) => pixels.getUint32((y * 8 + x) * 4, Endian.little);
    int rgba(int r, int g, int b) => r | (g << 8) | (b << 16) | (0xFF << 24);
    expect(at(0, 0), rgba(253, 0, 0));
    expect(at(7, 0), rgba(6, 253, 0));
    expect(at(0, 7), rgba(0, 6, 253));
    expect(at(7, 7), rgba(255, 255, 2));
  });

  test('empty bytes upload nothing', () async {
    final device = FakeBackend();
    expect(await uploadEncodedImage(device, Uint8List(0)), isNull);
    expect(device.uploadedTextures, isEmpty);
  });

  test('a truncated KTX2 file degrades to no texture', () async {
    final device = FakeBackend();
    final bytes = _readSample('ktx2/etc1s_gradient_quadrants.ktx2');
    final truncated = Uint8List.sublistView(bytes, 0, 16);

    expect(await uploadEncodedImage(device, truncated), isNull);
    expect(device.uploadedTextures, isEmpty);
  });
}
