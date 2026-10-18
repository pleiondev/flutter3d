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

/// An [ImageDecoder] that can also scale a large image down while it decodes
/// it — `A4.17`.
///
/// A function of this type *is* an [ImageDecoder] (an extra optional named
/// parameter does not change what a one-argument call means), so every
/// parameter typed [ImageDecoder] takes one unchanged; [uploadEncodedImage]
/// asks `decodeImage is SizedImageDecoder` and passes the cap when it is.
/// `flutter3d`'s `defaultImageDecoder` is one, through `dart:ui`'s target
/// size, so the full-size pixels are never produced. A decoder that is not
/// one is still capped — its result is scaled down afterwards, on the CPU —
/// which costs the full decode the cap was meant to avoid.
///
/// [maxDimension] is the longest side the result may have, keeping the
/// aspect (`cappedImageSize`); null means the file's own size.
typedef SizedImageDecoder =
    Future<Rgba8Image?> Function(Uint8List encoded, {int? maxDimension});
