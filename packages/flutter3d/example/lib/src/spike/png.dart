/// Encoding raw pixels as a PNG, and reading one back, for the paths that
/// write and compare files.
///
/// **Byte for byte both ways, and in Dart.** The frame arrives as the bytes
/// the target holds, and a golden is only as good as the promise that the
/// file holds the same ones. These used to go through `dart:ui`:
/// `decodeImageFromPixels` takes its pixels as premultiplied, the PNG it
/// writes is divided back out, and a reference read with `rawRgba` is
/// multiplied again. Wherever a pixel's colour stood above its alpha — the
/// rim of a coverage edge did — the division clipped at 255, and the frame
/// that was recorded compared as twelve units away from itself on the next
/// run. A pure encoder and decoder neither multiply nor divide, so a
/// comparison can neither invent a difference nor hide one.
///
/// Affordable for the reason the old round trip was: this runs when a golden
/// is recorded or has failed, and when a debug capture is taken. Never per
/// frame.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' show decodePng, encodeCompressedPng;

/// Encodes [rgba] — RGBA8, row-major from the top-left, as
/// `GraphicsDevice.readback` returns it — as an 8-bit RGBA PNG holding
/// exactly those bytes.
Future<Uint8List?> encodePng(ByteData rgba, int width, int height) async =>
    encodeCompressedPng(
      width,
      height,
      rgba.buffer.asUint8List(rgba.offsetInBytes, width * height * 4),
    );

/// The RGBA8 bytes [png] holds, exactly as written — no premultiplication
/// and no colour management in either direction.
Uint8List decodePngBytes(Uint8List png) => decodePng(png).rgba;
