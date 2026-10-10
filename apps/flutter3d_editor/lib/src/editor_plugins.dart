/// The plugins this editor installs, and the three registries they fill:
/// [EditorPieces] for the inspector, the palette and the commands, [McpTools]
/// for an agent, and [Decoders] for the models the viewport reads.
library;

import 'package:flutter3d/flutter3d.dart' show Decoders;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_mcp/project_tools.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;

import '../plugins.g.dart';

/// What the editor's plugins brought, and the host they were installed in.
///
/// **An [EngineLoop] that never steps is the host.** The plugin host belongs
/// to the loop, and the editor has no simulation to run; its loop is built,
/// installs the plugins into the registries handed to it, and is left alone.
/// A plugin that only adds editor pieces, tools or decoders is complete
/// there. One that adds systems has them registered and never run, which is
/// what an editor that does not play wants of it — Play runs the game in a
/// process of its own.
///
/// **The generated list unless one is given.** [installedPlugins] is what
/// `lib/plugins.g.dart` says this application's dependencies declare
/// (`dart run flutter3d_build:plugins` writes it); a list passed to
/// [EditorPlugins.new] replaces it, as decision 3 of the plugin plan has it.
///
/// **A plugin that will not install leaves the editor without plugins, not
/// without an editor.** A render-step plugin asks for a registry this host
/// does not have — the editor's renderer is made after a device is, long
/// after this — and the host refuses it by throwing. That is caught here,
/// kept in [refusal] for the console to say, and the editor goes on with the
/// three registries empty.
final class EditorPlugins {
  factory EditorPlugins({List<Flutter3dPlugin>? plugins}) {
    final pieces = EditorPieces();
    final tools = McpTools();
    final decoders = Decoders();
    final given = plugins ?? installedPlugins;
    try {
      return EditorPlugins._(
        pieces: pieces,
        tools: tools,
        decoders: decoders,
        loop: _host(pieces, tools, decoders, given),
        refusal: null,
      );
    } on Object catch (error) {
      // Fresh registries: the refused install may have added to these.
      return EditorPlugins.none(refusal: '$error');
    }
  }

  /// No plugins at all, with [refusal] saying why when it is not by choice.
  factory EditorPlugins.none({String? refusal}) {
    final pieces = EditorPieces();
    final tools = McpTools();
    final decoders = Decoders();
    return EditorPlugins._(
      pieces: pieces,
      tools: tools,
      decoders: decoders,
      loop: _host(pieces, tools, decoders, const <Flutter3dPlugin>[]),
      refusal: refusal,
    );
  }

  EditorPlugins._({
    required this.pieces,
    required this.tools,
    required this.decoders,
    required this.loop,
    required this.refusal,
  });

  static EngineLoop _host(
    EditorPieces pieces,
    McpTools tools,
    Decoders decoders,
    List<Flutter3dPlugin> plugins,
  ) => EngineLoop(
    input: InputState(),
    registries: <PluginRegistry>[pieces, tools, decoders],
    plugins: plugins,
  );

  /// The inspector's components, the palette's entries and the commands the
  /// plugins brought.
  final EditorPieces pieces;

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

  /// Every installed plugin and whether it is on, for the console.
  List<PluginStatus> get statuses => loop.plugins.statuses;
}
