/// [TextureGraph]: an immutable network of fixed-kind nodes describing how
/// one texture is composed — `mat-10`'s own "компоновщик текстур," a fixed
/// set of nodes that bakes into a texture slot, not a shader graph (Ж1,
/// closed 2026-09-09 — see `ROADMAP.md`'s "Not doing: Node-graph
/// materials").
///
/// **Eleven kinds and no others.** `Image`, `Color`, `Blend`, `Channels`,
/// `Levels`, `Invert`, `UvTransform`, `Checker`, `Noise`, `NormalFromHeight`
/// and `Output` — the plan's own list — each a sealed [TextureNode]
/// subclass. A shader-graph feature request has a wall to hit here: adding
/// a twelfth kind means a new `final class` and a compiler-checked switch
/// arm everywhere one exists, not a string a node's own JSON happens to
/// carry.
///
/// **Two socket types, not one per node kind.** [TextureValueType.color] is
/// four channels — what a texture slot samples — and
/// [TextureValueType.scalar] is one — a mask or a height on its way toward
/// becoming one. `Channels` is the one node that turns a `color` into a
/// `scalar` and `NormalFromHeight` is the one that turns a `scalar` back
/// into a `color`; everything else keeps whichever type it already has.
/// [TextureGraph.validate] reads this off every node's own [TextureNode.inputs]
/// without touching a pixel, which is what "тип входа проверен" (an input's
/// type is checked) asks for — no baking is needed to catch a `Blend` fed a
/// mask where a colour belongs.
///
/// **What this file does not do.** Baking a graph to actual pixels is
/// `mat-11`, which needs `mat-09n`'s pure-Dart image decoder first — neither
/// exists yet, and nothing here reads `project.images`' own bytes. `AddNode`,
/// `Link`, `Unlink`, `SetNodeField` and `MoveNode` — the commands a panel
/// would call — are `mat-13`'s own row, named there and not here, since this
/// row's acceptance is the data shape and its two checks, not the editing
/// verbs over it.
library;

import 'package:flutter3d_core/formats.dart';
import 'package:vector_math/vector_math.dart';

/// What one socket on a [TextureNode] carries.
enum TextureValueType {
  /// Four channels, 0..1 each — what a texture slot samples, and what
  /// [TextureGraph]'s own [OutputTextureNode] always takes.
  color,

  /// One channel, 0..1 — a mask or a height, never sampled on its own.
  scalar,
}

/// One thing [TextureGraph.validate] found wrong, named by the node it is
/// about.
final class TextureGraphIssue {
  const TextureGraphIssue(this.nodeId, this.message);

  /// The node this is about. Always one of [TextureGraph.nodes]' own ids —
  /// a dangling reference is reported on the node whose input names it, not
  /// on the id that does not exist.
  final int nodeId;

  final String message;

  @override
  String toString() => 'node $nodeId: $message';
}

/// One input socket's own declared type and, if [from] is not null, which
/// node is wired into it.
typedef TextureInputSocket = ({TextureValueType type, int? from});

/// One node in a [TextureGraph]. Sealed — see the library comment for why
/// eleven kinds and no others.
sealed class TextureNode {
  const TextureNode({required this.id});

  /// Stable within one [TextureGraph], the way `ModelObject.id` is stable
  /// within one `ModelProject` — an input names the node it reads by this,
  /// not by a position in [TextureGraph.nodes] that a reorder would move.
  final int id;

  /// What a link out of this node promises whatever it feeds.
  TextureValueType get outputType;

  /// This node's own input sockets, by name: the type a link into it must
  /// match, and the node id currently wired there, or null for nothing yet.
  /// A node with no inputs — [ImageTextureNode], [ColorTextureNode],
  /// [CheckerTextureNode], [NoiseTextureNode] — answers the empty map.
  Map<String, TextureInputSocket> get inputs;

  /// A control for every field a panel would show, keyed by field name —
  /// the same shape `builtInMaterialHints` already answers for
  /// `SurfaceMaterial`, reused rather than duplicated in a new hierarchy of
  /// its own.
  Map<String, MaterialHint> get hints;

  /// The word this kind writes to [toJson] and is read back by in
  /// [TextureNode.fromJson]'s own switch.
  String get kind;

  /// This node's own fields, as JSON — everything but [id] and [kind],
  /// which [TextureGraph.toJson] writes once, the same way, for every node.
  Map<String, Object?> toJson();

  /// The node [json] describes — `json['kind']` and `json['id']` read here,
  /// every other field read by the matching subclass's own reader.
  ///
  /// Throws a [FormatException] naming the id and the bad field, rather than
  /// answering a node the graph would misbehave on: a `Blend` with no `mode`
  /// is not "a `Blend` with a default mode," it is a file this build cannot
  /// honestly say it read.
  static TextureNode fromJson(Map<String, Object?> json) {
    final id = switch (json['id']) {
      final int value => value,
      _ => throw const FormatException('a texture node with no integer id'),
    };
    final kind = switch (json['kind']) {
      final String value => value,
      _ => throw FormatException('texture node $id has no string kind'),
    };
    return switch (kind) {
      'image' => ImageTextureNode(id: id, imageId: _int(json, id, 'imageId')),
      'color' => ColorTextureNode(id: id, value: _vec4(json, id, 'value')),
      'blend' => BlendTextureNode(
        id: id,
        base: _optionalInt(json, 'base'),
        overlay: _optionalInt(json, 'overlay'),
        mode: _enum(TextureBlendMode.values, json, id, 'mode'),
        factor: _double(json, id, 'factor'),
      ),
      'channels' => ChannelsTextureNode(
        id: id,
        source: _optionalInt(json, 'source'),
        channel: _enum(TextureChannel.values, json, id, 'channel'),
      ),
      'levels' => LevelsTextureNode(
        id: id,
        source: _optionalInt(json, 'source'),
        blackPoint: _double(json, id, 'blackPoint'),
        whitePoint: _double(json, id, 'whitePoint'),
        gamma: _double(json, id, 'gamma'),
      ),
      'invert' => InvertTextureNode(
        id: id,
        source: _optionalInt(json, 'source'),
      ),
      'uvTransform' => UvTransformTextureNode(
        id: id,
        source: _optionalInt(json, 'source'),
        offset: _vec2(json, id, 'offset'),
        scale: _vec2(json, id, 'scale'),
        rotation: _double(json, id, 'rotation'),
      ),
      'checker' => CheckerTextureNode(
        id: id,
        colorA: _vec4(json, id, 'colorA'),
        colorB: _vec4(json, id, 'colorB'),
        scale: _double(json, id, 'scale'),
      ),
      'noise' => NoiseTextureNode(
        id: id,
        seed: _int(json, id, 'seed'),
        scale: _double(json, id, 'scale'),
      ),
      'normalFromHeight' => NormalFromHeightTextureNode(
        id: id,
        height: _optionalInt(json, 'height'),
        strength: _double(json, id, 'strength'),
      ),
      'output' => OutputTextureNode(
        id: id,
        result: _optionalInt(json, 'result'),
        slot: json['slot'] as String?,
      ),
      _ => throw FormatException(
        'texture node $id has an unknown kind '
        '"$kind"',
      ),
    };
  }
}

int _int(Map<String, Object?> json, int id, String field) =>
    switch (json[field]) {
      final int value => value,
      _ => throw FormatException('texture node $id has no integer "$field"'),
    };

int? _optionalInt(Map<String, Object?> json, String field) =>
    switch (json[field]) {
      final int value => value,
      _ => null,
    };

double _double(Map<String, Object?> json, int id, String field) =>
    switch (json[field]) {
      final num value => value.toDouble(),
      _ => throw FormatException('texture node $id has no number "$field"'),
    };

Vector4 _vec4(Map<String, Object?> json, int id, String field) =>
    switch (json[field]) {
      final List<Object?> value when value.length == 4 => Vector4(
        (value[0]! as num).toDouble(),
        (value[1]! as num).toDouble(),
        (value[2]! as num).toDouble(),
        (value[3]! as num).toDouble(),
      ),
      _ => throw FormatException(
        'texture node $id has no four-number "$field"',
      ),
    };

Vector2 _vec2(Map<String, Object?> json, int id, String field) =>
    switch (json[field]) {
      final List<Object?> value when value.length == 2 => Vector2(
        (value[0]! as num).toDouble(),
        (value[1]! as num).toDouble(),
      ),
      _ => throw FormatException('texture node $id has no two-number "$field"'),
    };

T _enum<T extends Enum>(
  List<T> values,
  Map<String, Object?> json,
  int id,
  String field,
) {
  final word = json[field];
  for (final value in values) {
    if (value.name == word) return value;
  }
  throw FormatException('texture node $id has no "$field" named "$word"');
}

List<double> _vec4Json(Vector4 v) => <double>[v.x, v.y, v.z, v.w];
List<double> _vec2Json(Vector2 v) => <double>[v.x, v.y];

/// A texture, or a solid colour, sampled as-is. No inputs.
final class ImageTextureNode extends TextureNode {
  const ImageTextureNode({required super.id, required this.imageId});

  /// Into `ModelProject.images` — this class does not decode it, the same
  /// boundary `TextureInfo` already keeps in this package.
  final int imageId;

  @override
  TextureValueType get outputType => TextureValueType.color;

  @override
  Map<String, TextureInputSocket> get inputs => const {};

  @override
  Map<String, MaterialHint> get hints => const {
    'imageId': MaterialHint(TextureHint()),
  };

  @override
  String get kind => 'image';

  @override
  Map<String, Object?> toJson() => {'imageId': imageId};
}

/// A flat colour, painted everywhere. No inputs.
final class ColorTextureNode extends TextureNode {
  const ColorTextureNode({required super.id, required this.value});

  final Vector4 value;

  @override
  TextureValueType get outputType => TextureValueType.color;

  @override
  Map<String, TextureInputSocket> get inputs => const {};

  @override
  Map<String, MaterialHint> get hints => const {
    'value': MaterialHint(ColorHint()),
  };

  @override
  String get kind => 'color';

  @override
  Map<String, Object?> toJson() => {'value': _vec4Json(value)};
}

/// How [BlendTextureNode] combines its two colour inputs.
enum TextureBlendMode { normal, multiply, add, screen }

/// Two colours combined by [mode], mixed by [factor].
final class BlendTextureNode extends TextureNode {
  const BlendTextureNode({
    required super.id,
    this.base,
    this.overlay,
    this.mode = TextureBlendMode.normal,
    this.factor = 1.0,
  });

  final int? base;
  final int? overlay;
  final TextureBlendMode mode;

  /// 0 keeps [base] unchanged; 1 is [mode] at full strength.
  final double factor;

  @override
  TextureValueType get outputType => TextureValueType.color;

  @override
  Map<String, TextureInputSocket> get inputs => {
    'base': (type: TextureValueType.color, from: base),
    'overlay': (type: TextureValueType.color, from: overlay),
  };

  @override
  Map<String, MaterialHint> get hints => <String, MaterialHint>{
    'mode': MaterialHint(
      EnumHint(<EnumHintValue>[
        for (final m in TextureBlendMode.values) EnumHintValue(m.name),
      ]),
    ),
    'factor': const MaterialHint(RangeHint(0, 1)),
  };

  @override
  String get kind => 'blend';

  @override
  Map<String, Object?> toJson() => {
    'base': base,
    'overlay': overlay,
    'mode': mode.name,
    'factor': factor,
  };
}

/// One RGBA channel to read out of a colour input.
enum TextureChannel { r, g, b, a }

/// One channel of a colour input, alone, as a mask.
final class ChannelsTextureNode extends TextureNode {
  const ChannelsTextureNode({
    required super.id,
    this.source,
    this.channel = TextureChannel.r,
  });

  final int? source;
  final TextureChannel channel;

  @override
  TextureValueType get outputType => TextureValueType.scalar;

  @override
  Map<String, TextureInputSocket> get inputs => {
    'source': (type: TextureValueType.color, from: source),
  };

  @override
  Map<String, MaterialHint> get hints => {
    'channel': MaterialHint(
      EnumHint(<EnumHintValue>[
        for (final c in TextureChannel.values) EnumHintValue(c.name),
      ]),
    ),
  };

  @override
  String get kind => 'channels';

  @override
  Map<String, Object?> toJson() => {'source': source, 'channel': channel.name};
}

/// A mask remapped between [blackPoint] and [whitePoint], then [gamma].
final class LevelsTextureNode extends TextureNode {
  const LevelsTextureNode({
    required super.id,
    this.source,
    this.blackPoint = 0.0,
    this.whitePoint = 1.0,
    this.gamma = 1.0,
  });

  final int? source;
  final double blackPoint;
  final double whitePoint;
  final double gamma;

  @override
  TextureValueType get outputType => TextureValueType.scalar;

  @override
  Map<String, TextureInputSocket> get inputs => {
    'source': (type: TextureValueType.scalar, from: source),
  };

  @override
  Map<String, MaterialHint> get hints => const {
    'blackPoint': MaterialHint(RangeHint(0, 1)),
    'whitePoint': MaterialHint(RangeHint(0, 1)),
    'gamma': MaterialHint(RangeHint(0.1, 4)),
  };

  @override
  String get kind => 'levels';

  @override
  Map<String, Object?> toJson() => {
    'source': source,
    'blackPoint': blackPoint,
    'whitePoint': whitePoint,
    'gamma': gamma,
  };
}

/// A mask flipped: 1 minus its input.
final class InvertTextureNode extends TextureNode {
  const InvertTextureNode({required super.id, this.source});

  final int? source;

  @override
  TextureValueType get outputType => TextureValueType.scalar;

  @override
  Map<String, TextureInputSocket> get inputs => {
    'source': (type: TextureValueType.scalar, from: source),
  };

  @override
  Map<String, MaterialHint> get hints => const {};

  @override
  String get kind => 'invert';

  @override
  Map<String, Object?> toJson() => {'source': source};
}

/// A colour input resampled at a moved, scaled and turned UV.
final class UvTransformTextureNode extends TextureNode {
  UvTransformTextureNode({
    required super.id,
    this.source,
    Vector2? offset,
    Vector2? scale,
    this.rotation = 0.0,
  }) : offset = offset ?? Vector2(0, 0),
       scale = scale ?? Vector2(1, 1);

  final int? source;
  final Vector2 offset;
  final Vector2 scale;

  /// Radians.
  final double rotation;

  @override
  TextureValueType get outputType => TextureValueType.color;

  @override
  Map<String, TextureInputSocket> get inputs => {
    'source': (type: TextureValueType.color, from: source),
  };

  @override
  Map<String, MaterialHint> get hints => const {
    'rotation': MaterialHint(RangeHint(0, 6.2831853), help: 'radians'),
  };

  @override
  String get kind => 'uvTransform';

  @override
  Map<String, Object?> toJson() => {
    'source': source,
    'offset': _vec2Json(offset),
    'scale': _vec2Json(scale),
    'rotation': rotation,
  };
}

/// A flat two-colour grid, [scale] squares across. No inputs.
final class CheckerTextureNode extends TextureNode {
  CheckerTextureNode({
    required super.id,
    Vector4? colorA,
    Vector4? colorB,
    this.scale = 8.0,
  }) : colorA = colorA ?? Vector4(0, 0, 0, 1),
       colorB = colorB ?? Vector4(1, 1, 1, 1);

  final Vector4 colorA;
  final Vector4 colorB;
  final double scale;

  @override
  TextureValueType get outputType => TextureValueType.color;

  @override
  Map<String, TextureInputSocket> get inputs => const {};

  @override
  Map<String, MaterialHint> get hints => const {
    'colorA': MaterialHint(ColorHint()),
    'colorB': MaterialHint(ColorHint()),
    'scale': MaterialHint(RangeHint(1, 64)),
  };

  @override
  String get kind => 'checker';

  @override
  Map<String, Object?> toJson() => {
    'colorA': _vec4Json(colorA),
    'colorB': _vec4Json(colorB),
    'scale': scale,
  };
}

/// Deterministic noise, by [seed] — never `Random`, the same reason
/// `mat-11`'s own row rules it out for baking. No inputs.
final class NoiseTextureNode extends TextureNode {
  const NoiseTextureNode({required super.id, this.seed = 0, this.scale = 1.0});

  final int seed;
  final double scale;

  @override
  TextureValueType get outputType => TextureValueType.scalar;

  @override
  Map<String, TextureInputSocket> get inputs => const {};

  @override
  Map<String, MaterialHint> get hints => const {
    'scale': MaterialHint(RangeHint(0.01, 64)),
  };

  @override
  String get kind => 'noise';

  @override
  Map<String, Object?> toJson() => {'seed': seed, 'scale': scale};
}

/// A height mask read as a slope and written back as a tangent-space normal.
final class NormalFromHeightTextureNode extends TextureNode {
  const NormalFromHeightTextureNode({
    required super.id,
    this.height,
    this.strength = 1.0,
  });

  final int? height;
  final double strength;

  @override
  TextureValueType get outputType => TextureValueType.color;

  @override
  Map<String, TextureInputSocket> get inputs => {
    'height': (type: TextureValueType.scalar, from: height),
  };

  @override
  Map<String, MaterialHint> get hints => const {
    'strength': MaterialHint(RangeHint(0, 8)),
  };

  @override
  String get kind => 'normalFromHeight';

  @override
  Map<String, Object?> toJson() => {'height': height, 'strength': strength};
}

/// The graph's own result — what `mat-11`'s bake reads. A graph may hold more
/// than one, each naming which material slot it feeds: `mat-12`'s own
/// question, answered by [slot] rather than by this file adding a second way
/// to address a texture slot next to `SetTexture`'s own five names.
final class OutputTextureNode extends TextureNode {
  const OutputTextureNode({required super.id, this.result, this.slot});

  final int? result;

  /// One of `SetTexture`'s own slot names (`albedo`, `normal`,
  /// `metallicRoughness`, `occlusion`, `emissive`), or null for an output not
  /// yet wired to a material — a thumbnail a panel bakes to look at, not to
  /// paint anything with. `BakeTextureGraph` skips an output with no slot and
  /// refuses a graph where none has one.
  final String? slot;

  @override
  TextureValueType get outputType => TextureValueType.color;

  @override
  Map<String, TextureInputSocket> get inputs => {
    'result': (type: TextureValueType.color, from: result),
  };

  @override
  Map<String, MaterialHint> get hints => const {};

  @override
  String get kind => 'output';

  @override
  Map<String, Object?> toJson() => {'result': result, 'slot': slot};
}

/// An immutable network of [TextureNode]s.
final class TextureGraph {
  const TextureGraph({
    this.nodes = const <TextureNode>[],
    this.positions = const <int, (double, double)>{},
  });

  final List<TextureNode> nodes;

  /// Where `TextureGraphPanel` (`mat-13`) draws each node, by id — an (x, y)
  /// pair in the panel's own canvas space.
  ///
  /// **Presentation only.** Neither [validate] nor `bakeTextureGraph` reads
  /// this: two graphs that differ only in where their nodes are drawn bake to
  /// the same pixels, the same way two `ModelObject`s that differ only in
  /// which order the outliner happens to list them render the same scene. A
  /// node with no entry here is one `TextureGraphPanel` has never been told
  /// where to put — laid out however the panel's own default placement does,
  /// not treated as a graph a decoder failed to read.
  final Map<int, (double x, double y)> positions;

  /// The node with this id, or null when nothing in [nodes] has it.
  TextureNode? nodeById(int id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  /// What is wrong with this graph: a dangling input, a type mismatch, or a
  /// cycle — `mat-10`'s own two named checks plus the dangling case neither
  /// names but a type check needs answered one way or the other to avoid
  /// treating "wired to nothing found" as "wired to nothing," which is a
  /// different, silent fact.
  ///
  /// **Cycles are found before types are, and reported once per node that
  /// closes one** — a graph with `a → b → a` reports on whichever of the two
  /// the walk reaches second, not on every node the cycle passes through,
  /// since one node's own message is enough to say where to cut it.
  List<TextureGraphIssue> validate() {
    final issues = <TextureGraphIssue>[];
    final visiting = <int>{};
    final done = <int>{};

    void visit(TextureNode node) {
      if (done.contains(node.id)) return;
      if (visiting.contains(node.id)) {
        issues.add(TextureGraphIssue(node.id, 'is part of a cycle'));
        return;
      }
      visiting.add(node.id);
      for (final socket in node.inputs.values) {
        if (socket.from == null) continue;
        final source = nodeById(socket.from!);
        if (source != null) visit(source);
      }
      visiting.remove(node.id);
      done.add(node.id);
    }

    for (final node in nodes) {
      visit(node);
    }

    for (final node in nodes) {
      for (final entry in node.inputs.entries) {
        final from = entry.value.from;
        if (from == null) continue;
        final source = nodeById(from);
        if (source == null) {
          issues.add(
            TextureGraphIssue(
              node.id,
              'input "${entry.key}" reads node $from, which is not in this '
              'graph',
            ),
          );
          continue;
        }
        if (source.outputType != entry.value.type) {
          issues.add(
            TextureGraphIssue(
              node.id,
              'input "${entry.key}" expects ${entry.value.type.name} and '
              'node $from is ${source.outputType.name}',
            ),
          );
        }
      }
    }

    return issues;
  }

  Map<String, Object?> toJson() => {
    'nodes': <Map<String, Object?>>[
      for (final node in nodes)
        <String, Object?>{'id': node.id, 'kind': node.kind, ...node.toJson()},
    ],
    // Omitted rather than written empty, so a graph nothing has ever
    // positioned round-trips to exactly the JSON it would have before
    // `positions` existed — the same "silent unless there is something to
    // say" shape `LinkMaterialFile`'s own optional `bytes` already keeps.
    if (positions.isNotEmpty)
      'positions': <String, Object?>{
        for (final entry in positions.entries)
          '${entry.key}': <double>[entry.value.$1, entry.value.$2],
      },
  };

  static TextureGraph fromJson(Map<String, Object?> json) {
    final entries = switch (json['nodes']) {
      final List<Object?> value => value,
      _ => throw const FormatException('a texture graph with no "nodes" list'),
    };
    final positionsJson = json['positions'];
    return TextureGraph(
      nodes: <TextureNode>[
        for (final entry in entries)
          TextureNode.fromJson(entry! as Map<String, Object?>),
      ],
      positions: <int, (double, double)>{
        if (positionsJson is Map<String, Object?>)
          for (final entry in positionsJson.entries)
            if (int.tryParse(entry.key) case final int id)
              if (entry.value case final List<Object?> xy when xy.length == 2)
                id: ((xy[0]! as num).toDouble(), (xy[1]! as num).toDouble()),
      },
    );
  }
}
