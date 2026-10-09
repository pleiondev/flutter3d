/// The MCP servers of the plain Dart packages, built here and read back.
///
/// **Built, not read from source**, because what a server offers is what its
/// constructor makes of its tools, and only the constructor knows that: the
/// modeller widens every command that acts on a selection with the target
/// arguments, and wraps every tool twice on the way in. A server built over
/// a channel nobody writes to, with a session holding an empty document,
/// answers `tools` with exactly what `tools/list` would.
///
/// **One entry per server class**, so a server added to one of these
/// packages and not here is refused by `bin/schema_snapshot.dart` rather
/// than left out of the snapshot. A package that needs Flutter is not here:
/// it cannot be built under `dart run`, and `serversFromSource` reads it.
library;

import 'package:flutter3d_build/flutter3d_build.dart'
    show PluginAuthorMcpServer, PluginWorkshop;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart' show Editing;
import 'package:flutter3d_mcp/editor.dart';
import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_mcp/model.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart'
    show ModelHistory, ModelProject;
import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;
import 'package:stream_channel/stream_channel.dart';

import 'schema_snapshot.dart';

/// One server, built over [channel] with a session of its own.
typedef ServerBuilder =
    ToolTableServer<Object?, Object?> Function(StreamChannel<String> channel);

/// Every server class of every plain Dart package, by package and class.
final Map<String, Map<String, ServerBuilder>> liveServers =
    <String, Map<String, ServerBuilder>>{
      // The plugin author's server, over a workshop that has run nothing:
      // its tools name a directory, so there is no document to empty.
      'flutter3d_build': <String, ServerBuilder>{
        'PluginAuthorMcpServer': (StreamChannel<String> channel) =>
            PluginAuthorMcpServer(channel, session: PluginWorkshop()),
      },
      // The level editor's server, the project server over an empty
      // registry — what it offers of its own, which is nothing; the
      // plugins' tools are each plugin's surface — and the modeller's.
      'flutter3d_mcp': <String, ServerBuilder>{
        'EditorMcpServer': (StreamChannel<String> channel) => EditorMcpServer(
          channel,
          session: EditorSession(
            Editing(level: Level(), path: 'schema-snapshot.json'),
          ),
        ),
        'ProjectMcpServer': (StreamChannel<String> channel) =>
            ProjectMcpServer(channel, tools: McpTools()),
        'ModelMcpServer': (StreamChannel<String> channel) => ModelMcpServer(
          channel,
          session: ModelSession(ModelHistory(const ModelProject())),
        ),
      },
    };

/// The surface of each server [package] builds, by building it.
Future<List<ServerSurface>> liveSurfaces(String package) async {
  final out = <ServerSurface>[];
  for (final build in liveServers[package]!.values) {
    final server = build(StreamChannelController<String>().local);
    out.add(<String, Object?>{
      'name': server.name,
      'schemaVersion': server.schemaVersion,
      'aliases': server.aliases,
      'tools': <Object?>[for (final t in server.offeredSpecs) t.toJson()],
    });
    await server.shutdown();
  }
  return out;
}
