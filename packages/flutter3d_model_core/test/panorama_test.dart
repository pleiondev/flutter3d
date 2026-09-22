/// `ux-49`: a panorama beside the four presets, and the size it insists on.
///
///     flutter test test/panorama_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

/// A Radiance file of [width] × [height], one flat grey pixel each.
Uint8List _hdr(int width, int height) => Uint8List.fromList(<int>[
  ...utf8.encode(
    '#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y $height +X $width\n',
  ),
  for (var i = 0; i < width * height; i++) ...<int>[128, 128, 128, 136],
]);

ModelProject _withImage(Uint8List bytes) => const ModelProject().copyWith(
  images: <EncodedImage>[
    EncodedImage(bytes: bytes, name: 'sky.hdr', mimeType: 'image/vnd.radiance'),
  ],
);

void main() {
  test('a 2:1 panorama is accepted, and is what lights the scene', () {
    final ModelHistory history = ModelHistory(_withImage(_hdr(4, 2)));

    expect(history.run(const SetPanorama(index: 0)), isNull);
    expect(history.project.lighting.panorama, 0);
  });

  test('an image that is not 2:1 refuses, naming its size', () {
    final ModelHistory history = ModelHistory(_withImage(_hdr(4, 3)));

    // **The refusal is the feature.** The mapping from a pixel to a
    // direction assumes longitude across the full width and latitude down
    // the full height, so a 4:3 photograph comes out as a sky stretched
    // round the horizon with the poles pinched — and nothing in the picture
    // says why. Mutation: accept anything. The bug is then a look somebody
    // spends an afternoon trying to fix in the lighting.
    final String? refused = history.run(const SetPanorama(index: 0));
    expect(refused, contains('twice as wide'));
    expect(refused, contains('4 by 3'));
    expect(history.project.lighting.panorama, isNull);
  });

  test('an image that is not a Radiance file refuses too', () {
    final ModelHistory history = ModelHistory(
      _withImage(Uint8List.fromList(utf8.encode('\x89PNG\r\n\x1a\n\n'))),
    );

    expect(
      history.run(const SetPanorama(index: 0)),
      contains('not a Radiance'),
    );
  });

  test('an index nothing is at refuses rather than throwing', () {
    final ModelHistory history = ModelHistory(const ModelProject());
    expect(history.run(const SetPanorama(index: 3)), contains('no image 3'));
  });

  test('a null index clears it, and the presets take over again', () {
    final ModelHistory history = ModelHistory(_withImage(_hdr(4, 2)));
    expect(history.run(const SetPanorama(index: 0)), isNull);

    expect(history.run(const SetPanorama()), isNull);
    expect(history.project.lighting.panorama, isNull);
    // Mutation: clear the preset as well. A person who tried a panorama and
    // went back would find the sky they had before was gone too.
    expect(history.project.lighting.environment, SceneEnvironmentPreset.none);
  });

  test('and one undo puts the panorama back', () {
    final ModelHistory history = ModelHistory(_withImage(_hdr(4, 2)));
    expect(history.run(const SetPanorama(index: 0)), isNull);
    expect(history.run(const SetPanorama()), isNull);

    expect(history.undo(), isTrue);
    expect(history.project.lighting.panorama, 0);
  });
}
