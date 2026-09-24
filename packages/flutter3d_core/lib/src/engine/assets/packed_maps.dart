/// The material layers' textures, packed into the maps the layered stage
/// samples — `M1`.
///
/// **Packed at load, because the stage has no sampler to spare.** glTF gives
/// a clear coat, its roughness, a transmission and a thickness a texture
/// each; the layered stage reads all four from one coat map, since WebGL2
/// promises a stage sixteen samplers and metal-rough already binds fourteen.
/// The images are decoded here, one channel of each is copied into its lane,
/// and the result is uploaded once per material.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart' hide Ktx2Texture;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'texture_upload.dart';

/// One lane of a packed map: which image, and which of its channels (0 red
/// to 3 alpha) goes there. Null leaves the lane white, which multiplies its
/// factor by one.
typedef PackedLane = ({Rgba8Image image, int channel})?;

/// [lanes] — red, green, blue, alpha — packed into one RGBA8 image, or null
/// when every lane is empty.
///
/// The size is the largest of the sources, and each is read at the nearest
/// texel to the same place: sources authored at different sizes line up in
/// texture space, which is what their shared coordinates promise.
Rgba8Image? packLanes(List<PackedLane> lanes) {
  final present = <({Rgba8Image image, int channel})>[
    for (final lane in lanes) ?lane,
  ];
  if (present.isEmpty) return null;
  final width = present
      .map((lane) => lane.image.width)
      .reduce((a, b) => a > b ? a : b);
  final height = present
      .map((lane) => lane.image.height)
      .reduce((a, b) => a > b ? a : b);
  final pixels = Uint8List(width * height * 4)
    ..fillRange(0, width * height * 4, 255);
  for (final (lane, source) in lanes.indexed) {
    if (source == null) continue;
    final image = source.image;
    for (var y = 0; y < height; y++) {
      final sy = (y * image.height) ~/ height;
      for (var x = 0; x < width; x++) {
        final sx = (x * image.width) ~/ width;
        pixels[(y * width + x) * 4 + lane] =
            image.pixels[(sy * image.width + sx) * 4 + source.channel];
      }
    }
  }
  return Rgba8Image(width: width, height: height, pixels: pixels);
}

/// [layers]' coat map on [device]: red the clear coat, green its roughness,
/// blue and alpha white until transmission reads them. Null when neither
/// texture is there or none of them decodes, which binds white — the factors
/// alone.
///
/// [image] decodes one binding's image; a caller that has already decoded it
/// for another slot hands back the same pixels. The sampler is the first
/// source's: a coat and its roughness authored together are sampled alike.
Future<({TextureHandle texture, SamplerOptions sampler})?> uploadCoatMap(
  GraphicsDevice device,
  MaterialExtensions layers, {
  required Future<Rgba8Image?> Function(TextureBinding binding) image,
}) async {
  final sources = layers.coatMapSources;
  final lanes = <PackedLane>[
    for (final (lane, binding) in sources.indexed)
      switch (binding == null ? null : await image(binding)) {
        final Rgba8Image decoded => (image: decoded, channel: lane),
        null => null,
      },
  ];
  final packed = packLanes(lanes);
  if (packed == null) return null;
  final sampling = sources.nonNulls.first.sampling;
  final texture = uploadRgba8(device, packed, sampling: sampling);
  return texture == null
      ? null
      : (texture: texture, sampler: samplerOptionsFor(sampling));
}
