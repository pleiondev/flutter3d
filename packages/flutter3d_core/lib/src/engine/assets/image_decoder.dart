import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';

/// Decodes an encoded image — PNG, JPEG, whatever [uploadEncodedImage]'s
/// caller hands it — into straight (not premultiplied) RGBA8 pixels, or
/// `null` for an image that will not decode.
///
/// **Why this is a parameter and not a call.** `dart:ui`'s
/// `instantiateImageCodec` is what every existing Flutter app already gets
/// this from, and it is also the one call in this file mcp-01n's whole
/// reason for existing refuses to let `flutter3d_core` make: a flat package
/// cannot name `dart:ui` and stay flat. `flutter3d`'s own
/// `defaultImageDecoder` is that call, wrapped to this shape; a `dart run`
/// caller with no Flutter SDK to ask supplies a different one — a pure-Dart
/// PNG decoder, once mcp-04n exists — instead.
typedef ImageDecoder = Future<Rgba8Image?> Function(Uint8List encoded);
