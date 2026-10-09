/// Frame captures as files, saved from a running game and opened in the
/// editor — `A5.23`.
///
/// **The loader is the core's**: `FrameCapture.parse` reads what
/// `FrameCapture.toJson` wrote, and everything here is what the editor does
/// with the result — hold it, describe it, show a thumbnail, open one draw.
/// A capture opened from a file answers the same questions a live one
/// does, except where it kept only a thumbnail of an image.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart'
    show CapturedImage, CapturedPass, FrameCapture, FrameCaptureFormatException;
import 'package:flutter3d_cpu/flutter3d_cpu.dart' show encodePng;

/// The capture the editor has open, and where it came from.
final class OpenCapture {
  OpenCapture(this.path, this.capture);

  final String path;
  final FrameCapture capture;

  /// The pass table with its draws and images, as a tool lists it.
  Map<String, Object?> summary() => <String, Object?>{
    'path': path,
    'width': capture.width,
    'height': capture.height,
    'draws': capture.draws.length,
    'undetailedDraws': capture.undetailedDraws,
    'passes': <Map<String, Object?>>[
      for (final (index, pass) in capture.passes.indexed)
        <String, Object?>{
          'index': index,
          'name': pass.name,
          'active': pass.active,
          'drawCalls': pass.drawCalls,
          'triangles': pass.triangles,
          'micros': pass.micros,
          'images': <Map<String, Object?>>[
            for (final image in pass.images) _describe(image),
          ],
        },
    ],
  };

  /// One draw as the file holds it, uniforms decoded, or null when there is
  /// none at [index].
  Map<String, Object?>? draw(int index) {
    if (index < 0 || index >= capture.draws.length) return null;
    return capture.draws[index].toCaptureJson();
  }

  /// A PNG of [pass]'s first image, or of the last pass that has one when
  /// [pass] is null: the image itself when the file kept it, else its
  /// thumbnail. Null when no image has either.
  Uint8List? picture({CapturedPass? pass}) {
    final candidates = pass != null
        ? <CapturedPass>[pass]
        : capture.passes.reversed.toList();
    for (final candidate in candidates) {
      for (final image in candidate.images) {
        final png = _png(image);
        if (png != null) return png;
      }
    }
    return null;
  }

  /// The pass named or numbered [which], or null.
  CapturedPass? passOf(String which) => switch (int.tryParse(which)) {
    final int i when i >= 0 && i < capture.passes.length => capture.passes[i],
    _ => capture.passNamed(which),
  };

  static Map<String, Object?> _describe(CapturedImage image) =>
      <String, Object?>{
        'resource': image.resource,
        'width': image.width,
        'height': image.height,
        'format': image.format.name,
        'kept': image.pixels != null
            ? 'whole'
            : image.thumbnail != null
            ? 'thumbnail ${image.thumbnail!.width}×${image.thumbnail!.height}'
            : 'nothing',
        'refused': ?image.refused,
        'black': image.pixels == null ? null : image.isBlack,
      };

  static Uint8List? _png(CapturedImage image) {
    final pixels = image.pixels;
    if (pixels != null) {
      return encodePng(
        pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
        image.width,
        image.height,
      );
    }
    final small = image.thumbnail;
    if (small == null) return null;
    return encodePng(
      small.pixels.buffer.asUint8List(
        small.pixels.offsetInBytes,
        small.pixels.lengthInBytes,
      ),
      small.width,
      small.height,
    );
  }
}

/// Reads the capture file at [path], or says why it cannot.
({OpenCapture? open, String? why}) openCaptureFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return (open: null, why: 'there is no file at $path');
  final String text;
  try {
    text = file.readAsStringSync();
  } on FileSystemException catch (error) {
    return (open: null, why: 'cannot read $path: ${error.message}');
  }
  try {
    return (open: OpenCapture(path, FrameCapture.parse(text)), why: null);
  } on FrameCaptureFormatException catch (refused) {
    return (
      open: null,
      why: '$path is not a frame capture this editor reads: ${refused.message}',
    );
  }
}

/// Writes [capture] — the JSON a game's `render.capture` answered — to
/// [path], creating its directory, and says how large the file is.
String saveCaptureFile(String path, Map<String, Object?> capture) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  final text = const JsonEncoder.withIndent(' ').convert(capture);
  file.writeAsStringSync(text);
  return '${(text.length / 1024).toStringAsFixed(1)} KiB';
}
