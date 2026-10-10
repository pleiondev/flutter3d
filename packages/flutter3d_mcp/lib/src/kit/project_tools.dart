/// The tools plugins bring, merged into one project's MCP servers under each
/// plugin's id.
library;

import 'dart:async';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'tool_spec.dart';

/// What calling a project tool does: its arguments in, a result out.
///
/// **A [ToolResult] rather than a server's own answer type**, because a
/// plugin's tool is offered by every server of the project and each of them
/// speaks a different answer: the editor's carries a picture, the
/// modeller's a selection. A result is what all of them send in the end.
typedef ProjectToolRun =
    FutureOr<ToolResult> Function(Map<String, Object?> arguments);

/// One tool a plugin, or the application, added to a project's [McpTools].
final class ProjectTool {
  ProjectTool._(
    this.spec,
    this.run, {
    required this.namespace,
    required this.owner,
    required this._scope,
    required this._sequence,
  });

  /// What `tools/list` offers: the tool as it was added, under its published
  /// name, `<namespace>.<name>`.
  final ToolSpec spec;

  final ProjectToolRun run;

  /// The plugin's id, or the namespace the application named.
  final String namespace;

  /// Who added it, as a refusal says it: `plugin "wind"` or `the
  /// application`.
  final String owner;

  final PluginScope? _scope;
  final int _sequence;

  /// The published name, `<namespace>.<name>`.
  String get name => spec.name;

  int get _rank => _scope?.rank ?? -1;

  static int _compare(ProjectTool a, ProjectTool b) {
    final byRank = a._rank.compareTo(b._rank);
    return byRank != 0 ? byRank : a._sequence.compareTo(b._sequence);
  }
}

/// MCP tools, merged into the project's servers as `<plugin id>.<tool>`:
/// the slot [McpTools] fills, `host.registry<McpTools>()`.
///
/// **Declared by the package that fills it.** It was a marker in
/// `flutter3d_plugin_api` until 1.0.0-rc.1, which named a slot nothing in
/// the contract used.
abstract base class McpToolRegistry extends PluginRegistry {
  const McpToolRegistry();
}

/// The [McpToolRegistry] a project fills: the MCP tools its plugins bring,
/// each under the plugin's id.
///
/// **Decision 19 of the plugin plan: a plugin brings everything, its tools
/// for an agent included.** A plugin's `install` asks the host for this type,
/// `host.registry<McpTools>()`, and gets a view scoped to the plugin: a tool
/// added through it is published as `<plugin id>.<name>` — `wind.gust` — so
/// two plugins can each have a `reset` and neither shadows the other or a
/// server's own. Switching the plugin off withdraws its tools; a running
/// server hears it and tells its client the list changed.
///
/// ```dart
/// void install(PluginHost host) {
///   final tools = host.registry<McpTools>()..declareSchemaVersion('1.0.0');
///   tools.addTool(
///     ToolSpec(
///       name: 'gust',
///       description: 'Blow once, as hard as asked.',
///       inputSchema: {
///         'type': 'object',
///         'properties': {'strength': {'type': 'number'}},
///       },
///     ),
///     (Map<String, Object?> arguments) => ToolResult.text('blew'),
///   );
/// }
/// ```
///
/// **A plugin asks for the `tools` permission to add one.** Its manifest
/// lists `PluginPermission.tools`, so a person installing it reads that it
/// talks to agents; a plugin that did not ask is refused at [addTool] with a
/// [PluginException] naming it.
///
/// **Each namespace versions its own tools.** [declareSchemaVersion] gives
/// the namespace's schema version, by the same rule a server's follows; it
/// travels in each of its tools' `_meta` and in every server's
/// `flutter3d.schema` answer, and `schema_snapshot --plugin` writes the
/// plugin's tools to its own `api/<package>.mcp`.
///
/// **One per project, handed to the plugin host and to every server.** The
/// engine gets it among its registries — `EngineLoop(registries: [tools])` —
/// and each server takes it as `projectTools`, so the editor's, the
/// simulation's and the modeller's servers all offer the same plugin tools
/// beside their own. [ProjectMcpServer] offers them alone, for a project
/// with no other server running. The application's own tools go through the
/// root with a namespace it names: `tools.addTool(tool, run, namespace:
/// 'game')`.
///
/// **Ordered as every registry is**: the application's first, then each
/// plugin's in install order, and within one owner as they were added.
///
/// **Snapshotted by the package that brings them.** A server built without
/// this offers exactly what `api/<package>.mcp` lists; the tools added here
/// are a plugin's surface, versioned with the plugin.
final class McpTools extends McpToolRegistry {
  /// An empty registry: the root, which the application owns.
  McpTools() : _store = _ToolStore(), _scope = null;

  McpTools._scoped(McpTools root, PluginScope scope)
    : _store = root._store,
      _scope = scope;

  final _ToolStore _store;
  final PluginScope? _scope;

  /// The published name of a tool called [name] under [namespace].
  static String published(String namespace, String name) => '$namespace.$name';

  /// What a tool's own name may be: letters, digits, `_` and `-`. The dot is
  /// the namespace's, so a name cannot pretend to be under another one.
  static final RegExp _namePattern = RegExp(r'^[A-Za-z0-9_\-]+$');

  /// What a namespace the application names may be: a plugin id's own
  /// shape, so the two read alike in a list.
  static final RegExp _namespacePattern = RegExp(r'^[a-z][a-z0-9_.\-]*$');

  /// The longest published name; MCP hosts are told to expect no more.
  static const int maxNameLength = 128;

  /// Every tool added, in order: the application's, then each plugin's by
  /// install order, and within one owner as added.
  List<ProjectTool> get tools => List<ProjectTool>.unmodifiable(
    _store.tools.toList()..sort(ProjectTool._compare),
  );

  /// The tool published as [name], or null.
  ProjectTool? named(String name) =>
      _store.tools.where((ProjectTool t) => t.name == name).firstOrNull;

  /// Adds [tool], to be run by [run], published as `<namespace>.<name>`.
  ///
  /// Through a plugin's view the namespace is the plugin's id, and
  /// [namespace] must be left out or be that id. Through the root the
  /// application names one; the root refuses a tool without it.
  ///
  /// Throws an [ArgumentError] for a name that is not letters, digits, `_`
  /// and `-`, for a published name longer than [maxNameLength], and for one
  /// already added — naming who added it. Throws a [PluginException] when a
  /// plugin whose manifest does not list [PluginPermission.tools] adds one.
  Registration addTool(ToolSpec tool, ProjectToolRun run, {String? namespace}) {
    final scope = _scope;
    final String space;
    if (scope != null) {
      final id = scope.manifest.id;
      if (!scope.manifest.permissions.contains(PluginPermission.tools)) {
        throw PluginException(
          'plugin "$id" adds the MCP tool "${tool.name}" without asking for '
          'the `tools` permission: list PluginPermission.tools in its '
          'manifest, so whoever installs it sees that it talks to agents',
        );
      }
      if (namespace != null && namespace != id) {
        throw ArgumentError.value(
          namespace,
          'namespace',
          'plugin "$id" adds its tools under its own id, not "$namespace"',
        );
      }
      space = id;
    } else {
      if (namespace == null) {
        throw ArgumentError.value(
          tool.name,
          'tool',
          'the application names the namespace its tools go under: '
              'addTool(tool, run, namespace: \'game\')',
        );
      }
      if (!_namespacePattern.hasMatch(namespace)) {
        throw ArgumentError.value(
          namespace,
          'namespace',
          'a namespace is lower case letters, digits, "_", "." and "-", '
              'starting with a letter, as a plugin id is',
        );
      }
      space = namespace;
    }
    if (!_namePattern.hasMatch(tool.name)) {
      throw ArgumentError.value(
        tool.name,
        'tool',
        'a tool\'s name is letters, digits, "_" and "-"; the namespace '
            'and its dot are added for it',
      );
    }
    final name = published(space, tool.name);
    if (name.length > maxNameLength) {
      throw ArgumentError.value(
        name,
        'tool',
        'is ${name.length} characters published; at most $maxNameLength',
      );
    }
    final owner = scope == null
        ? 'the application'
        : 'plugin "${scope.manifest.id}"';
    if (named(name) case final ProjectTool taken) {
      throw ArgumentError.value(
        name,
        'tool',
        'is already added, by ${taken.owner}; $owner cannot add it again',
      );
    }
    final added = ProjectTool._(
      tool.copyWith(
        name: name,
        meta: <String, Object?>{
          'flutter3d/schemaVersion': ?_store.schemaVersions[space],
        },
      ),
      run,
      namespace: space,
      owner: owner,
      scope: scope,
      sequence: _store.sequence++,
    );
    _store.tools.add(added);
    _store.changed();
    // By sequence rather than identity: a version declared later replaces
    // the entry with one carrying it (see [declareSchemaVersion]).
    final registration = Registration(() {
      final before = _store.tools.length;
      _store.tools.removeWhere(
        (ProjectTool t) => t._sequence == added._sequence,
      );
      if (_store.tools.length != before) _store.changed();
    });
    scope?.track(registration);
    return registration;
  }

  /// Gives the schema version of the tools under this view's namespace — the
  /// plugin's id, or [namespace] through the root — by the rule a server's
  /// schema version follows: a new tool or optional argument is a minor, a
  /// removed tool or a new required argument a major.
  ///
  /// **Honoured whenever it is called.** Tools of the namespace added
  /// before it are given the version in their `_meta` too, and a running
  /// server offers them again with it, so a plugin that declares after
  /// adding is not left announcing nothing. Through a plugin's view
  /// [namespace] must be left out.
  ///
  /// Returns the [Registration] that withdraws the declaration. Through a
  /// plugin's view it is also withdrawn when the plugin is switched off, as
  /// its tools are, so `flutter3d.schema` stops naming a namespace whose
  /// tools are gone.
  Registration declareSchemaVersion(String version, {String? namespace}) {
    final scope = _scope;
    final space = scope?.manifest.id ?? namespace;
    if (space == null) {
      throw ArgumentError.value(
        version,
        'version',
        'the application names the namespace the version is for',
      );
    }
    if (scope != null && namespace != null && namespace != space) {
      throw ArgumentError.value(
        namespace,
        'namespace',
        'plugin "$space" declares its own namespace\'s version only',
      );
    }
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      throw ArgumentError.value(version, 'version', 'is not MAJOR.MINOR.PATCH');
    }
    _store.schemaVersions[space] = version;
    _store.restamp(space);
    _store.changed();
    final registration = Registration(() {
      if (_store.schemaVersions[space] != version) return;
      _store.schemaVersions.remove(space);
      _store.restamp(space);
      _store.changed();
    });
    scope?.track(registration);
    return registration;
  }

  /// The schema version each namespace declared, by namespace.
  Map<String, String> get schemaVersions =>
      Map<String, String>.unmodifiable(_store.schemaVersions);

  /// Calls [onChange] whenever a tool is added or withdrawn, until the
  /// registration it returns is cancelled. What a running server listens
  /// with, to keep its `tools/list` in step.
  ///
  /// Not tracked by a plugin's scope: a listener is a server's, not a
  /// plugin's.
  Registration listen(void Function() onChange) {
    final entry = _Listener(onChange);
    _store.listeners.add(entry);
    return Registration(() => _store.listeners.remove(entry));
  }

  @override
  McpTools forPlugin(PluginScope scope) => McpTools._scoped(this, scope);
}

/// What a project's [McpTools] and all its scoped views share.
final class _ToolStore {
  final List<ProjectTool> tools = <ProjectTool>[];
  final List<_Listener> listeners = <_Listener>[];
  final Map<String, String> schemaVersions = <String, String>{};
  int sequence = 0;

  /// Every tool under [namespace] again, its `_meta` saying the namespace's
  /// schema version now, or none. New entries, so a server that compares by
  /// identity offers them again.
  void restamp(String namespace) {
    final version = schemaVersions[namespace];
    for (var i = 0; i < tools.length; i++) {
      final t = tools[i];
      if (t.namespace != namespace) continue;
      tools[i] = ProjectTool._(
        ToolSpec(
          name: t.spec.name,
          description: t.spec.description,
          inputSchema: t.spec.inputSchema,
          outputSchema: t.spec.outputSchema,
          hints: t.spec.hints,
          meta: <String, Object?>{
            for (final MapEntry(:key, :value) in t.spec.meta.entries)
              if (key != 'flutter3d/schemaVersion') key: value,
            'flutter3d/schemaVersion': ?version,
          },
        ),
        t.run,
        namespace: t.namespace,
        owner: t.owner,
        scope: t._scope,
        sequence: t._sequence,
      );
    }
  }

  void changed() {
    for (final listener in List<_Listener>.of(listeners)) {
      listener.onChange();
    }
  }
}

/// One listener, as its own object so two equal closures are two entries.
final class _Listener {
  _Listener(this.onChange);

  final void Function() onChange;
}
