import 'dart:typed_data';

import '../format_exceptions.dart';
import '../image_sniff.dart';
import '../ktx2/encode/rgba8_image.dart';
import 'jpeg_decoder.dart';
import 'png_decoder.dart';

/// Decodes [encoded] into straight RGBA8 pixels with no Flutter SDK and no
/// `dart:ui` behind it — `mcp-04n`: the headless half of
/// `flutter3d_core`'s own `ImageDecoder` typedef, which this function's
/// signature already matches structurally without needing to import it
/// (`flutter3d_formats` sits below `flutter3d_core` in the dependency
/// order, so the import would run backwards).
///
/// PNG and baseline JPEG only, the same two formats `sniffImageMimeType`
/// recognises a decoder for. Anything else — an unrecognised signature, a
/// progressive JPEG `decodeJpeg` refuses, a truncated file — throws an
/// [ImageFormatException] saying which; the texture upload that takes an
/// `ImageDecoder` treats a throw as it treats a null, as no texture.
Future<Rgba8Image> decodeImagePure(Uint8List encoded) async {
  final mimeType = sniffImageMimeType(encoded);
  final decoded = switch (mimeType) {
    'image/png' => decodePng(encoded),
    'image/jpeg' => decodeJpeg(encoded),
    _ => throw ImageFormatException(
      'an image this decoder does not read: PNG and baseline JPEG are, and '
      'this is ${mimeType ?? 'neither'}',
    ),
  };
  return Rgba8Image(
    width: decoded.width,
    height: decoded.height,
    pixels: decoded.rgba,
  );
}
