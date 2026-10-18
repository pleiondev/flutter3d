/// The plugins this editor installs, and the registries they fill:
/// [EditorPieces] for the inspector, the palette, the commands, the gizmos,
/// the importers and the asset browser (with the hints it brings along),
/// [EditorPanels] for the panels and docks, [McpTools] for an agent, and
/// [Decoders] for the models the viewport reads.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' show Decoders;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart'
    show EditorPanels;
import 'package:flutter3d_mcp/project_tools.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_sim/data_plugins.dart' show entityKindsSection;
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;

import '../plugins.g.dart';

/// What the editor's plugins brought, and the host they were installed in.
///
/// **An [EngineLoop] that never steps is the host.** The plugin host belongs
/// to the loop, and the editor has no simulation to run; its loop is built,
/// installs the plugins into the registries handed to it, and is left alone.
/// A plugin that only adds editor pieces, panels, tools or decoders is
/// complete there. One that adds systems has them registered and never run,
/// which is what an editor that does not play wants of it — Play runs the
/// game in a process of its own.
///
/// **The compiled ones and the project's.** [installedPlugins] is what
/// `lib/plugins.g.dart` says this application's dependencies declare
/// (`flutter3d plugins` writes it); a list passed to [EditorPlugins.new]
/// replaces it, as decision 3 of the plugin plan has it. Beside them come
/// the data plugins of the project the open level belongs to, the
/// `.f3dplugin` documents under its `assets/plugins` ([forProject]), read
/// with their `editor:` and `entityKinds:` sections: a Dart plugin is code
/// and can only be compiled in, while a data plugin is a file the editor
/// reads like the level.
///
/// **A plugin that will not install leaves the editor without plugins, not
/// without an editor.** A render-step plugin asks for a registry this host
/// does not have — the editor's renderer is made after a device is, long
/// after this — and the host refuses it by throwing. That is caught here,
/// kept in [refusal] for the console to say, and the editor goes on with the
/// registries empty. A data plugin that does not read is left out alone,
/// and [notes] says why.
final class EditorPlugins {
  /// The registries of [plugins], or of the discovered ones when null, with
  /// the [project]'s data plugins after them; [notes] are said about data
  /// plugins that did not read.
  factory EditorPlugins({
    List<Flutter3dPlugin>? plugins,
    List<Flutter3dPlugin> project = const <Flutter3dPlugin>[],
    List<String> notes = const <String>[],
  }) {
    final given = <Flutter3dPlugin>[
      ...plugins ?? installedPlugins.plugins,
      ...project,
    ];
    final registries = _Registries();
    try {
      return EditorPlugins._(
        registries,
        loop: _host(registries, given),
        refusal: null,
        notes: notes,
      );
    } on Object catch (error) {
      // Fresh registries: the refused install may have added to these.
      return EditorPlugins.none(refusal: '$error', notes: notes);
    }
  }

  /// No plugins at all, with [refusal] saying why when it is not by choice.
  factory EditorPlugins.none({
    String? refusal,
    List<String> notes = const <String>[],
  }) {
    final registries = _Registries();
    return EditorPlugins._(
      registries,
      loop: _host(registries, const <Flutter3dPlugin>[]),
      refusal: refusal,
      notes: notes,
    );
  }

  EditorPlugins._(
    _Registries registries, {
    required this.loop,
    required this.refusal,
    required List<String> notes,
  }) : pieces = registries.pieces,
       panels = registries.panels,
       tools = registries.tools,
       decoders = registries.decoders,
       notes = List<String>.unmodifiable(notes);

  /// The compiled plugins and the data plugins of the project whose root is
  /// [root], read through [listFiles] and [readBytes]; the compiled ones
  /// alone when [root] is null.
  ///
  /// [listFiles] answers the files under a directory, relative to it.
  static Future<EditorPlugins> forProject(
    String? root, {
    required List<String> Function(String directory) listFiles,
    required Future<Uint8List> Function(String path) readBytes,
    List<Flutter3dPlugin>? plugins,
  }) async {
    if (root == null) return EditorPlugins(plugins: plugins);
    final loader = DataPluginLoader(
      sections: DataSections(<DataSection>[editorSection, entityKindsSection]),
    );
    final project = <Flutter3dPlugin>[];
    final notes = <String>[];
    for (final path in projectPluginPaths(listFiles(root))) {
      final directory = path.substring(0, path.lastIndexOf('/'));
      try {
        final text = utf8.decode(await readBytes('$root/$path'));
        project.add(
          await loader.load(
            text,
            _ProjectSource(
              (String file) => readBytes('$root/$directory/$file'),
            ),
          ),
        );
        notes.add('plugins: $path read from the project');
      } on Object catch (error) {
        notes.add('plugins: $path left out — $error');
      }
    }
    return EditorPlugins(plugins: plugins, project: project, notes: notes);
  }

  static EngineLoop _host(_Registries registries, List<Flutter3dPlugin> all) =>
      EngineLoop(
        input: InputState(),
        registries: <PluginRegistry>[
          registries.pieces,
          registries.panels,
          registries.tools,
          registries.decoders,
        ],
        plugins: all,
      );

  /// The inspector's components and hints, the palette's entries, the
  /// commands, the gizmos, the importers and the asset browser's entries the
  /// plugins brought.
  final EditorPieces pieces;

  /// The panels and docks the plugins brought.
  final EditorPanels panels;

  /// The plugins' MCP tools, for a server started beside the editor as its
  /// `projectTools`.
  final McpTools tools;

  /// The model and material decoders and the asset sources the plugins
  /// brought, which every model the viewport reads goes through.
  final Decoders decoders;

  /// The host the plugins are installed in; see the class's doc.
  final EngineLoop loop;

  /// Why no plugin was installed, or null when every one that could run did.
  final String? refusal;

  /// What reading the project's data plugins said, a line each: which were
  /// read, and which were left out and why.
  final List<String> notes;

  /// Every installed plugin and whether it is on, for the console.
  List<PluginStatus> get statuses => loop.plugins.statuses;
}

final class _Registries {
  final EditorPieces pieces = EditorPieces();
  final EditorPanels panels = EditorPanels();
  final McpTools tools = McpTools();
  final Decoders decoders = Decoders();
}

/// A data plugin's own files, read beside its document.
final class _ProjectSource extends PluginSource {
  const _ProjectSource(this._read);

  final Future<Uint8List> Function(String path) _read;

  @override
  Future<Uint8List> read(String path) => _read(path);
}
