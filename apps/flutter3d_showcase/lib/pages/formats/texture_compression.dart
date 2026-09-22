/// Compressing a texture: four block encoders, a mip chain, and a KTX2
/// container to hold the result.
///
/// Quoted by `texture_compression.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide VkFormat;
import 'package:flutter3d_core/formats.dart'
    show
        Rgba8Image,
        VkFormat,
        buildMipChain,
        encodeAstc4x4,
        encodeBc1,
        encodeBc3,
        encodeEtc2Rgb8,
        writeKtx2;
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class TextureCompressionDemo extends ShowcaseDemo {
  late final Rgba8Image _source;
  late final Uint8List _bc1;
  late final Uint8List _bc3;
  late final Uint8List _etc2;
  late final Uint8List _astc;
  late final Uint8List _ktx2;

  @override
  Scene build(DemoContext context) {
    // #region source
    // A 16x16 checkerboard, whole 4x4 blocks in both directions, which
    // every encoder here requires.
    final pixels = Uint8List(16 * 16 * 4);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final lit = ((x ~/ 4) + (y ~/ 4)).isEven;
        final o = (y * 16 + x) * 4;
        final value = lit ? 220 : 40;
        pixels[o] = value;
        pixels[o + 1] = value;
        pixels[o + 2] = lit ? 60 : 200;
        pixels[o + 3] = 255;
      }
    }
    _source = Rgba8Image(width: 16, height: 16, pixels: pixels);
    // #endregion source

    // #region encode
    _bc1 = encodeBc1(_source);
    _bc3 = encodeBc3(_source);
    _etc2 = encodeEtc2Rgb8(_source);
    _astc = encodeAstc4x4(_source);
    // #endregion encode

    // #region mips
    // A block encoder needs whole 4x4 blocks, so the chain stops at the
    // last level that still is one: 16, 8, 4, and no further.
    final chain = buildMipChain(
      _source,
    ).where((level) => level.width % 4 == 0 && level.height % 4 == 0);
    _ktx2 = writeKtx2(
      vkFormat: VkFormat.bc1RgbaUNormBlock,
      pixelWidth: _source.width,
      pixelHeight: _source.height,
      levels: <Uint8List>[for (final level in chain) encodeBc1(level)],
    );
    // #endregion mips

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(context.device, CuboidShape().build()),
          Material(baseColor: Vector4(0.7, 0.7, 0.75, 1.0)),
          name: 'block',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region report
  int get _rawBytes => _source.pixels.length;

  String _report() =>
      'raw RGBA8: $_rawBytes bytes\n'
      'BC1:  ${_bc1.length} bytes (${(_rawBytes / _bc1.length).toStringAsFixed(1)}x)\n'
      'BC3:  ${_bc3.length} bytes (${(_rawBytes / _bc3.length).toStringAsFixed(1)}x)\n'
      'ETC2: ${_etc2.length} bytes (${(_rawBytes / _etc2.length).toStringAsFixed(1)}x)\n'
      'ASTC 4x4: ${_astc.length} bytes '
      '(${(_rawBytes / _astc.length).toStringAsFixed(1)}x)\n'
      'KTX2 with a mip chain: ${_ktx2.length} bytes';
  // #endregion report

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFFE8E8EC),
            fontSize: 16,
            fontFamily: 'monospace',
          ),
          child: Text(_report()),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // Every block format above packs a 4x4 patch of pixels into fewer
    // bytes than the raw pixels take, or it is not compression.
    if (_bc1.length >= _rawBytes ||
        _bc3.length >= _rawBytes ||
        _etc2.length >= _rawBytes ||
        _astc.length >= _rawBytes) {
      throw StateError('a compressed block is not smaller than the raw one');
    }
    if (_ktx2.length < 12) {
      throw StateError('writeKtx2 did not produce a file');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the block was not drawn');
    }
    // #endregion check
  }
}
