/// `f3d.pipeline`: a frame's pipeline written down — its anchors, its nodes
/// with what each reads, writes and keeps, the steps switched off and the
/// settings slots it reads (D44).
library;

import 'dart:convert';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show DocumentFormatException, FormatDocument, FormatMigration, FormatSpec;

import 'engine_words.dart';

/// The `f3d.pipeline` version this build writes and the newest it reads.
///
/// **Version 2 names the engine's anchors, resources and steps `f3d.<name>`**
/// (`f3d.after_bloom`, `f3d.scene_color`, `f3d.color_grade`), as every
/// other registration carries its namespace. A version 1 document reads,
/// its words renamed on the way in ([engineWordFor]); this build writes
/// only the new ones.
const int pipelineVersion = 2;

/// `f3d.pipeline` in the format registry.
const FormatSpec pipelineFormat = FormatSpec(
  id: 'f3d.pipeline',
  version: pipelineVersion,
  suffixes: <String>['.pipeline.json'],
  fixture: 'test/fixtures/v<N>/standard.pipeline.json',
  migrations: <FormatMigration>[_engineWords],
);

/// Version 1 to 2: every anchor, resource and step a document names, in
/// the engine's `f3d.` words. Node names are what the frame reports and
/// stay as they are.
Map<String, Object?> _engineWords(Map<String, Object?> document) {
  Object? words(Object? value) => switch (value) {
    final List<Object?> list => <Object?>[
      for (final word in list) word is String ? engineWordFor(word) : word,
    ],
    _ => value,
  };
  Object? word(Object? value) => value is String ? engineWordFor(value) : value;
  Object? each(Object? entries, Map<String, Object?> Function(Map) lift) =>
      switch (entries) {
        final List<Object?> list => <Object?>[
          for (final entry in list) entry is Map ? lift(entry) : entry,
        ],
        _ => entries,
      };
  return <String, Object?>{
    ...document,
    if (document.containsKey('anchors'))
      'anchors': each(
        document['anchors'],
        (Map anchor) => <String, Object?>{
          ...anchor.cast<String, Object?>(),
          if (anchor.containsKey('after')) 'after': word(anchor['after']),
        },
      ),
    if (document.containsKey('nodes'))
      'nodes': each(
        document['nodes'],
        (Map node) => <String, Object?>{
          ...node.cast<String, Object?>(),
          if (node.containsKey('anchor')) 'anchor': word(node['anchor']),
          if (node.containsKey('step')) 'step': word(node['step']),
          for (final key in const <String>[
            'reads',
            'optionalReads',
            'writes',
            'keeps',
          ])
            if (node.containsKey(key)) key: words(node[key]),
        },
      ),
    if (document.containsKey('off')) 'off': words(document['off']),
  };
}

/// An anchor a pipeline adds: a plugin's own, standing right after another.
final class PipelineAnchor {
  const PipelineAnchor({required this.name, required this.after});

  /// The anchor's name, `<namespace>.<name>`.
  final String name;

  /// The anchor it stands right after, by name: the engine's or another
  /// added one.
  final String after;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'after': after,
  };
}

/// One node of a pipeline: where it stands, what it touches, and — for a
/// node of a plugin's own — which kind makes it.
final class PipelineNode {
  const PipelineNode({
    required this.name,
    required this.anchor,
    this.kind,
    this.engine = false,
    this.step,
    this.reads = const <String>[],
    this.optionalReads = const <String>[],
    this.writes = const <String>[],
    this.keeps = const <String>[],
    this.after = const <String>[],
    this.before = const <String>[],
    this.options = const <String, Object?>{},
    this.unknown = const <String, Object?>{},
  });

  /// The keys a node is written with; any other a node has was written by a
  /// later minor and is kept in [unknown].
  static const Set<String> keys = <String>{
    'name',
    'anchor',
    'kind',
    'engine',
    'step',
    'reads',
    'optionalReads',
    'writes',
    'keeps',
    'after',
    'before',
    'options',
  };

  /// The node's name, as the frame reports it.
  final String name;

  /// The anchor it stands at, by name.
  final String anchor;

  /// For a node a plugin adds, the kind that makes it — a
  /// `PipelineNodeKind`'s name; null for the engine's own nodes, which the
  /// renderer makes.
  final String? kind;

  /// Whether this is one of the engine's own passes. Written by the
  /// renderer when it describes its frame; a document applied to a renderer
  /// places none of them — they stand where the engine puts them — and an
  /// engine node it names that the renderer does not have is refused.
  final bool engine;

  /// The render step the node belongs to, by name, or null.
  final String? step;

  /// What the node reads, by resource name.
  final List<String> reads;

  /// What it reads when the frame produces it.
  final List<String> optionalReads;

  /// What it writes fresh this frame.
  final List<String> writes;

  /// What it maintains across frames.
  final List<String> keeps;

  /// Nodes at the same anchor it runs after and before.
  final List<String> after;
  final List<String> before;

  /// What the [kind] is handed to make the node: its own settings, by name.
  final Map<String, Object?> options;

  /// The node's keys this build does not read, as the file had them: written
  /// back after the node's own, so a pipeline a later minor wrote and this
  /// one opened and saved keeps what the later one added to its nodes
  /// (`FormatDocument.nestedUnknownIn`).
  final Map<String, Object?> unknown;

  Map<String, Object?> toJson() => FormatDocument.writeNested(<String, Object?>{
    'name': name,
    'anchor': anchor,
    'kind': ?kind,
    if (engine) 'engine': true,
    'step': ?step,
    if (reads.isNotEmpty) 'reads': reads,
    if (optionalReads.isNotEmpty) 'optionalReads': optionalReads,
    if (writes.isNotEmpty) 'writes': writes,
    if (keeps.isNotEmpty) 'keeps': keeps,
    if (after.isNotEmpty) 'after': after,
    if (before.isNotEmpty) 'before': before,
    if (options.isNotEmpty) 'options': options,
  }, unknown);
}

/// A frame's pipeline, written down (D44): what a renderer describes of its
/// own frame (`Renderer.describePipeline`), what an editor edits, what a
/// `.f3dplugin`'s `pipeline:` section brings, and what
/// `RendererSteps.fromDocument` applies.
///
/// **The standard pipeline is one of these** — the fixture
/// `test/fixtures/v1/standard.pipeline.json` is the engine's frame as the
/// renderer describes it — so a pipeline of one's own is that file edited,
/// and the two can be compared line by line.
final class PipelineDocument extends FormatDocument {
  PipelineDocument({
    this.name,
    this.anchors = const <PipelineAnchor>[],
    this.nodes = const <PipelineNode>[],
    this.stepsOff = const <String>[],
    this.settings = const <String>[],
    super.unknown,
  });

  /// Reads a document, lifted from any earlier version, or throws a
  /// [DocumentFormatException] saying what is wrong.
  factory PipelineDocument.fromJson(Map<String, Object?> json) {
    final document = pipelineFormat.open(
      json,
      refuse: DocumentFormatException.new,
    );
    List<Map<String, Object?>> entries(String key) => switch (document[key]) {
      null => const <Map<String, Object?>>[],
      final List<Object?> list when list.every((e) => e is Map) =>
        <Map<String, Object?>>[
          for (final entry in list) (entry! as Map).cast<String, Object?>(),
        ],
      _ => throw DocumentFormatException('"$key" is not a list of objects'),
    };
    List<String> names(Object? value, String what) => switch (value) {
      null => const <String>[],
      final List<Object?> list when list.every((e) => e is String) =>
        List<String>.unmodifiable(list.cast<String>()),
      _ => throw DocumentFormatException('$what is not a list of names'),
    };
    String text(Map<String, Object?> entry, String key, String what) =>
        switch (entry[key]) {
          final String value when value.isNotEmpty => value,
          _ => throw DocumentFormatException('$what names no "$key"'),
        };
    return PipelineDocument(
      name: document['name'] as String?,
      anchors: List<PipelineAnchor>.unmodifiable(<PipelineAnchor>[
        for (final entry in entries('anchors'))
          PipelineAnchor(
            name: text(entry, 'name', 'an anchor'),
            after: text(entry, 'after', 'an anchor'),
          ),
      ]),
      nodes: List<PipelineNode>.unmodifiable(<PipelineNode>[
        for (final entry in entries('nodes'))
          () {
            final name = text(entry, 'name', 'a node');
            final what = 'node "$name"';
            return PipelineNode(
              name: name,
              anchor: text(entry, 'anchor', what),
              kind: entry['kind'] as String?,
              engine: entry['engine'] == true,
              step: entry['step'] as String?,
              reads: names(entry['reads'], '$what: "reads"'),
              optionalReads: names(
                entry['optionalReads'],
                '$what: "optionalReads"',
              ),
              writes: names(entry['writes'], '$what: "writes"'),
              keeps: names(entry['keeps'], '$what: "keeps"'),
              after: names(entry['after'], '$what: "after"'),
              before: names(entry['before'], '$what: "before"'),
              options: switch (entry['options']) {
                null => const <String, Object?>{},
                final Map<Object?, Object?> map
                    when map.keys.every((k) => k is String) =>
                  Map<String, Object?>.unmodifiable(
                    map.cast<String, Object?>(),
                  ),
                _ => throw DocumentFormatException(
                  '$what: "options" is not an object',
                ),
              },
              unknown: FormatDocument.nestedUnknownIn(
                entry,
                known: PipelineNode.keys,
              ),
            );
          }(),
      ]),
      stepsOff: names(document['off'], '"off"'),
      settings: names(document['settings'], '"settings"'),
      unknown: FormatDocument.unknownIn(
        document,
        known: _known,
        spec: pipelineFormat,
      ),
    );
  }

  /// Reads [text], a whole `.pipeline.json` file.
  factory PipelineDocument.parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw DocumentFormatException('a pipeline is not JSON: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const DocumentFormatException('a pipeline is a JSON object');
    }
    return PipelineDocument.fromJson(decoded);
  }

  static const Set<String> _known = <String>{
    'name',
    'anchors',
    'nodes',
    'off',
    'settings',
  };

  @override
  FormatSpec get spec => pipelineFormat;

  /// What the pipeline is called — `standard` for the engine's own.
  final String? name;

  /// The anchors it adds, in the order they are added.
  final List<PipelineAnchor> anchors;

  /// Its nodes, in the order the frame registers them.
  final List<PipelineNode> nodes;

  /// The render steps it switches off, by name.
  final List<String> stepsOff;

  /// The settings slots it reads, by id.
  final List<String> settings;

  /// The nodes a plugin adds — every one not the engine's own.
  Iterable<PipelineNode> get added => nodes.where((node) => !node.engine);

  /// The document as a `.pipeline.json` file writes it.
  Map<String, Object?> toJson() => write(<String, Object?>{
    'name': ?name,
    if (anchors.isNotEmpty)
      'anchors': <Object?>[for (final anchor in anchors) anchor.toJson()],
    'nodes': <Object?>[for (final node in nodes) node.toJson()],
    if (stepsOff.isNotEmpty) 'off': stepsOff,
    if (settings.isNotEmpty) 'settings': settings,
  });

  /// [toJson] as text, one node a line, the way the fixture is written.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}
