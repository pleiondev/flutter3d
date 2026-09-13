/// [bakeTextureGraph]/[bakeTextureFull]: `mat-11`'s own CPU compositor —
/// a `TextureGraph` (`mat-10`) evaluated node by node, in linear light, to
/// plain RGBA8.
///
/// **Everything composites in linear space.** A PNG's own bytes are
/// gamma-encoded (sRGB) so a display shows them evenly; averaging two
/// gamma-encoded values (a `Blend`, a resample) is not the same operation as
/// averaging the light they actually stand for, and the difference shows up
/// as a picture darker at the seam than either side of it. [_ImageTextureNode]
/// decodes through the sRGB EOTF on the way in; the top-level bake functions
/// encode back through it on the way out. A directly authored constant — a
/// [ColorTextureNode]'s own `value`, a [CheckerTextureNode]'s two colours —
/// is read as linear already, the same choice a shader uniform makes over a
/// texture sample.
///
/// **Cached by structural hash, not by node id.** [_structuralKey] folds a
/// node's own `toJson()` together with every input it reads, recursively, so
/// two nodes — in this graph or a later edit of it — with the same kind, the
/// same fields and the same *inputs* share one bake. Editing a `Blend`
/// node's own `factor` changes only that node's own key; its `Image` inputs
/// keep theirs, are found in [TextureBakeCache] unchanged, and are never
/// redecoded — the row's own second acceptance line, and the reason a cache
/// has to be handed in rather than built fresh every call.
///
/// **No `Random` anywhere.** [NoiseTextureNode]'s own value is a hash of its
/// lattice coordinates and [NoiseTextureNode.seed], not a seeded generator's
/// next value — `dart:math`'s `Random` promises the same seed gives the same
/// stream *within one SDK build*, not that it always will, and "two runs
/// byte-identical" is the row's own first acceptance line.
///
/// **Full resolution runs off this isolate when one exists** — the same
/// bargain `editInIsolate` already strikes for a modifier bake in this same
/// package's own `job.dart`, copied rather than shared: that helper crosses
/// an `EditMesh`, and this crosses a `TextureGraph`'s JSON and the source
/// images' own bytes, different enough values that sharing the function
/// would mean generalising it for one caller.
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart' show decodePng;

import 'texture_graph.dart';

/// Whether this build has no isolates — `dart:isolate` compiles for the web
/// as a stub, the same fact `flutter3d_mesh/src/isolate.dart`'s own
/// `meshWorkStaysHere` is named for, copied here rather than imported since
/// `flutter3d_mesh` does not export it: a plain-Dart package cannot ask
/// Flutter's `kIsWeb`, so this is the question underneath it.
const bool _bakeStaysHere = bool.fromEnvironment('dart.library.js_interop');

/// A structural-hash-keyed memo of already-baked node rasters, reused across
/// calls to [bakeTextureGraph] and [bakeTextureFull] — the object a caller
/// keeps alive across edits so an unchanged `Image` node is never redecoded.
/// Empty and inert until a bake fills it.
final class TextureBakeCache {
  final Map<String, _Raster> _byKey = <String, _Raster>{};

  /// Drops everything — a project closed, an image replaced under an id the
  /// structural key cannot see (it hashes the id, not the bytes behind it).
  void clear() => _byKey.clear();
}

/// [graph]'s own [outputNodeId] node, baked at [size]×[size] and written out
/// as plain RGBA8 — `mat-10`'s `TextureGraph` finally able to answer in
/// pixels. Null when [graph] does not [TextureGraph.validate] clean, or
/// [outputNodeId] names nothing in it.
///
/// The chunked half of the row's own "предпросмотр 256² чанками": the final
/// linear-to-sRGB pass below writes [size] rows at a time rather than the
/// whole buffer in one pass, which is also where a caller wanting progress
/// would hook in — nothing here reports it, since nothing yet asks for one.
Uint8List? bakeTextureGraph(
  TextureGraph graph,
  int outputNodeId,
  Map<int, Uint8List> images, {
  int size = 256,
  TextureBakeCache? cache,
}) => _bake(graph, outputNodeId, images, size, cache ?? TextureBakeCache());

/// The same bake as [bakeTextureGraph], at a size meant for export rather
/// than a panel's own thumbnail, run off this isolate when one exists.
///
/// **What crosses is [graph]'s own JSON and [images], both plain values —
/// no live `TextureGraph`, no `ModelProject`.** `Isolate.run`'s own closure
/// carries whatever it captures, so capturing a decoded, mutable value would
/// be the copy the byte format in `flutter3d_mesh/src/isolate.dart` exists
/// to avoid; `graph.toJson()` and a `Map<int, Uint8List>` are already the
/// plain shape a message can hold as-is.
Future<Uint8List?> bakeTextureFull(
  TextureGraph graph,
  int outputNodeId,
  Map<int, Uint8List> images, {
  int size = 2048,
}) async {
  final graphJson = graph.toJson();
  if (_bakeStaysHere) {
    return _bakeFromJson(graphJson, outputNodeId, images, size);
  }
  return Isolate.run(
    () => _bakeFromJson(graphJson, outputNodeId, images, size),
  );
}

/// The other side of [bakeTextureFull]'s isolate boundary — rebuilds the
/// graph from JSON and runs the same bake a synchronous call would. Top-level
/// rather than a closure over [bakeTextureFull]'s own locals, so what
/// `Isolate.run` actually sends is this function and the plain values passed
/// to it, not a closure captured over a `TextureGraph`.
Uint8List? _bakeFromJson(
  Map<String, Object?> graphJson,
  int outputNodeId,
  Map<int, Uint8List> images,
  int size,
) => _bake(
  TextureGraph.fromJson(graphJson),
  outputNodeId,
  images,
  size,
  TextureBakeCache(),
);

Uint8List? _bake(
  TextureGraph graph,
  int outputNodeId,
  Map<int, Uint8List> images,
  int size,
  TextureBakeCache cache,
) {
  if (graph.validate().isNotEmpty) return null;
  final node = graph.nodeById(outputNodeId);
  if (node == null) return null;

  final raster = _evaluate(graph, node, images, size, cache);
  final rgba = Uint8List(size * size * 4);
  const rowsPerChunk = 32;
  for (var chunkStart = 0; chunkStart < size; chunkStart += rowsPerChunk) {
    final chunkEnd = (chunkStart + rowsPerChunk).clamp(0, size);
    for (var y = chunkStart; y < chunkEnd; y++) {
      for (var x = 0; x < size; x++) {
        final out = (y * size + x) * 4;
        if (raster.channels == 1) {
          final v = _toByte(_linearToSrgb(raster.at(x, y, 0)));
          rgba[out] = v;
          rgba[out + 1] = v;
          rgba[out + 2] = v;
          rgba[out + 3] = 255;
        } else {
          rgba[out] = _toByte(_linearToSrgb(raster.at(x, y, 0)));
          rgba[out + 1] = _toByte(_linearToSrgb(raster.at(x, y, 1)));
          rgba[out + 2] = _toByte(_linearToSrgb(raster.at(x, y, 2)));
          rgba[out + 3] = _toByte(
            raster.at(x, y, 3),
          ); // alpha is already linear
        }
      }
    }
  }
  return rgba;
}

int _toByte(double v) => (v.clamp(0.0, 1.0) * 255).round();

double _srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _linearToSrgb(double c) => c <= 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(c.clamp(0.0, 1.0), 1 / 2.4).toDouble() - 0.055;

/// One node's own baked answer: [channels] of 1 (a mask) or 4 (RGBA, alpha
/// already linear), [size]×[size], row-major.
final class _Raster {
  _Raster(this.size, this.channels)
    : data = Float32List(size * size * channels);

  final int size;
  final int channels;
  final Float32List data;

  double at(int x, int y, int channel) =>
      data[(y * size + x) * channels + channel];

  void set(int x, int y, int channel, double value) =>
      data[(y * size + x) * channels + channel] = value;

  void fill(List<double> value) {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        for (var c = 0; c < channels; c++) {
          set(x, y, c, value[c]);
        }
      }
    }
  }
}

_Raster _blankColor(int size) => _Raster(size, 4); // (0,0,0,0): nothing wired
_Raster _blankScalar(int size) => _Raster(size, 1);

/// [node]'s own baked raster, memoized in [cache] by [_structuralKey] —
/// every recursive call below goes through this, never straight to a node
/// kind's own `_eval*`, so a shared subtree is only ever baked once per
/// bake, cache hit or not.
_Raster _evaluate(
  TextureGraph graph,
  TextureNode node,
  Map<int, Uint8List> images,
  int size,
  TextureBakeCache cache,
) {
  final key = '${_structuralKey(graph, node.id)}@$size';
  final cached = cache._byKey[key];
  if (cached != null) return cached;

  _Raster colorInput(String name) {
    final from = node.inputs[name]!.from;
    if (from == null) return _blankColor(size);
    return _evaluate(graph, graph.nodeById(from)!, images, size, cache);
  }

  _Raster scalarInput(String name) {
    final from = node.inputs[name]!.from;
    if (from == null) return _blankScalar(size);
    return _evaluate(graph, graph.nodeById(from)!, images, size, cache);
  }

  final raster = switch (node) {
    ImageTextureNode() => _evalImage(node, images, size),
    ColorTextureNode() => _evalColor(node, size),
    BlendTextureNode() => _evalBlend(
      node,
      colorInput('base'),
      colorInput('overlay'),
      size,
    ),
    ChannelsTextureNode() => _evalChannels(node, colorInput('source'), size),
    LevelsTextureNode() => _evalLevels(node, scalarInput('source'), size),
    InvertTextureNode() => _evalInvert(scalarInput('source'), size),
    UvTransformTextureNode() => _evalUvTransform(
      node,
      colorInput('source'),
      size,
    ),
    CheckerTextureNode() => _evalChecker(node, size),
    NoiseTextureNode() => _evalNoise(node, size),
    NormalFromHeightTextureNode() => _evalNormalFromHeight(
      node,
      scalarInput('height'),
      size,
    ),
    OutputTextureNode() => colorInput('result'),
  };
  cache._byKey[key] = raster;
  return raster;
}

/// A key that is the same for two nodes exactly when a bake of one would
/// answer the same raster as a bake of the other: this node's own kind and
/// fields (`toJson`, which already excludes [TextureNode.id]), then every
/// input it reads, by the same key rather than by the id wired to it — an
/// id renumbered by an edit elsewhere in the graph must not read as a
/// different node when nothing about *this* one changed.
String _structuralKey(TextureGraph graph, int nodeId) {
  final node = graph.nodeById(nodeId)!;
  final inputKeys = <String>[
    for (final entry in node.inputs.entries)
      if (entry.value.from != null)
        '${entry.key}=${_structuralKey(graph, entry.value.from!)}'
      else
        '${entry.key}=∅',
  ]..sort();
  return '${node.kind}(${_jsonKey(node.toJson())})[${inputKeys.join(',')}]';
}

/// A deterministic string for a `toJson()` map — sorted keys, since a
/// `Map<String, Object?>` literal's own insertion order is an implementation
/// detail of the node class that wrote it, not something two equal nodes are
/// guaranteed to agree on.
String _jsonKey(Map<String, Object?> json) {
  final keys = json.keys.toList()..sort();
  return keys.map((k) => '$k:${json[k]}').join(',');
}

_Raster _evalImage(
  ImageTextureNode node,
  Map<int, Uint8List> images,
  int size,
) {
  final raster = _Raster(size, 4);
  final bytes = images[node.imageId];
  final decoded = bytes == null ? null : decodePng(bytes);
  if (decoded == null) {
    raster.fill(const <double>[
      0.5,
      0.5,
      0.5,
      1.0,
    ]); // a flagged, not a hidden, gap
    return raster;
  }
  for (var y = 0; y < size; y++) {
    final sy = (y * decoded.height ~/ size).clamp(0, decoded.height - 1);
    for (var x = 0; x < size; x++) {
      final sx = (x * decoded.width ~/ size).clamp(0, decoded.width - 1);
      final at = (sy * decoded.width + sx) * 4;
      raster.set(x, y, 0, _srgbToLinear(decoded.rgba[at] / 255));
      raster.set(x, y, 1, _srgbToLinear(decoded.rgba[at + 1] / 255));
      raster.set(x, y, 2, _srgbToLinear(decoded.rgba[at + 2] / 255));
      raster.set(
        x,
        y,
        3,
        decoded.rgba[at + 3] / 255,
      ); // alpha is already linear
    }
  }
  return raster;
}

_Raster _evalColor(ColorTextureNode node, int size) {
  final raster = _Raster(size, 4);
  raster.fill(<double>[node.value.x, node.value.y, node.value.z, node.value.w]);
  return raster;
}

double _blendOne(TextureBlendMode mode, double base, double overlay) =>
    switch (mode) {
      TextureBlendMode.normal => overlay,
      TextureBlendMode.multiply => base * overlay,
      TextureBlendMode.add => base + overlay,
      TextureBlendMode.screen => 1 - (1 - base) * (1 - overlay),
    };

_Raster _evalBlend(
  BlendTextureNode node,
  _Raster base,
  _Raster overlay,
  int size,
) {
  final raster = _Raster(size, 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      for (var c = 0; c < 3; c++) {
        final b = base.at(x, y, c);
        final o = overlay.at(x, y, c);
        final blended = _blendOne(node.mode, b, o);
        raster.set(x, y, c, b + (blended - b) * node.factor);
      }
      final ba = base.at(x, y, 3);
      final oa = overlay.at(x, y, 3);
      raster.set(x, y, 3, ba + (oa - ba) * node.factor);
    }
  }
  return raster;
}

_Raster _evalChannels(ChannelsTextureNode node, _Raster source, int size) {
  final raster = _Raster(size, 1);
  final channel = switch (node.channel) {
    TextureChannel.r => 0,
    TextureChannel.g => 1,
    TextureChannel.b => 2,
    TextureChannel.a => 3,
  };
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      raster.set(x, y, 0, source.at(x, y, channel));
    }
  }
  return raster;
}

_Raster _evalLevels(LevelsTextureNode node, _Raster source, int size) {
  final raster = _Raster(size, 1);
  final range = node.whitePoint - node.blackPoint;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var v = source.at(x, y, 0);
      v = range == 0 ? 0 : ((v - node.blackPoint) / range).clamp(0.0, 1.0);
      v = math.pow(v, 1 / node.gamma).toDouble();
      raster.set(x, y, 0, v);
    }
  }
  return raster;
}

_Raster _evalInvert(_Raster source, int size) {
  final raster = _Raster(size, 1);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      raster.set(x, y, 0, 1 - source.at(x, y, 0));
    }
  }
  return raster;
}

_Raster _evalUvTransform(
  UvTransformTextureNode node,
  _Raster source,
  int size,
) {
  final raster = _Raster(size, 4);
  final cosR = math.cos(node.rotation);
  final sinR = math.sin(node.rotation);
  for (var y = 0; y < size; y++) {
    final v = (y + 0.5) / size;
    for (var x = 0; x < size; x++) {
      final u = (x + 0.5) / size;
      // The inverse of offset-then-scale-then-rotate, so sampling at the
      // transformed UV shows the source moved, scaled and turned the way
      // the forward transform names it, not its own inverse.
      var su = u - node.offset.x;
      var sv = v - node.offset.y;
      su /= node.scale.x == 0 ? 1 : node.scale.x;
      sv /= node.scale.y == 0 ? 1 : node.scale.y;
      final ru = su * cosR + sv * sinR;
      final rv = -su * sinR + sv * cosR;
      final sx = (_wrap(ru) * size).floor().clamp(0, size - 1);
      final sy = (_wrap(rv) * size).floor().clamp(0, size - 1);
      for (var c = 0; c < 4; c++) {
        raster.set(x, y, c, source.at(sx, sy, c));
      }
    }
  }
  return raster;
}

/// [v] wrapped into 0–1 — a texture tiles rather than clamping at its own
/// edge, the ordinary behaviour a sampler falls back to with no wrap mode
/// named.
double _wrap(double v) => v - v.floor();

_Raster _evalChecker(CheckerTextureNode node, int size) {
  final raster = _Raster(size, 4);
  for (var y = 0; y < size; y++) {
    final v = (y + 0.5) / size;
    for (var x = 0; x < size; x++) {
      final u = (x + 0.5) / size;
      final cell = (u * node.scale).floor() + (v * node.scale).floor();
      final color = cell.isEven ? node.colorA : node.colorB;
      raster.set(x, y, 0, color.x);
      raster.set(x, y, 1, color.y);
      raster.set(x, y, 2, color.z);
      raster.set(x, y, 3, color.w);
    }
  }
  return raster;
}

/// A deterministic value noise: each integer lattice point gets a
/// pseudo-random value from [_hash] — a fixed, portable mix of its own
/// coordinates and [seed], never `dart:math`'s `Random` — and a queried
/// point is the bilinear blend of the four lattice points around it, smoothed
/// by a cubic ease so the result has no visible grid at the lattice itself.
double _valueNoise(double x, double y, int seed) {
  final x0 = x.floor();
  final y0 = y.floor();
  final fx = _smooth(x - x0);
  final fy = _smooth(y - y0);
  final v00 = _hash(x0, y0, seed);
  final v10 = _hash(x0 + 1, y0, seed);
  final v01 = _hash(x0, y0 + 1, seed);
  final v11 = _hash(x0 + 1, y0 + 1, seed);
  final top = v00 + (v10 - v00) * fx;
  final bottom = v01 + (v11 - v01) * fx;
  return top + (bottom - top) * fy;
}

double _smooth(double t) => t * t * (3 - 2 * t);

/// [ix]/[iy]/[seed] mixed into 0–1 — a 32-bit multiplicative hash, the same
/// shape every deterministic lattice noise in a shader uses, chosen because
/// it is a handful of integer operations rather than a generator's own
/// internal state a future Dart release is free to change.
double _hash(int ix, int iy, int seed) {
  var h = (ix * 0x27d4eb2d) ^ (iy * 0x165667b1) ^ (seed * 0x9e3779b9);
  h = (h ^ (h >> 15)) & 0xFFFFFFFF;
  h = (h * 0x85ebca6b) & 0xFFFFFFFF;
  h = (h ^ (h >> 13)) & 0xFFFFFFFF;
  return (h & 0xFFFFFF) / 0xFFFFFF;
}

_Raster _evalNoise(NoiseTextureNode node, int size) {
  final raster = _Raster(size, 1);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final u = x / size * node.scale;
      final v = y / size * node.scale;
      raster.set(x, y, 0, _valueNoise(u, v, node.seed));
    }
  }
  return raster;
}

_Raster _evalNormalFromHeight(
  NormalFromHeightTextureNode node,
  _Raster height,
  int size,
) {
  final raster = _Raster(size, 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final left = height.at((x - 1).clamp(0, size - 1), y, 0);
      final right = height.at((x + 1).clamp(0, size - 1), y, 0);
      final up = height.at(x, (y - 1).clamp(0, size - 1), 0);
      final down = height.at(x, (y + 1).clamp(0, size - 1), 0);
      final dx = (right - left) * node.strength;
      final dy = (down - up) * node.strength;
      final length = math.sqrt(dx * dx + dy * dy + 1);
      raster.set(x, y, 0, (-dx / length) * 0.5 + 0.5);
      raster.set(x, y, 1, (-dy / length) * 0.5 + 0.5);
      raster.set(x, y, 2, (1 / length) * 0.5 + 0.5);
      raster.set(x, y, 3, 1.0);
    }
  }
  return raster;
}
