/// A panorama file becomes a cube without holding up the isolate that asked.
///
///     dart test test/engine/environment_off_isolate_test.dart
///
/// **Asked of the event loop, not of a clock.** `EnvironmentMap.fromEncoded`
/// decoded a Radiance file, cut its faces and convolved them in the calling
/// turn: its future was complete before any timer queued ahead of it could
/// fire. Done on an isolate of its own, the caller's event loop turns while
/// the work runs, so a timer queued before the call fires before the cube
/// arrives. A clock would say the same thing more slowly and less reliably.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

/// A Radiance file of [width] by [height], every pixel a mid grey.
Uint8List _hdr(int width, int height) => Uint8List.fromList(<int>[
  ...utf8.encode(
    '#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y $height +X $width\n',
  ),
  for (var i = 0; i < width * height; i++) ...<int>[128, 128, 128, 128],
]);

void main() {
  group('a panorama from a file', () {
    test('is decoded and convolved off the calling isolate', () async {
      // Mutation: decode the `.hdr` and convolve its faces in the calling
      // turn, as before 1.0 — the cube arrives before the timer fires.
      var turned = false;
      Timer.run(() => turned = true);
      final cube = await EnvironmentMap.fromEncoded(
        FakeBackend(),
        _hdr(16, 8),
        decodeImage: (Uint8List bytes) async => null,
        size: 8,
        levels: 3,
      );
      expect(turned, isTrue);
      expect(cube.levels, 3);
    });

    test(
      'an image the decoder read is convolved off the isolate too',
      () async {
        // Mutation: convolve the decoded pixels in place — the decoder's own
        // future settles in a microtask, so only the convolution can let the
        // timer through.
        var turned = false;
        final cube = await EnvironmentMap.fromEncoded(
          FakeBackend(),
          Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47]),
          decodeImage: (Uint8List bytes) {
            Timer.run(() => turned = true);
            return Future<Rgba8Image?>.value(
              Rgba8Image(width: 4, height: 2, pixels: Uint8List(32)),
            );
          },
          size: 4,
          levels: 2,
        );
        expect(turned, isTrue);
        expect(cube.levels, 2);
      },
    );

    test('bytes neither reader takes are still a PanoramaFormatException', () {
      expect(
        EnvironmentMap.fromEncoded(
          FakeBackend(),
          Uint8List.fromList(<int>[1, 2, 3]),
          decodeImage: (Uint8List bytes) async => null,
        ),
        throwsA(isA<PanoramaFormatException>()),
      );
    });
  });
}
