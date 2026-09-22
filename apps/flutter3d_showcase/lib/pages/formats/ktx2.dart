/// Reading a KTX2 container that carries Basis Universal ETC1S pixels, and
/// putting the transcoded texture on a cube.
///
/// Quoted by `ktx2.md` and shown whole in the Source tab.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Ktx2Texture;
// The engine's own `Ktx2Texture` (from `flutter3d/flutter3d.dart`) answers
// a `TextureFormat`, already resolved against a device. This page reads
// the container itself, which answers the file's own `vkFormat`.
import 'package:flutter3d_core/formats.dart' show Ktx2Texture, VkFormat;
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class Ktx2Demo extends ShowcaseDemo {
  late final Ktx2Texture _texture;

  // #region bitstream
  // An 8x8 image, four flat-coloured quadrants, encoded by a real build of
  // `basisu`. `vkFormat` is left undefined, KTX2's own way of saying "these
  // pixels are Basis Universal", with the actual flavour named in the
  // container's data format descriptor.
  static const String _fixtureBase64 =
      'q0tUWCAyMLsNChoKAAAAAAEAAAAIAAAACAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAaAAAACw'
      'AAACUAAAAJAAAALgAAAAAAAAAkQAAAAAAAABJAQAAAAAAAAIAAAAAAAAAAAAAAAAAAAAsA'
      'AAAAAAAAAIAKACjAQEAAwMAAAgAAAAAAAAAAAA/AAAAAAAAAAAA/////x8AAABLVFh3cml'
      '0ZXIAQmFzaXMgVW5pdmVyc2FsIDIuNTAAAAQABAAsAAAAEQAAACwAAAAAAAAAAAAAAAAAA'
      'AACAAAAAAAAAAAAAAAgQEQAAAAAAAgjRAATAQAAAAAASAIDwASAAAAAAADiAGACAAAAAAA'
      'AATkjAKyqUlWtqqqqrKqqqlJVVVUFAMFEAAAAAAAA8l+NAJgBAAAAAABAQgkQIUAAAAAAU'
      'pgiAJgAAAAAAABAAAEEEw==';
  // #endregion bitstream

  @override
  Scene build(DemoContext context) {
    // #region parse
    final bytes = base64Decode(_fixtureBase64.replaceAll('\n', ''));
    _texture = Ktx2Texture.parse(bytes);
    // #endregion parse

    // #region upload
    // The level this reader hands back is already plain RGBA8, so it goes
    // straight onto a device texture the same way any other decoded image
    // would.
    final albedo = context.device.createTextureFromPixels(
      width: _texture.pixelWidth,
      height: _texture.pixelHeight,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: _texture.levels.first,
    );
    // #endregion upload

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(context.device, CuboidShape().build()),
          Material(albedo: albedo, roughness: 0.7),
          name: 'block',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_texture.pixelWidth != 8 || _texture.pixelHeight != 8) {
      throw StateError('this fixture is always 8x8');
    }
    if (_texture.vkFormat != VkFormat.r8g8b8a8UNorm) {
      throw StateError('a Basis file should transcode to plain RGBA8');
    }
    // The top-left quadrant is a flat, near-pure red.
    final topLeft = _texture.levels.first.getUint32(0, Endian.little);
    final red = topLeft & 0xff;
    final green = (topLeft >> 8) & 0xff;
    if (red < 240 || green > 15) {
      throw StateError('the top-left quadrant should transcode close to red');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the block was not drawn');
    }
    // #endregion check
  }
}
