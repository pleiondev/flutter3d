import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart' show RendererSteps;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EntityKinds;

import '../data_event.dart';
import '../permissions.dart';
import '../scripting/script_runtime.dart';
import '../wasm/wasm.dart';
import '../world_fields.dart' show Fixed16;
import 'data_entity_kind.dart';
import 'data_sections.dart';
import 'runtime_shaders.dart';

/// A `.f3dplugin` document that cannot be read, with the sentence that says
/// why.
final class DataPluginFormatException extends Flutter3dFormatException {
  const DataPluginFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'DataPluginFormatException: $message';
}

/// A loop phase a data plugin adds.
final class DataPhase {
  const DataPhase({
    required this.name,
    required this.kind,
    this.after = const <String>[],
    this.before = const <String>[],
  });

  final String name;

  /// [PhaseKind.step] or [PhaseKind.frame].
  final PhaseKind kind;

  /// Phases of the same kind it goes after and before.
  final List<String> after;
  final List<String> before;

  LoopPhase get phase =>
      kind == PhaseKind.frame ? LoopPhase.frame(name) : LoopPhase.step(name);

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'kind': kind.name,
    if (after.isNotEmpty) 'after': after,
    if (before.isNotEmpty) 'before': before,
  };
}

/// An event a data plugin publishes, declared on the bus as
/// `<plugin id>.<name>`.
final class DataEventDeclaration {
  const DataEventDeclaration({required this.name, this.description});

  /// The name without the plugin's prefix.
  final String name;
  final String? description;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (description != null) 'description': description,
  };
}

/// A material in the material language, as a file of the plugin's or as
/// text written into the document.
final class DataMaterial {
  const DataMaterial({this.source, this.text})
    : assert(
        (source == null) != (text == null),
        'a material is a source path or text, not both',
      );

  /// The `.f3dmat` file, relative to the plugin's own directory.
  final String? source;

  /// The material written out in the document.
  final String? text;

  Map<String, Object?> toJson() => <String, Object?>{
    if (source != null) 'source': source,
    if (text != null) 'text': text,
  };
}

/// A render step a data plugin adds: a full-screen stage per backend at an
/// anchor. See [RuntimeRenderStep], which it becomes.
final class DataRenderStep {
  const DataRenderStep({
    required this.name,
    required this.anchor,
    required this.shaders,
    this.present = false,
    this.needs = const <String>[],
    this.after = const <String>[],
    this.before = const <String>[],
  });

  /// The name without the plugin's prefix.
  final String name;

  /// The anchor the step is placed at, by name: one of the engine's
  /// (`after bloom`), or one another plugin added to the renderer
  /// (`RendererSteps.addAnchor`). A name, not a [RenderAnchor], because a
  /// plugin's anchor is the renderer's, and the document is read before
  /// there is one; the engine resolves it with `RendererSteps.anchorNamed`
  /// when the plugin is installed.
  final String anchor;

  /// The stage's source file, by backend.
  final Map<String, String> shaders;
  final bool present;
  final List<String> needs;
  final List<String> after;
  final List<String> before;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'anchor': anchor,
    'shaders': shaders,
    if (present) 'present': true,
    if (needs.isNotEmpty) 'needs': needs,
    if (after.isNotEmpty) 'after': after,
    if (before.isNotEmpty) 'before': before,
  };
}

/// A plugin written as data: what a `.f3dplugin` file holds.
///
/// **Decision 4 of `tasks/0.9-plugins.md`: some plugins load while the game
/// runs.** A Dart plugin is compiled into the application. A data plugin is
/// a document an application reads at run time — from its assets, from a
/// mod folder, from a server — and installs through the same host, with the
/// same manifest, the same switch at a step boundary and the same journal.
/// What it can declare is what the engine already has a data form for:
///
/// * `phases` — loop phases, step or frame, ordered by `after`/`before`;
/// * `events` — the events its Wasm systems and scripts publish, declared on
///   the bus as `<plugin id>.<name>` ([PluginDataEvent]);
/// * `entityKinds` — the kinds a level may name ([DataEntityKind]): a
///   genre's rules, in the one form a genre's rules already are data;
/// * `materials` — the material language, compiled where the backend
///   compiles at run time ([RuntimeShaders]);
/// * `renderSteps` — a full-screen stage per backend at an anchor, switched
///   like the engine's own steps;
/// * `wasm` — step systems in Wasm under ABI [wasmPluginAbi];
/// * `scripts` — step systems in interpreted Dart, behind a
///   [ScriptRuntime] the application provides;
/// * any section a subsystem registered in the [DataSectionRegistry] the
///   document is read with ([sections]): `effects` (particle effects, read by
///   `flutter3d_particles`' `effectsSection`), `physicalMaterials` and
///   `materialPairs` (substances and how they meet, read by
///   `flutter3d_matter`'s sections). This package reads none of them
///   itself, so it depends on none of the packages they install into.
///
/// A section no registered reader takes is kept as written in [extra] and
/// written back, and [DataPlugin.notes] says it was not read.
///
/// ```json
/// {
///   "format": "f3d.plugin", "version": 2,
///   "manifest": {"id": "gusts", "apiVersion": "1.0", "touches": "simulation"},
///   "phases": [{"name": "weather", "kind": "step",
///               "after": ["physics"], "before": ["elements"]}],
///   "events": [{"name": "gust"}],
///   "wasm": [{"module": "gusts.wasm", "system": "blow", "phase": "weather",
///             "fields": [{"name": "wind", "write": true}],
///             "events": ["gust"]}]
/// }
/// ```
///
/// **Versioned, with the format policy every engine file follows**
/// (decision 8 of `tasks/1.0-stability.md`): `f3dplugin` carries the version,
/// a 1.x engine reads every 1.x document through [_migrations], a document
/// from the future is refused with the version that reads it, and keys this
/// build does not know are kept in [extra] and written back.
///
/// **JSON.** A document is written by tools as often as by hand, and the
/// package that reads it runs in a browser and on a server; a YAML front end
/// can come later without the format changing.
final class DataPluginDocument {
  const DataPluginDocument({
    required this.manifest,
    this.phases = const <DataPhase>[],
    this.events = const <DataEventDeclaration>[],
    this.entityKinds = const <DataEntityKind>[],
    this.materials = const <DataMaterial>[],
    this.renderSteps = const <DataRenderStep>[],
    this.wasm = const <WasmSystemSpec>[],
    this.scripts = const <ScriptSystemSpec>[],
    this.sections = const <String, ({DataSection reader, Object section})>{},
    this.extra = const <String, Object?>{},
  });

  /// Bumped when an existing key changes meaning, with a step in
  /// [_migrations] and a fixture under `test/fixtures/v<N>/`.
  ///
  /// **2 is the format envelope** (`"format": "f3d.plugin", "version": 2`)
  /// in place of version 1's `"f3dplugin": 1`. No section changed meaning;
  /// a build from before looks for its version under `f3dplugin`, so it
  /// refuses a version-2 document as having none rather than misreading it.
  static const int formatVersion = 2;

  /// Entry `i` lifts a document from version `i + 1` to `i + 2`. 1 → 2 is the
  /// identity: [FormatSpec.open] has read the version from `f3dplugin`.
  static const List<FormatMigration> _migrations = <FormatMigration>[_identity];

  static Map<String, Object?> _identity(Map<String, Object?> document) =>
      document;

  /// The data plugin format in the registry: `f3d.plugin`, read from its
  /// own envelope or from version 1's `"f3dplugin": 1`.
  ///
  /// It understands no `requires` of its own: what a document requires is
  /// a registered section's [DataSection.requirement], which the sections a
  /// document is read with answer for ([_withoutUnderstood]).
  static const FormatSpec format = FormatSpec(
    id: 'f3d.plugin',
    version: formatVersion,
    suffixes: <String>['.f3dplugin'],
    fixture: 'test/fixtures/v<N>/glow.f3dplugin',
    migrations: _migrations,
    legacyVersionKey: 'f3dplugin',
  );

  /// [document] without the `requires` entries a section in [sections]
  /// reads, so [format] refuses only what nothing here understands: a
  /// document requiring a section nobody registered is refused, rather than
  /// installed without it.
  static Map<String, Object?> _withoutUnderstood(
    Map<String, Object?> document,
    DataSectionRegistry? sections,
  ) {
    final understood = <String>{
      for (final name in sections?.names ?? const <String>[])
        ?sections![name]?.requirement,
    };
    return switch (document['requires']) {
      final List<Object?> requires when understood.isNotEmpty =>
        <String, Object?>{
          ...document,
          'requires': <Object?>[
            for (final r in requires)
              if (!understood.contains(r)) r,
          ],
        },
      _ => document,
    };
  }

  final PluginManifest manifest;
  final List<DataPhase> phases;
  final List<DataEventDeclaration> events;
  final List<DataEntityKind> entityKinds;
  final List<DataMaterial> materials;
  final List<DataRenderStep> renderSteps;
  final List<WasmSystemSpec> wasm;
  final List<ScriptSystemSpec> scripts;

  /// The sections a registered reader read, by name: each with the
  /// [DataSection] that read it and what its [DataSection.read] returned.
  final Map<String, ({DataSection reader, Object section})> sections;

  /// Top-level keys this build does not know, kept as they were read.
  final Map<String, Object?> extra;

  /// Every file the document points at, in the order it names them: the
  /// materials' sources, the render steps' stages, the Wasm modules, the
  /// scripts and what the [sections] name. What a loader reads before
  /// anything is installed.
  List<String> get resources => <String>{
    for (final material in materials) ?material.source,
    for (final step in renderSteps) ...step.shaders.values,
    for (final system in wasm) system.module,
    for (final script in scripts) script.source,
    for (final (:reader, :section) in sections.values)
      ...reader.resources(section),
  }.toList(growable: false);

  /// Reads [text] as a document, or throws a [DataPluginFormatException].
  /// [sections] read what their subsystems own; a section none of them
  /// reads is kept in [extra].
  factory DataPluginDocument.parse(
    String text, {
    DataSectionRegistry? sections,
  }) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (error) {
      throw DataPluginFormatException(
        'the document is not JSON: ${error.message}',
      );
    }
    if (json is! Map<String, Object?>) {
      throw const DataPluginFormatException('the document is not an object');
    }
    return DataPluginDocument.fromJson(json, sections: sections);
  }

  /// Reads a decoded document, or throws a [DataPluginFormatException] that
  /// says what is wrong and where. [sections] as in [parse].
  factory DataPluginDocument.fromJson(
    Map<String, Object?> document, {
    DataSectionRegistry? sections,
  }) {
    final version = document['version'] ?? document['f3dplugin'];
    if (version is! int || version < 1) {
      throw const DataPluginFormatException(
        'the document has no version in it — neither "version" nor version '
        '1\'s "f3dplugin"',
      );
    }
    // A newer document, another format's or a `requires` this build does
    // not know is refused by the spec; every older one is lifted through
    // [_migrations] before a key is read (decision 8 of
    // `tasks/1.0-stability.md`).
    final json = format.open(
      _withoutUnderstood(document, sections),
      refuse: DataPluginFormatException.new,
    );
    try {
      return _read(json, sections);
    } on DataPluginFormatException {
      rethrow;
    } on Flutter3dFormatException catch (error) {
      // A section's own reader refused — a Wasm system's declaration, a
      // script's, the manifest inside the document, a registered section.
      throw DataPluginFormatException(error.message);
    } on FormatException catch (error) {
      throw DataPluginFormatException(error.message);
    }
  }

  static DataPluginDocument _read(
    Map<String, Object?> json,
    DataSectionRegistry? registry,
  ) {
    final rawManifest = json['manifest'];
    if (rawManifest is! Map<String, Object?>) {
      throw const DataPluginFormatException('the document has no manifest');
    }
    final manifest = PluginManifest.fromJson(rawManifest);
    final problem = manifest.idProblem;
    if (problem != null) throw DataPluginFormatException(problem);
    final id = manifest.id;

    List<Map<String, Object?>> entries(String key) => switch (json[key]) {
      null => const <Map<String, Object?>>[],
      final List<Object?> list when list.every((e) => e is Map) =>
        <Map<String, Object?>>[
          for (final entry in list) (entry! as Map).cast<String, Object?>(),
        ],
      _ => throw DataPluginFormatException('"$key" is not a list of objects'),
    };
    List<String> names(Map<String, Object?> entry, String key, String what) =>
        switch (entry[key]) {
          null => const <String>[],
          final List<Object?> list when list.every((e) => e is String) =>
            List<String>.unmodifiable(list.cast<String>()),
          _ => throw DataPluginFormatException(
            '$what: "$key" is not a list of names',
          ),
        };
    String text(Map<String, Object?> entry, String key, String what) =>
        switch (entry[key]) {
          final String value when value.isNotEmpty => value,
          _ => throw DataPluginFormatException('$what names no "$key"'),
        };

    final phases = <DataPhase>[
      for (final entry in entries('phases'))
        DataPhase(
          name: text(entry, 'name', 'a phase'),
          kind: switch (entry['kind'] ?? 'step') {
            'step' => PhaseKind.step,
            'frame' => PhaseKind.frame,
            final Object? other => throw DataPluginFormatException(
              'phase "${entry['name']}": kind "$other" is neither step nor '
              'frame',
            ),
          },
          after: names(entry, 'after', 'phase "${entry['name']}"'),
          before: names(entry, 'before', 'phase "${entry['name']}"'),
        ),
    ];

    final events = <DataEventDeclaration>[
      for (final entry in entries('events'))
        DataEventDeclaration(
          name: text(entry, 'name', 'an event'),
          description: entry['description'] is String
              ? entry['description']! as String
              : null,
        ),
    ];
    final declared = <String>{for (final event in events) event.name};

    final kinds = <DataEntityKind>[
      for (final entry in entries('entityKinds'))
        DataEntityKind.fromJson(entry, owner: id),
    ];

    final materials = <DataMaterial>[
      for (final entry in entries('materials'))
        switch ((entry['source'], entry['text'])) {
          (final String source, null) => DataMaterial(source: source),
          (null, final String text) => DataMaterial(text: text),
          _ => throw const DataPluginFormatException(
            'a material is a "source" file or its "text", one of the two',
          ),
        },
    ];

    final renderSteps = <DataRenderStep>[
      for (final entry in entries('renderSteps')) _renderStep(entry, text),
    ];

    final wasm = <WasmSystemSpec>[
      for (final entry in entries('wasm')) WasmSystemSpec.fromJson(entry),
    ];
    final scripts = <ScriptSystemSpec>[
      for (final entry in entries('scripts')) ScriptSystemSpec.fromJson(entry),
    ];
    // An event a system publishes is declared, so a tool listing what the
    // plugin says lists it, and two plugins cannot claim one name.
    for (final (what, published) in <(String, List<String>)>[
      for (final system in wasm)
        ('Wasm system "${system.system}"', system.events),
      for (final script in scripts)
        ('script "${script.system}"', script.events),
    ]) {
      for (final event in published) {
        if (!declared.contains(event)) {
          throw DataPluginFormatException(
            '$what publishes "$event", which the document\'s "events" does '
            'not declare',
          );
        }
      }
    }

    final context = DataSectionContext(plugin: id);
    final sections = <String, ({DataSection reader, Object section})>{
      for (final key in json.keys)
        if (!DataSections.runtimeKeys.contains(key))
          if (registry?[key] case final DataSection reader)
            key: (reader: reader, section: reader.read(json[key], context)),
    };

    return DataPluginDocument(
      manifest: manifest,
      phases: List<DataPhase>.unmodifiable(phases),
      events: List<DataEventDeclaration>.unmodifiable(events),
      entityKinds: List<DataEntityKind>.unmodifiable(kinds),
      materials: List<DataMaterial>.unmodifiable(materials),
      renderSteps: List<DataRenderStep>.unmodifiable(renderSteps),
      wasm: List<WasmSystemSpec>.unmodifiable(wasm),
      scripts: List<ScriptSystemSpec>.unmodifiable(scripts),
      sections:
          Map<String, ({DataSection reader, Object section})>.unmodifiable(
            sections,
          ),
      extra: Map<String, Object?>.unmodifiable(
        FormatDocument.unknownIn(
          json,
          known: <String>{...DataSections.runtimeKeys, ...sections.keys},
          spec: format,
        ),
      ),
    );
  }

  static DataRenderStep _renderStep(
    Map<String, Object?> entry,
    String Function(Map<String, Object?>, String, String) text,
  ) {
    final name = text(entry, 'name', 'a render step');
    final what = 'render step "$name"';
    final written = text(entry, 'anchor', what);
    final present = switch (entry['present']) {
      null => false,
      final bool value => value,
      _ => throw DataPluginFormatException(
        '$what: "present" is not true or false',
      ),
    };
    // An engine anchor is checked here; any other name is one a plugin adds
    // to the renderer, resolved and checked when this one is installed.
    final engine = _anchorIn(RenderAnchor.values, written);
    if (engine != null) _checkSide(what, engine, present: present);
    final shaders = switch (entry['shaders']) {
      final Map<Object?, Object?> map
          when map.isNotEmpty &&
              map.keys.every((k) => k is String) &&
              map.values.every((v) => v is String) =>
        Map<String, String>.unmodifiable(map.cast<String, String>()),
      _ => throw DataPluginFormatException(
        '$what: "shaders" is not a map from a backend to a stage\'s file',
      ),
    };
    List<String> names(String key) => switch (entry[key]) {
      null => const <String>[],
      final List<Object?> list when list.every((e) => e is String) =>
        List<String>.unmodifiable(list.cast<String>()),
      _ => throw DataPluginFormatException(
        '$what: "$key" is not a list of names',
      ),
    };
    return DataRenderStep(
      name: name,
      anchor: engine?.name ?? written,
      shaders: shaders,
      present: present,
      needs: names('needs'),
      after: names('after'),
      before: names('before'),
    );
  }

  /// The anchor of [anchors] called [written], by its name (`after bloom`)
  /// or as Dart spells it (`afterBloom`), which is how a reader of the API
  /// will write it; null when none is.
  static RenderAnchor? _anchorIn(List<RenderAnchor> anchors, String written) {
    final spaced = written.replaceAllMapped(
      RegExp('[A-Z]'),
      (Match m) => ' ${m[0]!.toLowerCase()}',
    );
    return anchors
        .where((RenderAnchor a) => a.name == written || a.name == spaced)
        .firstOrNull;
  }

  /// Refuses a step on the wrong side of tone mapping. A plugin's anchor is
  /// judged by the engine anchor it follows ([RenderAnchor.engineAnchor]).
  ///
  /// A stage over the scene's light reads `hdr_colour`, which tone mapping
  /// turns into `frame`: one placed on the wrong side of it would read a
  /// picture that is not there yet, or is not there any more.
  static void _checkSide(
    String what,
    RenderAnchor anchor, {
    required bool present,
  }) {
    final at = RenderAnchor.values.indexOf(anchor.engineAnchor);
    final tonemap = RenderAnchor.values.indexOf(RenderAnchor.afterTonemap);
    if (present && at < tonemap) {
      throw DataPluginFormatException(
        '$what draws over the finished picture ("present": true) at '
        '"${anchor.name}", before tone mapping has made one; place it at '
        '"${RenderAnchor.afterTonemap.name}" or later',
      );
    }
    if (!present && at >= tonemap) {
      throw DataPluginFormatException(
        '$what draws over the scene\'s light at "${anchor.name}", after tone '
        'mapping has turned it into the picture; place it before '
        '"${RenderAnchor.afterTonemap.name}", or set "present": true',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    ...format.envelope(
      requires: <String>{
        for (final (:reader, section: _) in sections.values)
          ?reader.requirement,
      }.toList(),
    ),
    for (final MapEntry(:key, :value) in extra.entries)
      if (!FormatSpec.envelopeKeys.contains(key)) key: value,
    'manifest': manifest.toJson(),
    if (phases.isNotEmpty)
      'phases': <Object?>[for (final p in phases) p.toJson()],
    if (events.isNotEmpty)
      'events': <Object?>[for (final e in events) e.toJson()],
    if (entityKinds.isNotEmpty)
      'entityKinds': <Object?>[for (final k in entityKinds) k.toJson()],
    if (materials.isNotEmpty)
      'materials': <Object?>[for (final m in materials) m.toJson()],
    if (renderSteps.isNotEmpty)
      'renderSteps': <Object?>[for (final s in renderSteps) s.toJson()],
    if (wasm.isNotEmpty) 'wasm': <Object?>[for (final w in wasm) w.toJson()],
    if (scripts.isNotEmpty)
      'scripts': <Object?>[for (final s in scripts) s.toJson()],
    for (final MapEntry(key: name, value: (:reader, :section))
        in sections.entries)
      name: reader.write(section),
  };
}

/// Where a run-time plugin's own files come from.
///
/// **The plugin's own directory, and nothing beyond it.** A path a document
/// names — `glow.f3dmat`, `systems/push.wasm` — is read through this, and
/// the application decides what backs it: its asset bundle, a mod folder, a
/// download it already made. A path that leaves the directory, or a URL, is
/// not read here at all; it goes through the doors [DataPluginLoader] holds,
/// and only for a plugin that declares the permission and is granted it.
abstract base class PluginSource {
  const PluginSource();

  /// The bytes of [path], relative to the plugin's own directory. Throws
  /// when there is no such file.
  Future<Uint8List> read(String path);
}

/// A [PluginSource] over files already in memory: a test, or a plugin an
/// application unpacked itself.
final class MemoryPluginSource extends PluginSource {
  MemoryPluginSource(Map<String, Uint8List> files)
    : _files = Map<String, Uint8List>.unmodifiable(files);

  final Map<String, Uint8List> _files;

  @override
  Future<Uint8List> read(String path) async =>
      _files[path] ??
      (throw DataPluginFormatException(
        'the plugin names "$path", and it has no such file '
        '(${_files.keys.join(', ')})',
      ));
}

/// Reads `.f3dplugin` documents into plugins, holding the doors beyond a
/// plugin's own files.
///
/// **Permissions are enforced here, where access is handed out** (decision 6
/// of `tasks/0.9-plugins.md`). Before anything is read, every permission the
/// manifest declares must be in [grants]. Then each path the document names
/// is classified:
///
/// * relative and inside the plugin's directory — read from its
///   [PluginSource], with no permission needed;
/// * an `http:` or `https:` URL — needs `network`, declared and granted,
///   and goes through [fetch];
/// * absolute, a `file:` URL, or climbing out with `..` — needs `files`,
///   declared and granted, and goes through [readFile].
///
/// Each refusal is a [PermissionException] naming the plugin, the permission
/// and the path. A Wasm module under ABI 1 has no import that reaches either
/// door, and a script is handed none, so what is checked here is all the
/// reach a data plugin has.
final class DataPluginLoader {
  const DataPluginLoader({
    this.grants = PluginGrants.none,
    this.fetch,
    this.readFile,
    this.wasmRuntime = WasmRuntime.interpreter,
    this.sections,
  });

  /// The sections beyond the runtime's own that the documents are read
  /// with, each by the subsystem that registered it: the engine's
  /// [DataSectionRegistry]. Without it a document's `effects` or
  /// `physicalMaterials` is kept as written and not read, and a document
  /// whose `requires` names one is refused.
  final DataSectionRegistry? sections;

  /// What the application allows the plugins it loads.
  final PluginGrants grants;

  /// The application's door to the network, for a plugin granted `network`.
  final Future<Uint8List> Function(Uri url)? fetch;

  /// The application's door to its files, for a plugin granted `files`.
  final Future<Uint8List> Function(String path)? readFile;

  /// What steps the plugins' Wasm systems: the interpreter by default, which
  /// is metered and gives one answer on every platform.
  final WasmRuntime wasmRuntime;

  /// Reads [text] and every file it names, and returns the plugin.
  ///
  /// Throws a [DataPluginFormatException] for a document that cannot be
  /// read, a [PermissionException] for a permission not granted or a door not
  /// given, a `WasmException` for a module that is not ABI 1, and lets a
  /// [PluginSource]'s own failure through.
  Future<DataPlugin> load(String text, PluginSource source) async {
    final document = DataPluginDocument.parse(text, sections: sections);
    final manifest = document.manifest;
    final refusal = grants.refusalOf(manifest);
    if (refusal != null) throw PermissionException(refusal);

    final files = <String, Uint8List>{
      for (final path in document.resources)
        path: await _read(manifest, path, source),
    };
    String textOf(String path) => utf8.decode(files[path]!);

    // Read before anything is installed, as every other file is: a section
    // whose files do not read refuses the plugin here, not halfway through
    // an install.
    final context = DataSectionContext(plugin: manifest.id, textOf: textOf);
    final Map<String, Object> loaded;
    try {
      loaded = <String, Object>{
        for (final MapEntry(key: name, value: (:reader, :section))
            in document.sections.entries)
          name: reader.load(section, context),
      };
    } on Flutter3dFormatException catch (error) {
      throw DataPluginFormatException(error.message);
    }

    return DataPlugin._(
      document,
      <(String, String)>[
        for (final material in document.materials)
          switch (material) {
            DataMaterial(:final String text) => (
              '${manifest.id} (inline)',
              text,
            ),
            DataMaterial(:final source) => (source!, textOf(source)),
          },
      ],
      <String, Map<String, String>>{
        for (final step in document.renderSteps)
          step.name: <String, String>{
            for (final MapEntry(key: backend, value: path)
                in step.shaders.entries)
              RuntimeBackends.normalize(backend)!: textOf(path),
          },
      },
      <String, WasmModule>{
        for (final system in document.wasm)
          system.system: WasmModule.decode(files[system.module]!),
      },
      <String, String>{
        for (final script in document.scripts)
          script.system: textOf(script.source),
      },
      wasmRuntime,
      Map<String, Object>.unmodifiable(loaded),
    );
  }

  Future<Uint8List> _read(
    PluginManifest manifest,
    String path,
    PluginSource source,
  ) {
    final uri = Uri.tryParse(path);
    final scheme = uri?.scheme ?? '';
    if (scheme == 'http' || scheme == 'https') {
      grants.require(
        manifest,
        PluginPermission.network,
        forWhat: 'to fetch $path',
      );
      final door = fetch;
      if (door == null) {
        throw PermissionException(
          'plugin "${manifest.id}" is granted network to fetch $path, and the '
          'loader was given no fetch to do it through',
        );
      }
      return door(uri!);
    }
    final outside =
        scheme == 'file' ||
        path.startsWith('/') ||
        path.startsWith(r'\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
        path.split(RegExp(r'[\\/]')).contains('..');
    if (outside) {
      grants.require(
        manifest,
        PluginPermission.files,
        forWhat: 'to read $path, outside its own directory',
      );
      final door = readFile;
      if (door == null) {
        throw PermissionException(
          'plugin "${manifest.id}" is granted files to read $path, and the '
          'loader was given no readFile to do it through',
        );
      }
      return door(scheme == 'file' ? uri!.toFilePath() : path);
    }
    if (scheme.isNotEmpty) {
      throw DataPluginFormatException(
        'plugin "${manifest.id}" names $path, and "$scheme:" is not a place '
        'a plugin\'s files can be: a path inside its directory, an https '
        'URL or, granted files, a path outside it',
      );
    }
    return source.read(path);
  }
}

/// A plugin read from a `.f3dplugin` document, with every file it named
/// already in memory.
///
/// Installed like any `Flutter3dPlugin`: through the engine's host, at a step
/// boundary, switched off by withdrawing what it registered. Its install is
/// synchronous because the loader read everything first; a material or a
/// render step then arrives asynchronously from the device and draws from
/// the frame after.
///
/// [save] and [restore] carry the state its Wasm systems and scripts keep
/// outside the world, for an application's snapshot and for the debug
/// double-step check, which must cover everything a step system writes.
final class DataPlugin extends Flutter3dPlugin {
  DataPlugin._(
    this.document,
    this._materials,
    this._stages,
    this._modules,
    this._scripts,
    this._wasmRuntime,
    this._sections,
  );

  /// The document it was read from.
  final DataPluginDocument document;

  /// Each material's source text, with the name its messages give it.
  final List<(String, String)> _materials;

  /// Each render step's stages, by step name and then by backend.
  final Map<String, Map<String, String>> _stages;

  /// Each Wasm system's module, decoded, by system name.
  final Map<String, WasmModule> _modules;

  /// Each script's text, by system name.
  final Map<String, String> _scripts;

  final WasmRuntime _wasmRuntime;

  /// Each registered section of [document], as its reader loaded it, by
  /// name.
  final Map<String, Object> _sections;

  final List<WasmSystem> _wasmSystems = <WasmSystem>[];
  final List<ScriptSystem> _scriptSystems = <ScriptSystem>[];
  final List<String> _notes = <String>[];

  @override
  PluginManifest get manifest => document.manifest;

  /// What the last install left out and why: materials on an engine that
  /// draws nothing, a material its backend cannot compile, a section no
  /// subsystem read, and what a section's own install left out (an effect on
  /// an engine that draws nothing, what an effect asked for that this build
  /// does not do). A plugin list shows these beside the plugin.
  List<String> get notes => List<String>.unmodifiable(_notes);

  @override
  void install(PluginHost host) {
    _wasmSystems.clear();
    _scriptSystems.clear();
    _notes.clear();
    final id = manifest.id;

    for (final phase in document.phases) {
      host.loop.addPhase(phase.phase, after: phase.after, before: phase.before);
    }
    for (final event in document.events) {
      host.events.declare<PluginDataEvent>(
        '$id.${event.name}',
        description: event.description,
        codec: PluginDataEvent.codecFor('$id.${event.name}'),
      );
    }
    if (document.entityKinds.isNotEmpty) {
      final kinds = host.maybeRegistry<EntityKinds>();
      if (kinds == null) {
        throw PluginException(
          'plugin "$id" declares entity kinds '
          '(${document.entityKinds.map((k) => k.type).join(', ')}), and this '
          'engine has no EntityKinds to add them to',
        );
      }
      kinds.addAll(document.entityKinds);
    }
    _installShaders(host);
    for (final spec in document.wasm) {
      _wasmSystems.add(
        installWasmSystem(
          host,
          spec,
          _modules[spec.system]!,
          runtime: _wasmRuntime,
        ),
      );
    }
    for (final spec in document.scripts) {
      _scriptSystems.add(
        installScriptSystem(host, spec, _scripts[spec.system]!),
      );
    }
    // What its systems keep outside the world is part of the loop's
    // snapshots, under the plugin's id: a rewind, a rollback and the
    // double-step check cover a module's memory and a script's fields as
    // they cover the world.
    if (_wasmSystems.isNotEmpty || _scriptSystems.isNotEmpty) {
      host.maybeRegistry<SnapshotRegistry>()?.add(
        SnapshotPart.of(
          id: id,
          capture: save,
          restore: (data, _) {
            if (data is Map) restore(data.cast<String, Object?>());
          },
        ),
      );
    }
    _installSections(host);
  }

  /// Hands each registered section to the subsystem that read it, through
  /// the plugin's view of the host, so switching the plugin off takes out
  /// what each installed; and notes every section nobody read.
  void _installSections(PluginHost host) {
    final id = manifest.id;
    for (final name in document.extra.keys) {
      if (FormatSpec.envelopeKeys.contains(name)) continue;
      _notes.add(
        'section "$name" kept and not read: no subsystem this plugin was '
        'loaded with reads it',
      );
    }
    // A trigger naming one of the plugin's own events means the name it is
    // declared under on the bus; any other name is the engine's or another
    // plugin's, as written.
    final declared = <String>{for (final event in document.events) event.name};
    final context = DataSectionContext(
      plugin: id,
      eventName: (event) => declared.contains(event) ? '$id.$event' : event,
      numbersOf: numbersOfDataEvent,
      note: _notes.add,
    );
    for (final MapEntry(key: name, value: (:reader, section: _))
        in document.sections.entries) {
      reader.install(host, _sections[name]!, context);
    }
  }

  /// The numbers a [PluginDataEvent] carries, each read as [Fixed16]: what
  /// a script or a module that wants its events placed publishes, a
  /// position first and then a direction. Null for any other event.
  static List<double>? numbersOfDataEvent(BusEvent event) => switch (event) {
    PluginDataEvent(:final values) => List<double>.unmodifiable(
      values.map(Fixed16.toDouble),
    ),
    _ => null,
  };

  void _installShaders(PluginHost host) {
    if (_materials.isEmpty && document.renderSteps.isEmpty) return;
    final id = manifest.id;
    if (host.backend == null) {
      _notes.add(
        'materials and render steps not loaded: this engine draws nothing',
      );
      return;
    }
    final shaders = host.maybeRegistry<RuntimeShaders>();
    if (shaders == null) {
      throw PluginException(
        'plugin "$id" brings materials or render steps, and this engine has '
        'no RuntimeShaders to compile them; hand one to the engine among its '
        'registries',
      );
    }
    for (final (from, text) in _materials) {
      shaders.addMaterial(text, from: from);
    }
    if (document.renderSteps.isEmpty) return;
    final steps = host.maybeRegistry<RendererSteps>();
    if (steps == null) {
      throw PluginException(
        'plugin "$id" brings render steps, and this engine has no '
        'RendererSteps to add them to; hand the renderer\'s renderSteps to '
        'the engine among its registries',
      );
    }
    for (final step in document.renderSteps) {
      // Through the renderer, which knows the anchors other plugins added
      // as well as the engine's.
      final anchor = DataPluginDocument._anchorIn(steps.anchors, step.anchor);
      if (anchor == null) {
        throw PluginException(
          'plugin "$id": render step "${step.name}" is placed at '
          '"${step.anchor}", which is not an anchor of this renderer; the '
          'anchors are ${steps.anchors.map((a) => a.name).join(', ')}. A '
          'plugin\'s own anchor has to be added before this one is installed',
        );
      }
      if (!anchor.isEngine) {
        DataPluginDocument._checkSide(
          'render step "${step.name}"',
          anchor,
          present: step.present,
        );
      }
      shaders.addRenderStep(
        RuntimeRenderStep(
          name: '$id.${step.name}',
          anchor: anchor,
          shaders: _stages[step.name]!,
          present: step.present,
          needs: step.needs,
          after: step.after,
          before: step.before,
        ),
        steps,
      );
    }
  }

  /// The state its systems keep outside the world, by system name.
  Map<String, Object?> save() => <String, Object?>{
    for (final system in _wasmSystems) system.name: system.save(),
    for (final script in _scriptSystems) script.name: script.save(),
  };

  /// Puts back what [save] returned. A system [state] does not name keeps
  /// what it has.
  void restore(Map<String, Object?> state) {
    for (final system in _wasmSystems) {
      final saved = state[system.name];
      if (saved is Map<String, Object?>) system.restore(saved);
    }
    for (final script in _scriptSystems) {
      if (state.containsKey(script.name)) script.restore(state[script.name]);
    }
  }
}
