/// `ux-49`'s own `PanoramaSync`, against a real device.
///
///     dart test test/panorama_sync_test.dart
///
/// In this package rather than in `flutter3d_model_core` for the reason
/// `render_project_test.dart` gives at length: uploading a cube needs a real
/// [GraphicsDevice], and that package may not depend on a backend.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

GraphicsDevice _device() => CpuDevice(
  width: 8,
  height: 8,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

Uint8List _hdr(int width, int height, int mantissa) => Uint8List.fromList(<int>[
  ...utf8.encode(
    '#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y $height +X $width\n',
  ),
  for (var i = 0; i < width * height; i++) ...<int>[
    mantissa,
    mantissa,
    mantissa,
    136,
  ],
]);

ModelProject _lit(Uint8List bytes) {
  final ModelProject project = const ModelProject().copyWith(
    images: <EncodedImage>[
      EncodedImage(
        bytes: bytes,
        name: 'sky.hdr',
        mimeType: 'image/vnd.radiance',
      ),
    ],
  );
  final ModelHistory history = ModelHistory(project);
  expect(history.run(const SetPanorama(index: 0)), isNull);
  return history.project;
}

void main() {
  test('a panorama reaches the scene as an environment cube', () {
    final Scene scene = Scene();
    PanoramaSync().sync(_device(), scene, _lit(_hdr(8, 4, 200)));

    expect(scene.environment, isNotNull);
    expect(scene.environmentLevels, kPanoramaCubeLevels);
  });

  test('and a project with none leaves the scene alone', () {
    final Scene scene = Scene();
    final sync = PanoramaSync()..sync(_device(), scene, const ModelProject());

    expect(scene.environment, isNull);
    // Mutation: clear the scene's own environment on every sync regardless.
    // A project with no panorama would then wipe an environment something
    // else had put there, and report having done work.
    expect(sync.rebuiltLast, isFalse);
  });

  group('what it refuses to do twice', () {
    test('the same project twice rebuilds the cube once', () {
      final Scene scene = Scene();
      final GraphicsDevice device = _device();
      final ModelProject project = _lit(_hdr(8, 4, 200));
      final sync = PanoramaSync()..sync(device, scene, project);
      expect(sync.rebuiltLast, isTrue);

      sync.sync(device, scene, project);

      // **Convolving six faces by roughness is not a per-frame cost.**
      // Mutation: rebuild every time, which is the obvious way to write
      // this — a viewport that redraws sixty times a second then spends
      // every one of them on a sky nobody moved.
      expect(sync.rebuiltLast, isFalse);
    });

    test('and a different picture at the same index does rebuild', () {
      final Scene scene = Scene();
      final GraphicsDevice device = _device();
      final sync = PanoramaSync()..sync(device, scene, _lit(_hdr(8, 4, 200)));

      // A panorama replaced through "Replace…" lands at a new index in
      // practice; a re-linked one at the same index with different bytes is
      // the case a bare index comparison would miss.
      sync.sync(device, scene, _lit(_hdr(16, 8, 200)));

      expect(sync.rebuiltLast, isTrue);
    });

    test('and clearing it takes the cube off', () {
      final Scene scene = Scene();
      final GraphicsDevice device = _device();
      final sync = PanoramaSync()..sync(device, scene, _lit(_hdr(8, 4, 200)));
      expect(scene.environment, isNotNull);

      sync.sync(device, scene, const ModelProject());

      expect(scene.environment, isNull);
      expect(scene.environmentLevels, 0);
      expect(sync.rebuiltLast, isTrue);
    });
  });
}
