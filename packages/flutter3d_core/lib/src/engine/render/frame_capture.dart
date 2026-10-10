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

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show FormatDocument, FormatSpec;

import '../../formats/format_exceptions.dart';
import 'capture_json.dart';
import 'draw_journal.dart';
import 'frame_graph.dart';

/// A small copy of a [CapturedImage] — `A5.23`: what a capture file keeps
/// of an image when it does not keep the image.
final class CaptureThumbnail {
  const CaptureThumbnail({
    required this.width,
    required this.height,
    required this.pixels,
  });

  final int width;
  final int height;

  /// RGBA8 as the image's own pixels are — premultiplied, rows from the
  /// top — each the mean of the pixels it covers.
  final ByteData pixels;
}

/// One resource as one pass left it.
final class CapturedImage {
  const CapturedImage({
    required this.resource,
    required this.width,
    required this.height,
    required this.format,
    this.pixels,
    this.floats,
    this.refused,
    this.thumbnail,
  });

  /// [json] as [toJson] wrote it, or null when it lacks a resource name or
  /// a size — `A5.23`.
  ///
  /// The pixels come back exactly when the file kept them
  /// (`FrameCapture.toJson(images: true)`); otherwise [pixels] is null and
  /// [thumbnail] holds what there is. [floats] come back when the file kept
  /// them, NaNs included.
  static CapturedImage? fromJson(Map<String, Object?> json) {
    final resource = json['resource'];
    final width = json['width'];
    final height = json['height'];
    if (resource is! String || width is! int || height is! int) return null;
    final format = switch (json['format']) {
      final String word => captureTextureFormats[word],
      _ => null,
    };
    final full = decodeCapturePng(json['png']);
    final small = decodeCapturePng(json['thumbnail']);
    final fits = full != null && full.width == width && full.height == height;
    return CapturedImage(
      resource: resource,
      width: width,
      height: height,
      format: format ?? TextureFormat.unknown,
      pixels: fits ? ByteData.sublistView(full.rgba) : null,
      floats: decodeFloats(json['floats']),
      refused: switch (json['refused']) {
        final String why => why,
        _ => null,
      },
      thumbnail: small == null
          ? null
          : CaptureThumbnail(
              width: small.width,
              height: small.height,
              pixels: ByteData.sublistView(small.rgba),
            ),
    );
  }

  /// What a capture file holds for this image — `A5.23`: its name, size,
  /// format and refusal; a thumbnail of [pixels] no larger than
  /// [thumbnailSize] on its longer side, as a base64 PNG; the full pixels
  /// as another when [images]; the [floats], exactly, when [floats].
  Map<String, Object?> toJson({
    int thumbnailSize = 128,
    bool images = false,
    bool floats = false,
  }) {
    final bytes = pixels;
    final rgba = bytes == null || bytes.lengthInBytes < width * height * 4
        ? null
        : Uint8List.sublistView(bytes, 0, width * height * 4);
    CaptureThumbnail shrink(Uint8List rgba) {
      final shrunk = shrinkRgba(rgba, width, height, thumbnailSize);
      return CaptureThumbnail(
        width: shrunk.width,
        height: shrunk.height,
        pixels: ByteData.sublistView(shrunk.rgba),
      );
    }

    final small = rgba == null ? thumbnail : shrink(rgba);
    final kept = this.floats;
    return <String, Object?>{
      'resource': resource,
      'width': width,
      'height': height,
      'format': captureWordFor(format),
      'refused': ?refused,
      if (small != null) ...<String, Object?>{
        'thumbnailWidth': small.width,
        'thumbnailHeight': small.height,
        'thumbnail': base64Encode(
          encodeCapturePng(
            Uint8List.sublistView(small.pixels),
            small.width,
            small.height,
          ),
        ),
      },
      if (images && rgba != null)
        'png': base64Encode(encodeCapturePng(rgba, width, height)),
      if (floats && kept != null) 'floats': encodeFloats(kept),
    };
  }

  /// The frame-graph name, as the pass declared it.
  final String resource;

  final int width;
  final int height;
  final TextureFormat format;

  /// Premultiplied RGBA8, rows from the top, or null when [refused] says why
  /// there are none.
  final ByteData? pixels;

  /// The texture's own RGBA floats, unclamped, or null where the backend
  /// cannot hand them back — `P12`.
  ///
  /// [pixels] is eight bits a channel on every backend, and a NaN a shader
  /// wrote clamps to an ordinary byte on the way there. Only a backend that
  /// keeps its textures as floats can answer this, and the capture asks it
  /// through [FrameCaptureBuilder.readFloats].
  final Float32List? floats;

  /// Why there is no image, in a sentence a reader can act on.
  ///
  /// A capture with a gap in it is worse than no capture: the reader assumes
  /// the pass wrote nothing. Tile memory cannot be read after the pass that
  /// used it, a multisampled attachment has no single value per pixel, and a
  /// pass may simply not have provided the resource this frame — three
  /// different facts, and each one is the answer to a different question.
  final String? refused;

  /// A small copy of the image, kept by a capture file that did not keep
  /// [pixels] — `A5.23`. Null on a capture the renderer has just taken,
  /// whose [pixels] are the image itself.
  final CaptureThumbnail? thumbnail;

  /// The channel at [x], [y], or null when there are no pixels or the
  /// coordinate is outside the image.
  ///
  /// [channel] is 0 for red through 3 for alpha. For a reader walking a capture
  /// by hand, which is what a capture is for. Each coordinate is checked on
  /// its own: a column past the right edge is otherwise the first pixel of the
  /// next row, which reads as a real answer about the wrong place.
  int? channelAt(int x, int y, int channel) {
    final bytes = pixels;
    if (bytes == null) return null;
    if (x < 0 || x >= width || y < 0 || y >= height) return null;
    if (channel < 0 || channel > 3) return null;
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
    this.micros = 0,
    this.drawCalls = 0,
    this.triangles = 0,
  });

  final String name;

  /// What the pass cost, as `FrameResult.passes` reported it — `P12`, so a
  /// capture answers "how big was this frame" on its own.
  final int micros;
  final int drawCalls;
  final int triangles;

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

  /// [json] as [toJson] wrote it, or null without a name — `A5.23`.
  static CapturedPass? fromJson(Map<String, Object?> json) {
    final name = json['name'];
    if (name is! String) return null;
    List<String> names(String key) => switch (json[key]) {
      final List<Object?> list => List<String>.unmodifiable(
        list.whereType<String>(),
      ),
      _ => const <String>[],
    };
    int whole(String key) => switch (json[key]) {
      final int n => n,
      _ => 0,
    };
    return CapturedPass(
      name: name,
      active: json['active'] == true,
      reads: names('reads'),
      optionalReads: names('optionalReads'),
      writes: names('writes'),
      keeps: names('keeps'),
      images: List<CapturedImage>.unmodifiable(<CapturedImage>[
        if (json['images'] case final List<Object?> images)
          for (final image in images.whereType<Map<String, Object?>>())
            ?CapturedImage.fromJson(image),
      ]),
      micros: whole('micros'),
      drawCalls: whole('drawCalls'),
      triangles: whole('triangles'),
    );
  }

  /// What a capture file holds for this pass; [CapturedImage.toJson] says
  /// what the parameters keep of each image.
  Map<String, Object?> toJson({
    int thumbnailSize = 128,
    bool images = false,
    bool floats = false,
  }) => <String, Object?>{
    'name': name,
    'active': active,
    'reads': reads,
    'optionalReads': optionalReads,
    'writes': writes,
    'keeps': keeps,
    'micros': micros,
    'drawCalls': drawCalls,
    'triangles': triangles,
    'images': <Map<String, Object?>>[
      for (final image in this.images)
        image.toJson(
          thumbnailSize: thumbnailSize,
          images: images,
          floats: floats,
        ),
    ],
  };

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
///
/// **A [FormatDocument]**: written in the format envelope, and a key this
/// build does not read is kept in [unknown] and written back.
final class FrameCapture extends FormatDocument {
  FrameCapture({
    required this.width,
    required this.height,
    required this.passes,
    this.draws = const <DrawRecord>[],
    this.undetailedDraws = const <String, int>{},
    this.notes,
    super.unknown,
  });

  @override
  FormatSpec get spec => format;

  final int width;
  final int height;
  final List<CapturedPass> passes;

  /// Every draw the frame described, when the capture asked for them — `P12`.
  /// Empty otherwise; see [DrawJournal].
  final List<DrawRecord> draws;

  /// Draws a pass counted without describing, by pass name — see
  /// [DrawJournal.undetailed].
  final Map<String, int> undetailedDraws;

  /// What the reporter wrote beside the frame, as the file had it; null for
  /// a capture just taken. [toJson]'s `notes` replaces it.
  final String? notes;

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

  /// What `format` says in a capture file, so a reader can tell one from
  /// any other JSON before trusting it.
  static const String fileFormat = 'f3d.frameCapture';

  /// The layout [toJson] writes. A reader takes this and older.
  ///
  /// **Version 2 is the format envelope** (`format`, `version`, `requires`,
  /// `generator`) under the id [fileFormat]. A version-1 file said
  /// `"format": "flutter3d.frameCapture"`, which [format] lists as an alias,
  /// and reads as it always did.
  static const int fileVersion = 2;

  /// The frame capture in the format registry.
  static const FormatSpec format = FormatSpec(
    id: fileFormat,
    version: fileVersion,
    suffixes: <String>['.capture.json'],
    fixture: 'test/fixtures/v<N>/frame.capture.json',
    aliases: <String>['flutter3d.frameCapture'],
  );

  /// The keys [fromJson] reads; the rest go to [unknown].
  static const Set<String> _known = <String>{
    'width',
    'height',
    'notes',
    'passes',
    'draws',
    'undetailedDraws',
  };

  /// The whole frame as JSON — `A5.23`: a file to attach to a bug report
  /// and open in the editor, with every pass, every draw with its uniforms
  /// decoded, and a PNG thumbnail of every image no larger than
  /// [thumbnailSize] on its longer side.
  ///
  /// **Thumbnails by default, and the reason is size.** A 1080p HDR target
  /// is eight megabytes of readback, and a frame writes dozens; the
  /// thumbnail is enough to see which pass went black. [images] keeps the
  /// full eight-bit pixels as well, so the file reads back exactly;
  /// [floats] keeps a float target's own values, which is where a NaN
  /// lives. Everything goes through `jsonEncode`: a NaN or an infinity in a
  /// uniform is written as the string `"NaN"`, `"Infinity"` or
  /// `"-Infinity"`.
  ///
  /// [notes] is free text a reporter adds — what they were doing, what
  /// they expected — and replaces [FrameCapture.notes].
  Map<String, Object?> toJson({
    int thumbnailSize = 128,
    bool images = false,
    bool floats = false,
    String? notes,
  }) => write(<String, Object?>{
    'width': width,
    'height': height,
    'notes': ?(notes ?? this.notes),
    'passes': <Map<String, Object?>>[
      for (final pass in passes)
        pass.toJson(
          thumbnailSize: thumbnailSize,
          images: images,
          floats: floats,
        ),
    ],
    'draws': <Map<String, Object?>>[
      for (final draw in draws) draw.toCaptureJson(),
    ],
    'undetailedDraws': undetailedDraws,
  });

  /// A capture read back from [toJson] — `A5.23`.
  ///
  /// Throws a [FrameCaptureFormatException] saying why when [json] is not
  /// one: no `format` or another format's, a `version` newer than
  /// [fileVersion] (with the versions, so the reader knows to update), or
  /// no size. A pass, an image or a draw this reader cannot make sense of is
  /// left out rather than failing the whole file.
  static FrameCapture fromJson(Map<String, Object?> document) {
    if (document['format'] == null) {
      throw const FrameCaptureFormatException(
        'this JSON names no "format", so it is not a frame capture',
      );
    }
    final json = format.open(document, refuse: FrameCaptureFormatException.new);
    final width = json['width'];
    final height = json['height'];
    if (width is! int || height is! int) {
      throw const FrameCaptureFormatException(
        'a frame capture names its "width" and "height" in whole pixels',
      );
    }
    return FrameCapture(
      width: width,
      height: height,
      notes: switch (json['notes']) {
        final String text => text,
        _ => null,
      },
      unknown: FormatDocument.unknownIn(json, known: _known, spec: format),
      passes: List<CapturedPass>.unmodifiable(<CapturedPass>[
        if (json['passes'] case final List<Object?> passes)
          for (final pass in passes.whereType<Map<String, Object?>>())
            ?CapturedPass.fromJson(pass),
      ]),
      draws: List<DrawRecord>.unmodifiable(<DrawRecord>[
        if (json['draws'] case final List<Object?> draws)
          for (final draw in draws.whereType<Map<String, Object?>>())
            ?DrawRecord.fromJson(draw),
      ]),
      undetailedDraws: Map<String, int>.unmodifiable(<String, int>{
        if (json['undetailedDraws'] case final Map<String, Object?> counts)
          for (final MapEntry(:key, :value) in counts.entries)
            if (value case final int n) key: n,
      }),
    );
  }

  /// [source] — the text of a capture file — read back. Throws a
  /// [FrameCaptureFormatException] when it is not JSON or not a capture this
  /// build reads, saying which; see [fromJson].
  static FrameCapture parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FrameCaptureFormatException(
        'a frame capture is JSON, and this is not: ${error.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const FrameCaptureFormatException(
        'a frame capture is a JSON object',
      );
    }
    return fromJson(decoded);
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
  FrameCaptureBuilder({
    required this.width,
    required this.height,
    this.journal,
    this.readFloats,
  });

  final int width;
  final int height;

  /// Where the frame's draws are written down, or null when nobody asked.
  final DrawJournal? journal;

  /// Reads a texture's floats as they stand, for a backend that keeps them —
  /// the software rasteriser's `readHdrPixels`. Null everywhere else, and
  /// then [CapturedImage.floats] is null too.
  final Float32List? Function(TextureHandle texture)? readFloats;

  final List<_PendingPass> _passes = <_PendingPass>[];

  /// Records [node] and queues a readback of everything it wrote or maintains.
  void record(
    FrameGraphNode node, {
    required GraphicsDevice device,
    required TextureHandle? Function(ResourceId id) lookup,
    int micros = 0,
    int drawCalls = 0,
    int triangles = 0,
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
        micros: micros,
        drawCalls: drawCalls,
        triangles: triangles,
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

    final ByteData bytes;
    try {
      bytes = await device.readback(texture);
    } on Object catch (error) {
      return refusing('the backend refused the read: $error');
    }

    return CapturedImage(
      resource: id.name,
      width: texture.width,
      height: texture.height,
      format: texture.format,
      pixels: bytes,
      floats: _floatsOf(texture),
    );
  }

  /// [readFloats]' answer for [texture], or null when it has none or throws:
  /// the eight-bit image is still evidence, and losing it to a float read
  /// that failed would be worse than having only it.
  Float32List? _floatsOf(TextureHandle texture) {
    try {
      return readFloats?.call(texture);
    } on Object {
      return null;
    }
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
          micros: pass.micros,
          drawCalls: pass.drawCalls,
          triangles: pass.triangles,
        ),
    ],
    draws: journal?.records ?? const <DrawRecord>[],
    undetailedDraws: journal?.undetailed ?? const <String, int>{},
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
    required this.micros,
    required this.drawCalls,
    required this.triangles,
  });

  final String name;
  final bool active;
  final List<String> reads;
  final List<String> optionalReads;
  final List<String> writes;
  final List<String> keeps;
  final List<Future<CapturedImage>> images;
  final int micros;
  final int drawCalls;
  final int triangles;
}

/// The words a capture file names a texture's format by, and the
/// [TextureFormat] each is.
///
/// **An explicit table, not `TextureFormat.values.asNameMap()`.** The words
/// are what files on disk say, and they were the Dart names of the values
/// when captures were first written; a rename of a value must not change
/// what a capture file says or stop an old one reading. A new format gets a
/// new word here, and no word changes meaning. A word this build does not
/// know reads as [TextureFormat.unknown].
const Map<String, TextureFormat> captureTextureFormats =
    <String, TextureFormat>{
      'unknown': TextureFormat.unknown,
      'a8UNormInt': TextureFormat.a8UNormInt,
      'r8UNormInt': TextureFormat.r8UNormInt,
      'r8g8UNormInt': TextureFormat.r8g8UNormInt,
      'r8g8b8a8UNormInt': TextureFormat.r8g8b8a8UNormInt,
      'r8g8b8a8UNormIntSRGB': TextureFormat.r8g8b8a8UNormIntSRGB,
      'b8g8r8a8UNormInt': TextureFormat.b8g8r8a8UNormInt,
      'b8g8r8a8UNormIntSRGB': TextureFormat.b8g8r8a8UNormIntSRGB,
      'r32g32b32a32Float': TextureFormat.r32g32b32a32Float,
      'r16g16b16a16Float': TextureFormat.r16g16b16a16Float,
      'r32Float': TextureFormat.r32Float,
      's8UInt': TextureFormat.s8UInt,
      'd24UnormS8Uint': TextureFormat.d24UnormS8Uint,
      'd32FloatS8UInt': TextureFormat.d32FloatS8UInt,
      'bc1RGBAUNormInt': TextureFormat.bc1RGBAUNormInt,
      'bc1RGBAUNormIntSRGB': TextureFormat.bc1RGBAUNormIntSRGB,
      'bc3RGBAUNormInt': TextureFormat.bc3RGBAUNormInt,
      'bc3RGBAUNormIntSRGB': TextureFormat.bc3RGBAUNormIntSRGB,
      'bc5RGUNormInt': TextureFormat.bc5RGUNormInt,
      'bc7RGBAUNormInt': TextureFormat.bc7RGBAUNormInt,
      'bc7RGBAUNormIntSRGB': TextureFormat.bc7RGBAUNormIntSRGB,
      'etc2RGB8UNormInt': TextureFormat.etc2RGB8UNormInt,
      'etc2RGB8UNormIntSRGB': TextureFormat.etc2RGB8UNormIntSRGB,
      'etc2RGBA8UNormInt': TextureFormat.etc2RGBA8UNormInt,
      'etc2RGBA8UNormIntSRGB': TextureFormat.etc2RGBA8UNormIntSRGB,
      'astc4x4LDR': TextureFormat.astc4x4LDR,
      'astc4x4LDRSRGB': TextureFormat.astc4x4LDRSRGB,
      'astc8x8LDR': TextureFormat.astc8x8LDR,
      'astc8x8LDRSRGB': TextureFormat.astc8x8LDRSRGB,
      'astc4x4HDR': TextureFormat.astc4x4HDR,
      'astc8x8HDR': TextureFormat.astc8x8HDR,
      'r8g8b8a8SNormInt': TextureFormat.r8g8b8a8SNormInt,
      'r8g8b8a8UInt': TextureFormat.r8g8b8a8UInt,
      'r8g8b8a8SInt': TextureFormat.r8g8b8a8SInt,
      'r16Float': TextureFormat.r16Float,
      'r16g16Float': TextureFormat.r16g16Float,
      'r16g16b16a16UInt': TextureFormat.r16g16b16a16UInt,
      'r16g16b16a16SInt': TextureFormat.r16g16b16a16SInt,
      'r32UInt': TextureFormat.r32UInt,
      'r32SInt': TextureFormat.r32SInt,
      'r32g32Float': TextureFormat.r32g32Float,
      'r32g32UInt': TextureFormat.r32g32UInt,
      'r32g32SInt': TextureFormat.r32g32SInt,
      'r32g32b32a32UInt': TextureFormat.r32g32b32a32UInt,
      'r32g32b32a32SInt': TextureFormat.r32g32b32a32SInt,
      'r10g10b10a2UNormInt': TextureFormat.r10g10b10a2UNormInt,
      'r11g11b10UFloat': TextureFormat.r11g11b10UFloat,
      'r9g9b9e5UFloat': TextureFormat.r9g9b9e5UFloat,
      'd16UNormInt': TextureFormat.d16UNormInt,
      'd32Float': TextureFormat.d32Float,
    };

/// The word [captureTextureFormats] writes for [format]; `unknown` for a
/// format the table does not name yet.
String captureWordFor(TextureFormat format) {
  for (final MapEntry(:key, :value) in captureTextureFormats.entries) {
    if (value == format) return key;
  }
  return 'unknown';
}
