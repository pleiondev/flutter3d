/// The answers `ext.flutter3d.render.*` gives, worked out of one
/// [FrameCapture] — `P12`.
///
/// **Functions from a capture and a parameter map to a JSON map, and nothing
/// else.** The VM service is a transport: what it carries is "which pass",
/// "which pixel", "which draw", and every one of those questions can be asked
/// of a capture built by hand in a test. Kept apart from the registration in
/// `render_extensions.dart` so that the part with the decisions in it — what an
/// unknown pass is told, what a pixel past the edge is told, what a NaN looks
/// like in JSON — is tested without a VM, a window or a GPU.
///
/// **A refusal is an answer**: every function returns `{"refused": "..."}`
/// rather than throwing when it cannot do what was asked, and the sentence
/// names what was asked, why it cannot be, and what would work.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart' show encodePng;

/// What a refusal looks like, so the registration can tell one apart.
Map<String, Object?> refusal(String why) => <String, Object?>{'refused': why};

/// Whether [answer] is a refusal from one of the functions here.
bool isRefusal(Map<String, Object?> answer) => answer['refused'] is String;

/// `passes`: every pass of the frame, in the order it ran.
Map<String, Object?> renderPasses(FrameCapture capture) => <String, Object?>{
  'width': capture.width,
  'height': capture.height,
  'passes': <Map<String, Object?>>[
    for (final (index, pass) in capture.passes.indexed)
      <String, Object?>{
        'index': index,
        'name': pass.name,
        'active': pass.active,
        'reads': pass.reads,
        'optionalReads': pass.optionalReads,
        'writes': pass.writes,
        'keeps': pass.keeps,
        'outputs': <Map<String, Object?>>[
          for (final image in pass.images) _describeImage(image),
        ],
        'micros': pass.micros,
        'drawCalls': pass.drawCalls,
        'triangles': pass.triangles,
      },
  ],
};

/// `passOutput`: one output of one pass as a PNG, base64.
///
/// [parameters]: `pass` (an index or a name), `resource` (optional; the
/// pass's first output when absent). The PNG holds the eight-bit readback,
/// premultiplied, which is what every backend can hand back — see
/// `GraphicsDevice.readPixels`.
Map<String, Object?> renderPassOutput(
  FrameCapture capture,
  Map<String, String> parameters,
) => _answering(() {
  final (pass, image) = _imageFor(capture, parameters);
  final pixels = image.pixels;
  if (pixels == null) {
    throw _Refusal(
      'pass "${pass.name}" has no picture of "${image.resource}": '
      '${image.refused ?? 'the backend answered no pixels'}',
    );
  }
  return <String, Object?>{
    'pass': pass.name,
    ..._describeImage(image),
    'png': base64Encode(
      encodePng(
        pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
        image.width,
        image.height,
      ),
    ),
  };
});

/// `draws`: the frame's described draws, one row each.
///
/// [parameters]: `pass` (optional; an index or a name to keep only that
/// pass's draws), `offset` and `limit` (a page; two hundred rows by default,
/// because a frame of a few thousand draws is a response nobody reads whole).
Map<String, Object?> renderDraws(
  FrameCapture capture,
  Map<String, String> parameters,
) => _answering(() {
  final counted = capture.passes.fold<int>(0, (sum, p) => sum + p.drawCalls);
  if (capture.draws.isEmpty && capture.undetailedDraws.isEmpty && counted > 0) {
    throw _Refusal(
      'this capture was taken without the draw journal, so its $counted '
      'draws are counted and not described; capture again with '
      '`captureNextFrame(draws: true)`',
    );
  }
  final passName = switch (parameters['pass']) {
    final key? => _passFor(capture, key).$2.name,
    null => null,
  };
  final offset = int.tryParse(parameters['offset'] ?? '') ?? 0;
  final limit = int.tryParse(parameters['limit'] ?? '') ?? 200;
  if (offset < 0 || limit < 1) {
    throw _Refusal(
      'offset must be zero or more and limit one or more; '
      'got offset $offset, limit $limit',
    );
  }
  final matching = <DrawRecord>[
    for (final draw in capture.draws)
      if (passName == null || draw.pass == passName) draw,
  ];
  return <String, Object?>{
    'total': matching.length,
    'offset': offset,
    'draws': <Map<String, Object?>>[
      for (final draw in matching.skip(offset).take(limit))
        draw.toSummaryJson(),
    ],
    'undetailed': <String, int>{
      for (final MapEntry(:key, :value) in capture.undetailedDraws.entries)
        if (passName == null || key == passName) key: value,
    },
  };
});

/// `draw`: one draw, with its state and the values bound for it.
///
/// [parameters]: `index`, as [renderDraws] numbered it.
Map<String, Object?> renderDraw(
  FrameCapture capture,
  Map<String, String> parameters,
) => _answering(() {
  final index = int.tryParse(parameters['index'] ?? '');
  if (index == null) {
    throw const _Refusal('draw takes an index, an integer from `draws`');
  }
  if (index < 0 || index >= capture.draws.length) {
    throw _Refusal(
      capture.draws.isEmpty
          ? 'there is no draw $index: this frame described no draws'
          : 'there is no draw $index: this frame described '
                '${capture.draws.length}, numbered 0 to '
                '${capture.draws.length - 1}',
    );
  }
  final draw = capture.draws[index];
  return <String, Object?>{
    ...draw.toJson(),
    // A NaN in a matrix is exactly what somebody opens one draw to find, and
    // `jsonEncode` throws on one rather than writing it.
    'uniforms': <String, Object?>{
      for (final MapEntry(:key, :value) in draw.uniforms.entries)
        key: <Object>[for (final v in value) _number(v)],
    },
  };
});

/// `pick`: what [node] — the picking pass's answer at ([x], [y]) — drew in
/// [capture], the same frame: its name and the indices of its draws, which
/// `draw` opens. Nothing picked is the clear colour, said as such.
Map<String, Object?> renderPicked(
  FrameCapture capture,
  MeshNode? node, {
  required int x,
  required int y,
}) => node == null
    ? <String, Object?>{
        'x': x,
        'y': y,
        'node': null,
        'draws': const <int>[],
        'says': 'nothing is drawn at ($x, $y): it is the clear colour',
      }
    : <String, Object?>{
        'x': x,
        'y': y,
        'node': node.name,
        'draws': <int>[
          for (final draw in capture.draws)
            if (identical(draw.node, node)) draw.index,
        ],
      };

/// `readPixel`: one pixel of one output, as stored and as read back.
///
/// [parameters]: `pass`, `x`, `y`, and `resource` (optional). `uint` is the
/// eight-bit readback every backend has; `float` is the texture's own value
/// where the backend keeps one, and null with `floatUnread` saying why
/// otherwise. A NaN or an infinity arrives as the string `"NaN"`,
/// `"Infinity"` or `"-Infinity"`, because JSON has no number for them.
Map<String, Object?> renderReadPixel(
  FrameCapture capture,
  Map<String, String> parameters,
) => _answering(() {
  final x = int.tryParse(parameters['x'] ?? '');
  final y = int.tryParse(parameters['y'] ?? '');
  if (x == null || y == null) {
    throw const _Refusal('readPixel takes x and y, integers from the top left');
  }
  final (pass, image) = _imageFor(capture, parameters);
  if (image.pixels == null && image.floats == null) {
    throw _Refusal(
      'pass "${pass.name}" has no pixels of "${image.resource}": '
      '${image.refused ?? 'the backend answered none'}',
    );
  }
  if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
    throw _Refusal(
      '($x, $y) lies outside "${image.resource}", which is '
      '${image.width}x${image.height}: x runs 0 to ${image.width - 1} and '
      'y 0 to ${image.height - 1}',
    );
  }
  final uint = <int?>[for (var c = 0; c < 4; c++) image.channelAt(x, y, c)];
  final readable = !uint.contains(null);
  final floats = _floatsAt(image, x, y);
  return <String, Object?>{
    'pass': pass.name,
    'resource': image.resource,
    'format': image.format.name,
    'x': x,
    'y': y,
    'uint': readable ? uint : null,
    'unorm': readable ? <double>[for (final v in uint) v! / 255.0] : null,
    'float': floats == null
        ? null
        : <Object>[for (final v in floats) _number(v)],
    if (floats == null) 'floatUnread': _floatsUnread(image),
  };
});

/// `scanNan`: every NaN and infinity in the frame's outputs, by pass.
///
/// [parameters]: `pass` (optional; one pass rather than all), `first` (how
/// many coordinates to name per output; eight by default).
///
/// Only a texture's floats can hold a NaN, and only a backend that keeps
/// floats can hand them back. An eight-bit output cannot hold one and is
/// counted as such; a float output this backend read back as eight bits is
/// listed under `unread` with the reason, rather than reported clean — a
/// NaN clamps to an ordinary byte on the way, and "no NaN found" would be a
/// claim nothing checked.
Map<String, Object?> renderScanNan(
  FrameCapture capture,
  Map<String, String> parameters,
) => _answering(() {
  final first = int.tryParse(parameters['first'] ?? '') ?? 8;
  final passes = switch (parameters['pass']) {
    final key? => <(int, CapturedPass)>[_passFor(capture, key)],
    null => capture.passes.indexed.toList(),
  };
  final outputs = <(int, CapturedPass, CapturedImage)>[
    for (final (index, pass) in passes)
      for (final image in pass.images) (index, pass, image),
  ];
  final scanned = <(int, CapturedPass, CapturedImage, _Hits)>[
    for (final (index, pass, image) in outputs)
      if (image.floats case final floats?)
        (index, pass, image, _scan(image, floats, first)),
  ];
  return <String, Object?>{
    'clean': scanned.every((s) => s.$4.total == 0),
    'scanned': scanned.length,
    'eightBit': outputs
        .where(
          (o) =>
              o.$3.floats == null &&
              o.$3.pixels != null &&
              !_holdsFloats(o.$3.format),
        )
        .length,
    'found': <Map<String, Object?>>[
      for (final (index, pass, image, hits) in scanned)
        if (hits.total > 0)
          <String, Object?>{
            'passIndex': index,
            'pass': pass.name,
            'resource': image.resource,
            'nan': hits.nan,
            'infinite': hits.infinite,
            'first': hits.first,
          },
    ],
    'unread': <Map<String, Object?>>[
      for (final (index, pass, image) in outputs)
        if (image.floats == null &&
            (image.pixels == null || _holdsFloats(image.format)))
          <String, Object?>{
            'passIndex': index,
            'pass': pass.name,
            'resource': image.resource,
            'format': image.format.name,
            'why': image.refused ?? _floatsUnread(image),
          },
    ],
  };
});

/// `stats`: what the frame cost and what it held.
///
/// `targetBytes` sums each named resource once, at its captured size and
/// format; a pooled texture two names share is counted under both, and a
/// format whose size this does not know is listed in `unsizedFormats` rather
/// than guessed.
Map<String, Object?> renderStats(FrameCapture capture) {
  final targets = <String, CapturedImage>{
    for (final pass in capture.passes)
      for (final image in pass.images)
        if (image.width > 0 && image.height > 0) image.resource: image,
  };
  final sized = <Map<String, Object?>>[
    for (final image in targets.values)
      <String, Object?>{
        'resource': image.resource,
        'width': image.width,
        'height': image.height,
        'format': image.format.name,
        'bytes': switch (_bytesPerPixel(image.format)) {
          final int b => b * image.width * image.height,
          null => null,
        },
      },
  ];
  return <String, Object?>{
    'width': capture.width,
    'height': capture.height,
    'passes': capture.passes.length,
    'activePasses': capture.passes.where((p) => p.active).length,
    'drawCalls': capture.passes.fold<int>(0, (s, p) => s + p.drawCalls),
    'describedDraws': capture.draws.length,
    'triangles': capture.passes.fold<int>(0, (s, p) => s + p.triangles),
    'cpuMicros': capture.passes.fold<int>(0, (s, p) => s + p.micros),
    'targetBytes': sized.fold<int>(
      0,
      (s, t) => s + ((t['bytes'] as int?) ?? 0),
    ),
    'targets': sized,
    'unsizedFormats': <String>{
      for (final t in sized)
        if (t['bytes'] == null) t['format']! as String,
    }.toList(),
  };
}

/// `capture`: the whole frame as a capture file — `A5.23` — the JSON
/// `FrameCapture.toJson` writes, for a bug report or the editor's
/// `capture_open`.
///
/// [parameters]: `thumbnail` (the longer side of each image's thumbnail in
/// pixels, 128 when absent), `images` (`true` to keep every image whole as
/// well), `floats` (`true` to keep float targets' own values), `notes`
/// (free text written into the file).
Map<String, Object?> renderCaptureFile(
  FrameCapture capture,
  Map<String, String> parameters,
) => _answering(() {
  final size = switch (parameters['thumbnail']) {
    null => 128,
    final given => int.tryParse(given),
  };
  if (size == null || size < 1) {
    throw _Refusal(
      'thumbnail is the longer side of a thumbnail in whole pixels, one or '
      'more; leave it out for 128',
    );
  }
  return <String, Object?>{
    'capture': capture.toJson(
      thumbnailSize: size,
      images: parameters['images'] == 'true',
      floats: parameters['floats'] == 'true',
      notes: parameters['notes'],
    ),
  };
});

/// `memory`: what the renderer holds on the device, by category — `A5.24`,
/// [Renderer.memoryReport] as JSON.
Map<String, Object?> renderMemory(MemoryReport report) => report.toJson();

/// `debugViews`: every debug view by name, kind and what it shows —
/// `A5.21`, the registry a tool picks a channel from.
Map<String, Object?> renderDebugViews() => <String, Object?>{
  'views': <Map<String, Object?>>[
    for (final view in DebugView.values) view.toJson(),
  ],
  'wipeSides': <String>[for (final side in DebugWipeSide.values) side.name],
};

/// Raised inside a function here and answered at its edge by [_answering],
/// so a helper several calls down can refuse without every caller between
/// passing the refusal along by hand. Never escapes this file.
final class _Refusal implements Exception {
  const _Refusal(this.why);
  final String why;
}

Map<String, Object?> _answering(Map<String, Object?> Function() body) {
  try {
    return body();
  } on _Refusal catch (refused) {
    return refusal(refused.why);
  }
}

Map<String, Object?> _describeImage(CapturedImage image) => <String, Object?>{
  'resource': image.resource,
  'width': image.width,
  'height': image.height,
  'format': image.format.name,
  'readable': image.pixels != null,
  'floats': image.floats != null,
  if (image.refused != null) 'refused': image.refused,
};

/// The pass [key] names — an index or a name — with its index.
(int, CapturedPass) _passFor(FrameCapture capture, String key) {
  final names = capture.passes.map((p) => p.name).join(', ');
  if (int.tryParse(key) case final index?) {
    if (index >= 0 && index < capture.passes.length) {
      return (index, capture.passes[index]);
    }
    throw _Refusal(
      'there is no pass $index: this frame ran ${capture.passes.length}, '
      'numbered 0 to ${capture.passes.length - 1} ($names)',
    );
  }
  final index = capture.passes.indexWhere((p) => p.name == key);
  if (index >= 0) return (index, capture.passes[index]);
  throw _Refusal('no pass is called "$key"; this frame ran $names');
}

/// The output [parameters] name, as `pass` and `resource`.
(CapturedPass, CapturedImage) _imageFor(
  FrameCapture capture,
  Map<String, String> parameters,
) {
  final key = parameters['pass'];
  if (key == null) {
    throw const _Refusal('name a pass, by index or by name, as `pass`');
  }
  final (_, pass) = _passFor(capture, key);
  if (pass.images.isEmpty) {
    throw _Refusal(
      'pass "${pass.name}" wrote and kept nothing this frame'
      '${pass.active ? '' : ' — it was inactive'}',
    );
  }
  final resource = parameters['resource'];
  if (resource == null) return (pass, pass.images.first);
  final image = pass.imageOf(resource);
  if (image == null) {
    throw _Refusal(
      'pass "${pass.name}" has no output "$resource"; it wrote '
      '${pass.images.map((i) => i.resource).join(', ')}',
    );
  }
  return (pass, image);
}

/// The floats at ([x], [y]), as many channels as the texture keeps a pixel.
List<double>? _floatsAt(CapturedImage image, int x, int y) {
  final floats = image.floats;
  if (floats == null) return null;
  final channels = _channelsOf(image, floats);
  if (channels == 0) return null;
  final at = (y * image.width + x) * channels;
  return floats.sublist(at, at + channels);
}

int _channelsOf(CapturedImage image, Float32List floats) {
  final pixels = image.width * image.height;
  return pixels == 0 ? 0 : floats.length ~/ pixels;
}

typedef _Hits = ({
  int nan,
  int infinite,
  int total,
  List<Map<String, Object?>> first,
});

_Hits _scan(CapturedImage image, Float32List floats, int first) {
  final channels = _channelsOf(image, floats);
  final bad = <int>[
    for (var i = 0; i < image.width * image.height * channels; i++)
      if (!floats[i].isFinite) i,
  ];
  final nan = bad.where((i) => floats[i].isNaN).length;
  return (
    nan: nan,
    infinite: bad.length - nan,
    total: bad.length,
    first: <Map<String, Object?>>[
      for (final i in bad.take(first))
        <String, Object?>{
          'x': (i ~/ channels) % image.width,
          'y': (i ~/ channels) ~/ image.width,
          'channel': i % channels,
          'value': _number(floats[i]),
        },
    ],
  );
}

String _floatsUnread(CapturedImage image) => _holdsFloats(image.format)
    ? 'this backend reads ${image.format.name} back as eight bits a '
          'channel, and a NaN clamps to an ordinary byte on the way; run '
          'the frame on the software backend to read its floats'
    : '${image.format.name} holds no floats to read';

bool _holdsFloats(TextureFormat format) => switch (format) {
  TextureFormat.r32g32b32a32Float ||
  TextureFormat.r16g16b16a16Float ||
  TextureFormat.r32Float ||
  TextureFormat.d32FloatS8UInt => true,
  _ => false,
};

int? _bytesPerPixel(TextureFormat format) => switch (format) {
  TextureFormat.a8UNormInt ||
  TextureFormat.r8UNormInt ||
  TextureFormat.s8UInt => 1,
  TextureFormat.r8g8UNormInt => 2,
  TextureFormat.r8g8b8a8UNormInt ||
  TextureFormat.r8g8b8a8UNormIntSRGB ||
  TextureFormat.b8g8r8a8UNormInt ||
  TextureFormat.b8g8r8a8UNormIntSRGB ||
  TextureFormat.r32Float ||
  TextureFormat.d24UnormS8Uint => 4,
  TextureFormat.r16g16b16a16Float || TextureFormat.d32FloatS8UInt => 8,
  TextureFormat.r32g32b32a32Float => 16,
  _ => null,
};

/// [v] as JSON can carry it: a number, or the name of one JSON has not got.
Object _number(double v) => v.isNaN
    ? 'NaN'
    : v == double.infinity
    ? 'Infinity'
    : v == double.negativeInfinity
    ? '-Infinity'
    : v;
