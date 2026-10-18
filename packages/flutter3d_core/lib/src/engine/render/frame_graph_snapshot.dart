part of 'frame_graph.dart';

/// A compiled frame graph written down: every pass that ran, in order, with
/// the version of each resource it read and wrote; every pass that did not,
/// with why and what it declared; and what the frame was asked for.
///
/// **What a tool reads instead of the graph.** The compiled graph holds
/// nodes, which are code; this holds names and numbers, so it goes through
/// JSON ([toJson], [FrameGraphSnapshot.fromJson]) to an editor, an MCP
/// server or a bug report, and through [toMermaid] onto any page that draws
/// Mermaid. Made with [CompiledFrameGraph.snapshot]; the renderer's last
/// frame is `Renderer.lastFrameGraph`.
///
/// **Culled and skipped passes are part of it.** A pass that silently stops
/// running is the question a picture of the graph exists to answer, so the
/// passes left out are listed with their [PassSkip] reason and the names
/// they read and wrote, drawn dashed in the Mermaid text.
final class FrameGraphSnapshot {
  /// A snapshot of [passes], [skipped] and [outputs].
  const FrameGraphSnapshot({
    this.passes = const <FrameGraphPassSnapshot>[],
    this.skipped = const <SkippedPassSnapshot>[],
    this.outputs = const <String>[],
  });

  /// [json] read back, as [toJson] writes it.
  ///
  /// Throws a [FormatException] for a document of another format or of a
  /// version newer than [version].
  factory FrameGraphSnapshot.fromJson(Map<String, Object?> json) {
    if (json['format'] != format) {
      throw FormatException(
        'not a frame graph snapshot: format is ${json['format']}, not $format',
      );
    }
    final at = json['version'];
    if (at is! int || at > version) {
      throw FormatException(
        'a frame graph snapshot of version $at; this reads up to $version',
      );
    }
    List<Map<String, Object?>> list(String key) => <Map<String, Object?>>[
      for (final entry in (json[key] as List<Object?>?) ?? const <Object?>[])
        (entry! as Map).cast<String, Object?>(),
    ];
    return FrameGraphSnapshot(
      passes: <FrameGraphPassSnapshot>[
        for (final pass in list('passes')) FrameGraphPassSnapshot._read(pass),
      ],
      skipped: <SkippedPassSnapshot>[
        for (final pass in list('skipped')) SkippedPassSnapshot._read(pass),
      ],
      outputs: _strings(json['outputs']),
    );
  }

  /// What [toJson] writes under `format`.
  static const String format = 'f3d.frameGraph';

  /// The newest layout [toJson] writes and [FrameGraphSnapshot.fromJson]
  /// reads.
  static const int version = 1;

  /// The passes that ran, earliest first.
  final List<FrameGraphPassSnapshot> passes;

  /// The passes that did not run, in registration order, each with why.
  final List<SkippedPassSnapshot> skipped;

  /// The resources the frame was asked to produce, by name.
  final List<String> outputs;

  /// This snapshot as JSON: plain maps, lists, strings and numbers.
  Map<String, Object?> toJson() => <String, Object?>{
    'format': format,
    'version': version,
    'passes': <Map<String, Object?>>[for (final pass in passes) pass._json()],
    'skipped': <Map<String, Object?>>[for (final pass in skipped) pass._json()],
    'outputs': outputs,
  };

  /// This snapshot as a Mermaid flowchart, left to right: a box per pass
  /// that ran, a rounded node per resource version (`hdr_color@1`), an
  /// edge from each version's producer to its readers, and each skipped pass
  /// dashed, with its reason, joined by dotted edges to the names it
  /// declared.
  ///
  /// Version 0 of a name is what the engine handed in, drawn as an input.
  String toMermaid() {
    final out = StringBuffer()..writeln('flowchart LR');
    final ids = <String, String>{};
    String idOf(String key) =>
        ids.putIfAbsent(key, () => 'n${ids.length.toString()}');
    void node(String key, String shape) {
      if (ids.containsKey(key)) return;
      out.writeln('  ${idOf(key)}$shape');
    }

    String resource(String name, int version) {
      final key = 'r:$name@$version';
      node(key, '(["${_label('$name@$version')}"])');
      return idOf(key);
    }

    for (var i = 0; i < passes.length; i++) {
      final pass = passes[i];
      node('p:${pass.name}', '["${_label(pass.name)}"]');
      final self = idOf('p:${pass.name}');
      pass.reads.forEach((name, version) {
        out.writeln('  ${resource(name, version)} --> $self');
      });
      pass.writes.forEach((name, version) {
        final arrow = pass.keeps.contains(name) ? '==>' : '-->';
        out.writeln('  $self $arrow ${resource(name, version)}');
      });
    }
    for (final pass in skipped) {
      node(
        's:${pass.name}',
        '["${_label('${pass.name} (${pass.reason.name})')}"]:::skipped',
      );
      final self = idOf('s:${pass.name}');
      for (final name in pass.reads) {
        node('d:$name', '(["${_label(name)}"])');
        out.writeln('  ${idOf('d:$name')} -.-> $self');
      }
      for (final name in pass.writes) {
        node('d:$name', '(["${_label(name)}"])');
        out.writeln('  $self -.-> ${idOf('d:$name')}');
      }
    }
    if (skipped.isNotEmpty) {
      out.writeln(
        '  classDef skipped stroke-dasharray: 5 5,color:#888,fill:none',
      );
    }
    return out.toString();
  }

  @override
  String toString() =>
      'FrameGraphSnapshot(${passes.length} passes, ${skipped.length} '
      'skipped)';
}

/// A label as Mermaid reads it inside double quotes: a quote written as its
/// entity.
String _label(String text) => text.replaceAll('"', '#quot;');

List<String> _strings(Object? value) => <String>[
  for (final entry in (value as List<Object?>?) ?? const <Object?>[])
    entry! as String,
];

Map<String, int> _versions(Object? value) => <String, int>{
  for (final MapEntry(:key, :value)
      in ((value as Map?)?.cast<String, Object?>() ?? const <String, Object?>{})
          .entries)
    key: value! as int,
};

/// One pass that ran, as a [FrameGraphSnapshot] holds it.
final class FrameGraphPassSnapshot {
  /// [name], reading and writing the versions in [reads] and [writes], with
  /// the names of [writes] it maintains across frames in [keeps].
  const FrameGraphPassSnapshot({
    required this.name,
    this.reads = const <String, int>{},
    this.writes = const <String, int>{},
    this.keeps = const <String>[],
  });

  factory FrameGraphPassSnapshot._read(Map<String, Object?> json) =>
      FrameGraphPassSnapshot(
        name: json['name']! as String,
        reads: _versions(json['reads']),
        writes: _versions(json['writes']),
        keeps: _strings(json['keeps']),
      );

  /// The pass's name.
  final String name;

  /// Each resource it read, required or optional, to the version it read.
  final Map<String, int> reads;

  /// Each resource it wrote or maintained, to the version it produced.
  final Map<String, int> writes;

  /// The names among [writes] it maintains across frames rather than draws
  /// fresh (`FrameGraphNode.keeps`).
  final List<String> keeps;

  Map<String, Object?> _json() => <String, Object?>{
    'name': name,
    'reads': reads,
    'writes': writes,
    if (keeps.isNotEmpty) 'keeps': keeps,
  };

  @override
  String toString() => 'FrameGraphPassSnapshot($name)';
}

/// One pass that did not run, as a [FrameGraphSnapshot] holds it.
final class SkippedPassSnapshot {
  /// [name], left out for [reason], declaring [reads] and [writes]; [owner]
  /// and [error] for a [PassSkip.failed] pass.
  const SkippedPassSnapshot({
    required this.name,
    required this.reason,
    this.reads = const <String>[],
    this.writes = const <String>[],
    this.owner,
    this.error,
  });

  factory SkippedPassSnapshot._read(Map<String, Object?> json) =>
      SkippedPassSnapshot(
        name: json['name']! as String,
        reason:
            PassSkip.byName(json['reason']! as String) ??
            (throw FormatException(
              'a skipped pass "${json['name']}" with the reason '
              '"${json['reason']}", which this version does not know',
            )),
        reads: _strings(json['reads']),
        writes: _strings(json['writes']),
        owner: json['owner'] as String?,
        error: json['error'] as String?,
      );

  /// The pass's name.
  final String name;

  /// Why it did not run.
  final PassSkip reason;

  /// What it declared it reads, required and optional, by name.
  final List<String> reads;

  /// What it declared it writes or maintains, by name.
  final List<String> writes;

  /// For a [PassSkip.failed] pass, who placed it (`NodeFailure.owner`).
  final String? owner;

  /// For a [PassSkip.failed] pass, what it threw, as text.
  final String? error;

  Map<String, Object?> _json() => <String, Object?>{
    'name': name,
    'reason': reason.name,
    'reads': reads,
    'writes': writes,
    'owner': ?owner,
    'error': ?error,
  };

  @override
  String toString() => 'SkippedPassSnapshot($name, ${reason.name})';
}

/// A [CompiledFrameGraph] written down.
FrameGraphSnapshot _snapshotOf(CompiledFrameGraph graph) {
  final culled = <String, FrameGraphNode>{
    for (final node in graph.culled) node.name: node,
  };
  return FrameGraphSnapshot(
    passes: List<FrameGraphPassSnapshot>.unmodifiable(<FrameGraphPassSnapshot>[
      for (var i = 0; i < graph.order.length; i++)
        FrameGraphPassSnapshot(
          name: graph.order[i].name,
          reads: Map<String, int>.unmodifiable(graph._bindings[i].reads),
          writes: Map<String, int>.unmodifiable(graph._bindings[i].writes),
          keeps: List<String>.unmodifiable(<String>[
            for (final id in graph.keptBy(i)) id.name,
          ]),
        ),
    ]),
    skipped: List<SkippedPassSnapshot>.unmodifiable(<SkippedPassSnapshot>[
      for (final entry in graph.skipped)
        switch (culled[entry.name]) {
          final node? => () {
            final declared = NodeDeclarations.of(node);
            return SkippedPassSnapshot(
              name: entry.name,
              reason: entry.reason,
              reads: <String>[
                for (final id in declared.reads) id.name,
                for (final id in declared.optionalReads) id.name,
              ],
              writes: <String>[
                for (final id in declared.writes) id.name,
                for (final id in declared.keeps) id.name,
              ],
              owner: entry.failure?.owner,
              error: entry.failure?.error.toString(),
            );
          }(),
          null => SkippedPassSnapshot(
            name: entry.name,
            reason: entry.reason,
            owner: entry.failure?.owner,
            error: entry.failure?.error.toString(),
          ),
        },
    ]),
    outputs: List<String>.unmodifiable(<String>[
      for (final id in graph.outputs) id.name,
    ]),
  );
}
