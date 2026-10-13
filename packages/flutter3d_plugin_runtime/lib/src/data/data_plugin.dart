import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import '../data_event.dart';
import '../permissions.dart';
import '../wasm/wasm.dart';
import '../world_fields.dart' show Fixed16;
import 'data_sections.dart';
import 'expressions.dart';

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

/// One section of a document a registered reader read: the [DataSection]
/// that read it and what its `read` returned.
///
/// A class rather than a record, so a later minor can say more of a read
/// section — where in the document it was, what it required — without
/// breaking the code that reads [reader] and [section].
final class DataPluginSection {
  const DataPluginSection({required this.reader, required this.section});

  /// The subsystem's reader that took the section.
  final DataSection reader;

  /// What [DataSection.read] made of it, which [reader] writes back.
  final Object section;
}

/// A plugin written as data: what a `.f3dplugin` file holds.
///
/// **Decision 4 of `tasks/0.9-plugins.md`: some plugins load while the game
/// runs.** A Dart plugin is compiled into the application. A data plugin is
/// a document an application reads at run time — from its assets, from a
/// mod folder, from a server — and installs through the same host, with the
/// same manifest, the same switch at a step boundary and the same journal.
///
/// **What the runtime reads itself** is what every engine has, a server that
/// replays a run included:
///
/// * `phases` — loop phases, step or frame, ordered by `after`/`before`,
///   added to the loop as `<plugin id>.<name>`;
/// * `events` — the events its systems publish, declared on the bus as
///   `<plugin id>.<name>` ([PluginDataEvent]);
/// * `wasm` — step systems in Wasm under ABI [wasmPluginAbi];
/// * `expressions` — step systems in the expression language
///   ([ExpressionSystemSpec]).
///
/// **Every other section is read by the subsystem that owns it**, through
/// the [DataSectionRegistry] the document is read with ([sections]):
/// `entityKinds` (the kinds a level may name, `flutter3d_sim`'s
/// `entityKindsSection`), `materials` and `renderSteps` (compiled where the
/// backend compiles at run time, `flutter3d_core`'s `renderDataSections`),
/// `effects` (`flutter3d_particles`' `effectsSection`), `physicalMaterials`
/// and `materialPairs` (`flutter3d_matter`'s sections). This package reads
/// none of them and depends on none of those packages, so the interpreter a
/// replaying server steps a module with resolves without the render core.
///
/// A section no registered reader takes is kept as written in [extra] and
/// written back, and [DataPlugin.notes] says it was not read.
///
/// ```json
/// {
///   "format": "f3d.plugin", "version": 4,
///   "manifest": {"id": "gusts", "apiVersion": "1.0", "touches": "simulation"},
///   "phases": [{"name": "weather", "kind": "step",
///               "after": ["physics"], "before": ["fields"]}],
///   "events": [{"name": "gust"}],
///   "wasm": [{"module": "gusts.wasm", "system": "blow", "phase": "weather",
///             "fields": [{"name": "wind", "write": true}],
///             "events": ["gust"]}]
/// }
/// ```
///
/// **Versioned, with the format policy every engine file follows**
/// (decision 8 of `tasks/1.0-stability.md`): the envelope carries the
/// version, a 1.x engine reads every 1.x document through [_migrations], a
/// document from the future is refused with the version that reads it, and
/// keys this build does not know are kept in [extra] and written back.
///
/// **JSON.** A document is written by tools as often as by hand, and the
/// package that reads it runs in a browser and on a server; a YAML front end
/// can come later without the format changing.
final class DataPluginDocument {
  const DataPluginDocument({
    required this.manifest,
    this.phases = const <DataPhase>[],
    this.events = const <DataEventDeclaration>[],
    this.wasm = const <WasmSystemSpec>[],
    this.expressions = const <ExpressionSystemSpec>[],
    this.sections = const <String, DataPluginSection>{},
    this.extra = const <String, Object?>{},
  });

  /// Bumped when an existing key changes meaning, with a step in
  /// [_migrations] and a fixture under `test/fixtures/v<N>/`.
  ///
  /// **2 is the format envelope** (`"format": "f3d.plugin", "version": 2`)
  /// in place of version 1's `"f3dplugin": 1`. No section changed meaning;
  /// a build from before looks for its version under `f3dplugin`, so it
  /// refuses a version-2 document as having none rather than misreading it.
  ///
  /// **3 has `expressions` in place of `scripts`**: interpreted Dart gave
  /// way to the expression language, and a version-2 `scripts` entry is read
  /// as an expression system with its `source` kept. A version-2 build
  /// refuses a version-3 document rather than keep its systems unread.
  ///
  /// **4 files a phase under the plugin**, as its events and Wasm systems
  /// already were: a phase named `weather` in `phases` is the loop's
  /// `<id>.weather`, and so is `weather` wherever the document orders a
  /// phase or places a system against one of its own (`after`, `before`,
  /// `wasm[].phase`, `expressions[].phase`). A name that is not one of the
  /// document's phases — the engine's `physics`, another plugin's — is the
  /// loop's name as written. A Wasm system is `<id>.<system>` in the loop,
  /// and a `wasm[].after` or `wasm[].before` that names another of the
  /// document's systems is filed the same way; any other system name is the
  /// loop's as written. In version 3 a phase was the loop's name as
  /// written, a bare one the engine could add in a minor; the lift takes
  /// `<id>.` off a version-3 name that already carried it, so it is not
  /// filed twice. A version-3 build refuses a version-4 document rather
  /// than add its phases under names the plugin does not own.
  static const int formatVersion = 4;

  /// Entry `i` lifts a document from version `i + 1` to `i + 2`. 1 → 2 is the
  /// identity: [FormatSpec.open] has read the version from `f3dplugin`.
  static const List<FormatMigration> _migrations = <FormatMigration>[
    _identity,
    _scriptsToExpressions,
    _ownPhasesBare,
  ];

  /// 3 → 4: a phase of the document's own written as `<id>.<name>`, and
  /// each reference to it, becomes `<name>`, which version 4 files under
  /// `<id>.` at install. Every other name stays as written.
  static Map<String, Object?> _ownPhasesBare(Map<String, Object?> document) {
    final id = switch (document['manifest']) {
      {'id': final String id} => id,
      _ => null,
    };
    final phases = document['phases'];
    if (id == null || phases is! List<Object?>) return document;
    final prefix = '$id.';
    final own = <String>{
      for (final phase in phases)
        if (phase case {'name': final String name}) name,
    };
    Object? bare(Object? name) =>
        name is String && name.startsWith(prefix) && own.contains(name)
        ? name.substring(prefix.length)
        : name;
    Object? names(Object? list) => switch (list) {
      final List<Object?> names => <Object?>[for (final n in names) bare(n)],
      _ => list,
    };
    Object? entries(Object? list, Set<String> keys) => switch (list) {
      final List<Object?> entries => <Object?>[
        for (final entry in entries)
          if (entry is Map<String, Object?>)
            <String, Object?>{
              for (final MapEntry(:key, :value) in entry.entries)
                key: !keys.contains(key)
                    ? value
                    : key == 'after' || key == 'before'
                    ? names(value)
                    : bare(value),
            }
          else
            entry,
      ],
      _ => list,
    };
    return <String, Object?>{
      for (final MapEntry(:key, :value) in document.entries)
        key: switch (key) {
          'phases' => entries(value, const <String>{'name', 'after', 'before'}),
          'wasm' || 'expressions' => entries(value, const <String>{'phase'}),
          _ => value,
        },
    };
  }

  static Map<String, Object?> _identity(Map<String, Object?> document) =>
      document;

  /// 2 → 3: each `scripts` entry becomes an `expressions` entry, its keys as
  /// they were. No script runtime ever shipped, so no script ran; its
  /// declaration (system, phase, fields, events) carries over, and its
  /// `source` is the file its author rewrites in the expression language.
  static Map<String, Object?> _scriptsToExpressions(
    Map<String, Object?> document,
  ) => switch (document['scripts']) {
    null => document,
    final Object? scripts => <String, Object?>{
      for (final MapEntry(:key, :value) in document.entries)
        if (key != 'scripts') key: value,
      'expressions': <Object?>[
        ...switch (document['expressions']) {
          final List<Object?> already => already,
          _ => const <Object?>[],
        },
        ...switch (scripts) {
          final List<Object?> list => list,
          _ => <Object?>[scripts],
        },
      ],
    },
  };

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
  final List<WasmSystemSpec> wasm;
  final List<ExpressionSystemSpec> expressions;

  /// The sections a registered reader read, by name: each with the
  /// [DataSection] that read it and what its [DataSection.read] returned.
  final Map<String, DataPluginSection> sections;

  /// Top-level keys this build does not know, kept as they were read.
  final Map<String, Object?> extra;

  /// Every file the document points at, in the order it names them: the
  /// Wasm modules, the expression systems' sources and what the [sections]
  /// name. What a loader reads before anything is installed.
  List<String> get resources => <String>{
    for (final system in wasm) system.module,
    for (final system in expressions) ?system.source,
    for (final DataPluginSection(:reader, :section) in sections.values)
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
      // A section's own reader refused — a Wasm system's declaration, an
      // expression system's, the manifest inside the document, a registered
      // section.
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
    // A document says what it likes about itself; the engine's rights go
    // to the code the engine ships, never to a file.
    if (manifest.isEngine) {
      throw DataPluginFormatException(
        'the document names its plugin "$id", in the engine\'s own namespace '
        '"${manifest.namespace}"; a data plugin names itself after its '
        'package and is never the engine\'s',
      );
    }

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

    final wasm = <WasmSystemSpec>[
      for (final entry in entries('wasm')) WasmSystemSpec.fromJson(entry),
    ];
    final expressions = <ExpressionSystemSpec>[
      for (final entry in entries('expressions'))
        ExpressionSystemSpec.fromJson(entry),
    ];
    // An event a system publishes is declared, so a tool listing what the
    // plugin says lists it, and two plugins cannot claim one name.
    for (final (what, published) in <(String, List<String>)>[
      for (final system in wasm)
        ('Wasm system "${system.system}"', system.events),
      for (final system in expressions)
        ('expression system "${system.system}"', system.events),
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
    final sections = <String, DataPluginSection>{
      for (final key in json.keys)
        if (!DataSections.runtimeKeys.contains(key))
          if (registry?[key] case final DataSection reader)
            key: DataPluginSection(
              reader: reader,
              section: reader.read(
                DataSectionRead(json[key], context: context),
              ),
            ),
    };

    return DataPluginDocument(
      manifest: manifest,
      phases: List<DataPhase>.unmodifiable(phases),
      events: List<DataEventDeclaration>.unmodifiable(events),
      wasm: List<WasmSystemSpec>.unmodifiable(wasm),
      expressions: List<ExpressionSystemSpec>.unmodifiable(expressions),
      sections: Map<String, DataPluginSection>.unmodifiable(sections),
      extra: Map<String, Object?>.unmodifiable(
        FormatDocument.unknownIn(
          json,
          known: <String>{...DataSections.runtimeKeys, ...sections.keys},
          spec: format,
        ),
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    ...format.envelope(
      requires: <String>{
        for (final DataPluginSection(:reader) in sections.values)
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
    if (wasm.isNotEmpty) 'wasm': <Object?>[for (final w in wasm) w.toJson()],
    if (expressions.isNotEmpty)
      'expressions': <Object?>[for (final e in expressions) e.toJson()],
    for (final MapEntry(key: name, value: DataPluginSection(:reader, :section))
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
/// and the path. A Wasm module has no import that reaches either door, and
/// an expression has none to name, so what is checked here is all the reach
/// a data plugin has.
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
  /// [DataSectionRegistry]. Without it a document's `materials`, `effects`
  /// or `entityKinds` is kept as written and not read, and a document whose
  /// `requires` names one is refused.
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
        for (final MapEntry(
              key: name,
              value: DataPluginSection(:reader, :section),
            )
            in document.sections.entries)
          name: reader.load(DataSectionLoad(section, context: context)),
      };
    } on Flutter3dFormatException catch (error) {
      throw DataPluginFormatException(error.message);
    }

    return DataPlugin._(
      document,
      <String, WasmModule>{
        for (final system in document.wasm)
          system.system: WasmModule.decode(files[system.module]!),
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
/// [save] and [restore] carry the state its Wasm systems keep outside the
/// world, for an application's snapshot and for the debug double-step
/// check, which must cover everything a step system writes.
final class DataPlugin extends Flutter3dPlugin {
  DataPlugin._(this.document, this._modules, this._wasmRuntime, this._sections);

  /// The document it was read from.
  final DataPluginDocument document;

  /// Each Wasm system's module, decoded, by system name.
  final Map<String, WasmModule> _modules;

  final WasmRuntime _wasmRuntime;

  /// Each registered section of [document], as its reader loaded it, by
  /// name.
  final Map<String, Object> _sections;

  final List<WasmSystem> _wasmSystems = <WasmSystem>[];
  final List<String> _notes = <String>[];

  @override
  PluginManifest get manifest => document.manifest;

  /// What the last install left out and why: a section no subsystem read,
  /// and what a section's own install left out (materials or effects on an
  /// engine that draws nothing, what an effect asked for that this build
  /// does not do). A plugin list shows these beside the plugin.
  List<String> get notes => List<String>.unmodifiable(_notes);

  @override
  void install(PluginHost host) {
    _wasmSystems.clear();
    _notes.clear();
    final id = manifest.id;

    if (document.expressions.isNotEmpty) {
      // Refused whole, before anything is registered: a simulation missing
      // one of its systems would replay as another simulation.
      throw PluginException(
        'plugin "$id" brings the expression systems '
        '${document.expressions.map((s) => s.system).join(', ')}, and this '
        'build of flutter3d_plugin_runtime reads them but evaluates no '
        'expression language; write the system in Wasm, or install the '
        'plugin on a build that evaluates them',
      );
    }
    // A phase of the document's own is filed under the plugin, wherever it
    // is named; any other is the loop's name as written.
    final own = <String>{for (final phase in document.phases) phase.name};
    String inLoop(String phase) => own.contains(phase) ? '$id.$phase' : phase;
    for (final phase in document.phases) {
      host.loop.addPhase(
        phase.kind == PhaseKind.frame
            ? LoopPhase.frame(inLoop(phase.name))
            : LoopPhase.step(inLoop(phase.name)),
        after: phase.after.map(inLoop).toList(),
        before: phase.before.map(inLoop).toList(),
      );
    }
    for (final event in document.events) {
      host.events.declare<PluginDataEvent>(
        '$id.${event.name}',
        description: event.description,
        codec: PluginDataEvent.codecFor('$id.${event.name}'),
      );
    }
    // So is a system of its own, which a Wasm system orders itself against
    // by the name the document gives it; another's is the loop's name.
    final ownSystems = <String>{for (final spec in document.wasm) spec.system};
    String systemInLoop(String system) =>
        ownSystems.contains(system) ? '$id.$system' : system;
    for (final spec in document.wasm) {
      _wasmSystems.add(
        installWasmSystem(
          host,
          WasmSystemSpec(
            module: spec.module,
            system: spec.system,
            phase: inLoop(spec.phase),
            after: spec.after.map(systemInLoop).toList(),
            before: spec.before.map(systemInLoop).toList(),
            fields: spec.fields,
            events: spec.events,
            limits: spec.limits,
          ),
          _modules[spec.system]!,
          runtime: _wasmRuntime,
        ),
      );
    }
    // What its systems keep outside the world is part of the loop's
    // snapshots, under the plugin's id: a rewind, a rollback and the
    // double-step check cover a module's memory as they cover the world.
    if (_wasmSystems.isNotEmpty) {
      host.maybeRegistry<SnapshotRegistry>()?.add(
        SnapshotPart.of(
          id: id,
          // 2: a module's globals by export name, its own under `internal`,
          // and the runtime that ran it; a build that reads 1 refuses it.
          version: 2,
          capture: save,
          restore: (context) {
            final data = context.data;
            if (data is Map) restore(data.cast<String, Object?>());
          },
          digest: () => _digestOf(<String, Object?>{
            for (final system in _wasmSystems) system.name: system.digestible(),
          }),
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
    for (final MapEntry(key: name, value: DataPluginSection(:reader))
        in document.sections.entries) {
      reader.install(
        DataSectionInstall(_sections[name]!, host: host, context: context),
      );
    }
  }

  /// The numbers a [PluginDataEvent] carries, each read as [Fixed16]: what
  /// a module that wants its events placed publishes, a position first and
  /// then a direction. Null for any other event.
  static List<double>? numbersOfDataEvent(BusEvent event) => switch (event) {
    PluginDataEvent(:final values) => List<double>.unmodifiable(
      values.map(Fixed16.toDouble),
    ),
    _ => null,
  };

  /// FNV-1a over [document] written as JSON, as an unsigned 32-bit number:
  /// the same on the VM and in a browser, whose integers are doubles, since
  /// every product stays under 2^53.
  static int _digestOf(Object? document) {
    var hash = 0x811C9DC5;
    for (final byte in utf8.encode(jsonEncode(document))) {
      final mixed = (hash ^ byte) & 0xFFFFFFFF;
      // × 16777619, which is 2^24 + 403, kept to 32 bits.
      hash = (mixed * 403 + ((mixed & 0xFF) << 24)) % 0x100000000;
    }
    return hash;
  }

  /// The state its systems keep outside the world, by system name.
  Map<String, Object?> save() => <String, Object?>{
    for (final system in _wasmSystems) system.name: system.save(),
  };

  /// Puts back what [save] returned. A system [state] does not name keeps
  /// what it has.
  void restore(Map<String, Object?> state) {
    for (final system in _wasmSystems) {
      final saved = state[system.name];
      if (saved is Map<String, Object?>) system.restore(saved);
    }
  }
}
