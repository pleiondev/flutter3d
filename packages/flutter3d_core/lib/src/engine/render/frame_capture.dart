/// One frame recorded pass by pass, with the pixels each pass wrote —
/// `gfx-70n`.
///
/// **What this is for, and what `FrameResult.passes` already does.** `gfx-01n`
/// gave every pass its time, its draw count, its triangles and its pipeline
/// switches, and the modeller shows them. That table answers "which pass is
/// slow". It cannot answer "why is the frame black", which is the question
/// actually asked, and no amount of timing will: a pass that ran in the usual
/// microseconds and wrote nothing looks exactly like one that worked.
///
/// A capture answers it by holding the evidence. Every pass names what it read,
/// what it wrote and what it maintained, and carries an image of each resource
/// as that pass left it — so the pass where the picture went wrong is the first
/// one whose output is not what the pass after it needed.
///
/// **The copy happens at the pass boundary**, before the frame's resource layer
/// can hand a transient target back to the pool for the next pass to draw over.
/// That is exact on the software rasteriser, whose readback copies the texture
/// before returning; on the hardware backends `readPixels` may resolve after
/// the queue has moved on, so a capture there is evidence about a texture at
/// the moment the driver got to it rather than at the moment it was asked for.
/// The images say which they are — see [CapturedImage.refused], which is also
/// how a resource that cannot be read at all explains itself rather than
/// arriving as a silent gap.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'frame_graph.dart';

/// One resource as one pass left it.
final class CapturedImage {
  const CapturedImage({
    required this.resource,
    required this.width,
    required this.height,
    required this.format,
    this.pixels,
    this.refused,
  });

  /// The frame-graph name, as the pass declared it.
  final String resource;

  final int width;
  final int height;
  final TextureFormat format;

  /// Premultiplied RGBA8, rows from the top, or null when [refused] says why
  /// there are none.
  final ByteData? pixels;

  /// Why there is no image, in a sentence a reader can act on.
  ///
  /// A capture with a gap in it is worse than no capture: the reader assumes
  /// the pass wrote nothing. Tile memory cannot be read after the pass that
  /// used it, a multisampled attachment has no single value per pixel, and a
  /// pass may simply not have provided the resource this frame — three
  /// different facts, and each one is the answer to a different question.
  final String? refused;

  /// The channel at [x], [y], or null when there are no pixels.
  ///
  /// [channel] is 0 for red through 3 for alpha. For a reader walking a capture
  /// by hand, which is what a capture is for.
  int? channelAt(int x, int y, int channel) {
    final bytes = pixels;
    if (bytes == null) return null;
    final at = (y * width + x) * 4 + channel;
    if (at < 0 || at >= bytes.lengthInBytes) return null;
    return bytes.getUint8(at);
  }

  /// Whether every pixel of every colour channel is zero.
  ///
  /// The one question asked of almost every capture, because a black output is
  /// what sends somebody to a capture in the first place.
  bool get isBlack {
    final bytes = pixels;
    if (bytes == null) return false;
    for (var i = 0; i + 3 < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i) != 0 ||
          bytes.getUint8(i + 1) != 0 ||
          bytes.getUint8(i + 2) != 0) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() =>
      'CapturedImage($resource, ${width}x$height, ${format.name}'
      '${refused == null ? '' : ', refused: $refused'})';
}

/// One pass of a captured frame.
final class CapturedPass {
  const CapturedPass({
    required this.name,
    required this.active,
    required this.reads,
    required this.optionalReads,
    required this.writes,
    required this.keeps,
    required this.images,
  });

  final String name;

  /// Whether the node said it had anything to do.
  ///
  /// A pass can be in the order and inactive — see `FrameGraphNode.isActive` —
  /// and an inactive pass with no images is the ordinary case rather than a
  /// missing one.
  final bool active;

  final List<String> reads;
  final List<String> optionalReads;
  final List<String> writes;
  final List<String> keeps;

  /// One entry per resource this pass wrote or maintained.
  final List<CapturedImage> images;

  /// The image for [resource], or null when the pass did not touch it.
  CapturedImage? imageOf(String resource) {
    for (final image in images) {
      if (image.resource == resource) return image;
    }
    return null;
  }

  @override
  String toString() =>
      'CapturedPass($name, ${active ? 'active' : 'inactive'}, '
      '${images.length} images)';
}

/// A whole frame, pass by pass.
final class FrameCapture {
  const FrameCapture({
    required this.width,
    required this.height,
    required this.passes,
  });

  final int width;
  final int height;
  final List<CapturedPass> passes;

  /// The pass called [name], or null.
  CapturedPass? passNamed(String name) {
    for (final pass in passes) {
      if (pass.name == name) return pass;
    }
    return null;
  }

  /// The first pass that wrote [resource] and left it entirely black.
  ///
  /// **The question a capture exists to answer**, in one call: a frame comes
  /// back black, and what a reader wants is the earliest pass whose output was
  /// already black, because everything after it was only propagating that.
  /// A pass with no readable image is skipped rather than blamed — see
  /// [CapturedImage.refused].
  CapturedPass? firstBlack(String resource) {
    for (final pass in passes) {
      final image = pass.imageOf(resource);
      if (image != null && image.isBlack) return pass;
    }
    return null;
  }

  @override
  String toString() =>
      'FrameCapture(${width}x$height, ${passes.length} passes)';
}

/// Collects a capture while a frame runs.
///
/// Held by the renderer for the one frame it is capturing. Separate from
/// [FrameCapture] because the images arrive as futures — the readback is
/// queued at the pass boundary and answered afterwards — and a caller should
/// not be handed a half-filled capture.
final class FrameCaptureBuilder {
  FrameCaptureBuilder({required this.width, required this.height});

  final int width;
  final int height;

  final List<_PendingPass> _passes = <_PendingPass>[];

  /// Records [node] and queues a readback of everything it wrote or maintains.
  void record(
    FrameGraphNode node, {
    required GraphicsDevice device,
    required TextureHandle? Function(ResourceId id) lookup,
  }) {
    final pending = <Future<CapturedImage>>[];
    // Written *and* maintained: a node that keeps an atlas between frames — the
    // static point-shadow bake is the case — writes nothing most frames and is
    // exactly the pass somebody captures a frame to look at.
    final seen = <String>{};
    for (final id in <ResourceId>[...node.writes, ...node.keeps]) {
      if (!seen.add(id.name)) continue;
      pending.add(_read(id, device: device, lookup: lookup));
    }

    _passes.add(
      _PendingPass(
        name: node.name,
        active: node.isActive,
        reads: <String>[for (final id in node.reads) id.name],
        optionalReads: <String>[for (final id in node.optionalReads) id.name],
        writes: <String>[for (final id in node.writes) id.name],
        keeps: <String>[for (final id in node.keeps) id.name],
        images: pending,
      ),
    );
  }

  Future<CapturedImage> _read(
    ResourceId id, {
    required GraphicsDevice device,
    required TextureHandle? Function(ResourceId id) lookup,
  }) async {
    final texture = lookup(id);
    if (texture == null) {
      return CapturedImage(
        resource: id.name,
        width: 0,
        height: 0,
        format: TextureFormat.r8g8b8a8UNormInt,
        refused: 'the pass provided nothing under this name this frame',
      );
    }

    CapturedImage refusing(String why) => CapturedImage(
      resource: id.name,
      width: texture.width,
      height: texture.height,
      format: texture.format,
      refused: why,
    );

    if (texture.storageMode == StorageMode.deviceTransient) {
      return refusing(
        'tile memory: there is nothing to read once the pass has ended',
      );
    }
    if (texture.sampleCount > 1) {
      return refusing(
        'multisampled: ${texture.sampleCount} samples a pixel and no single '
        'value to hand back',
      );
    }
    if (texture.type != TextureType.texture2D) {
      return refusing('a cube: six faces, and this holds one image');
    }

    final ByteData? bytes;
    try {
      bytes = await device.readPixels(texture);
    } on Object catch (error) {
      return refusing('the backend refused the read: $error');
    }
    if (bytes == null) return refusing('the backend answered no pixels');

    return CapturedImage(
      resource: id.name,
      width: texture.width,
      height: texture.height,
      format: texture.format,
      pixels: bytes,
    );
  }

  /// The finished capture, once every queued readback has answered.
  Future<FrameCapture> build() async => FrameCapture(
    width: width,
    height: height,
    passes: <CapturedPass>[
      for (final pass in _passes)
        CapturedPass(
          name: pass.name,
          active: pass.active,
          reads: pass.reads,
          optionalReads: pass.optionalReads,
          writes: pass.writes,
          keeps: pass.keeps,
          images: await Future.wait(pass.images),
        ),
    ],
  );
}

final class _PendingPass {
  const _PendingPass({
    required this.name,
    required this.active,
    required this.reads,
    required this.optionalReads,
    required this.writes,
    required this.keeps,
    required this.images,
  });

  final String name;
  final bool active;
  final List<String> reads;
  final List<String> optionalReads;
  final List<String> writes;
  final List<String> keeps;
  final List<Future<CapturedImage>> images;
}
