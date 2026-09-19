/// PNG, JPEG and Radiance `.hdr`, decoded with no `dart:ui` in sight.
///
/// Quoted by `image_decode.md` and shown whole in the Source tab.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ImageDecodeDemo extends ShowcaseDemo {
  late final DecodedImage _png;
  late final DecodedImage _jpeg;
  late final HdrImage _hdr;

  // #region jpeg-source
  // A real JPEG, one 8x8 MCU encoded at quality 100 from a flat
  // (200, 100, 50) fill, the same fixture the decoder's own test checks
  // against that exact colour.
  static const String _jpegBase64 =
      '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB'
      'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQEBAQEB'
      'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAAR'
      'CAAIAAgDAREAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAA'
      'AgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkK'
      'FhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWG'
      'h4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl'
      '5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREA'
      'AgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYk'
      'NOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOE'
      'hYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk'
      '5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDn6/yvP9sD/9k=';
  // #endregion jpeg-source

  @override
  Scene build(DemoContext context) {
    // #region png
    // A tiny checkerboard, encoded here and decoded straight back: a real
    // compressed PNG, not a fixture on disk.
    final width = 4, height = 4;
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final lit = (x + y).isEven;
        final o = (y * width + x) * 4;
        rgba[o] = lit ? 240 : 20;
        rgba[o + 1] = lit ? 240 : 20;
        rgba[o + 2] = lit ? 240 : 20;
        rgba[o + 3] = 255;
      }
    }
    final pngBytes = encodeCompressedPng(width, height, rgba);
    _png = decodePng(pngBytes)!;
    // #endregion png

    // #region jpeg
    final jpegBytes = base64Decode(_jpegBase64);
    _jpeg = decodeJpeg(jpegBytes)!;
    // #endregion jpeg

    // #region hdr
    // Radiance's old, flat scanline encoding: a header, a resolution line,
    // then every pixel as four raw bytes (R, G, B, a shared exponent). Two
    // by two is under the width the new run-length form requires, so this
    // is read the simple way.
    final hdrText = '#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y 2 +X 2\n';
    final hdrBytes = Uint8List.fromList(<int>[
      ...utf8.encode(hdrText),
      // Top row: a dim red pixel, a bright red pixel.
      255, 0, 0, 120, 255, 0, 0, 128,
      // Bottom row: two pixels at half that brightness again.
      255, 0, 0, 119, 255, 0, 0, 127,
    ]);
    _hdr = readHdr(hdrBytes);
    // #endregion hdr

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(context.device, CuboidShape().build()),
          Material(baseColor: Vector4(0.6, 0.6, 0.6, 1.0)),
          name: 'block',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region report
  String _report() =>
      'PNG:  ${_png.width}x${_png.height}, top-left pixel '
      '${_png.rgba[0]},${_png.rgba[1]},${_png.rgba[2]}\n'
      'JPEG: ${_jpeg.width}x${_jpeg.height}, decodes back to about '
      '${_jpeg.rgba[0]},${_jpeg.rgba[1]},${_jpeg.rgba[2]} (encoded from '
      '200,100,50)\n'
      'HDR:  ${_hdr.width}x${_hdr.height}, top-left red channel '
      '${_hdr.rgb[0].toStringAsFixed(3)}';
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
    if (_png.width != 4 || _png.height != 4) {
      throw StateError('the PNG did not round-trip its own size');
    }
    if (_png.rgba[0] < 200) {
      throw StateError('the PNG round trip lost its lit corner');
    }
    if ((_jpeg.rgba[0] - 200).abs() > 5 || (_jpeg.rgba[1] - 100).abs() > 5) {
      throw StateError('the JPEG did not decode close to its own fill');
    }
    if (_hdr.rgb[0] <= 0.0) {
      throw StateError('the HDR pixel decoded to nothing');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the block was not drawn');
    }
    // #endregion check
  }
}
