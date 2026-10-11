/// A plugin's editor commands, offered to an agent as tools of their own.
library;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Registration;

import 'editor_session.dart';

/// Offers every command the plugins added to [pieces] as a tool of [tools],
/// `<namespace>.<name>`, that runs it on [session]'s document; keeps the
/// offer in step while plugins are switched on and off, until the
/// registration it returns is cancelled.
///
/// **One command, two doors.** A plugin registers `sink` once, with
/// `EditorPieces.addCommand`; the editor's menu offers it, `command.run`
/// reads it by name, and an agent sees `boats.sink` in `tools/list` with
/// the command's own argument hints as its input schema. Whichever door it
/// comes through, it is the same command on the same history.
///
/// A plugin that adds an MCP tool of the same name itself keeps it: its own
/// tool is the one offered, and the command stays reachable through
/// `command.run`. A command added by the application, without a plugin's
/// id, is not offered here: `command.run` reaches it.
Registration shareCommands(
  EditorPieces pieces,
  McpTools tools,
  EditorSession session,
) {
  final offered = <String, Registration>{};

  void sync() {
    final wanted = <String, PluginCommandInfo>{
      for (final command in pieces.pluginCommands)
        if (command.plugin != null) command.name: command,
    };
    for (final name in offered.keys.toList()) {
      if (wanted.containsKey(name)) continue;
      offered.remove(name)!.cancel();
    }
    for (final MapEntry(key: name, value: command) in wanted.entries) {
      if (offered.containsKey(name) || tools.named(name) != null) continue;
      offered[name] = tools.addTool(
        ToolSpec(
          name: command.bareName,
          description:
              command.description ??
              'The ${command.plugin} plugin\'s editor command '
                  '${command.bareName}.',
          inputSchema: commandInputSchema(command),
        ),
        (Map<String, Object?> arguments) {
          final read = pieces.readCommand(<String, Object?>{
            ...arguments,
            'command': name,
          });
          if (read == null) {
            return ToolResult.text(
              '$name cannot be read from those arguments',
              isError: true,
            );
          }
          final (:did, :says) = session.run(read);
          return ToolResult.text(says, isError: !did);
        },
        namespace: command.namespace,
      );
    }
  }

  sync();
  final listening = pieces.listen(sync);
  return Registration(() {
    listening.cancel();
    for (final registration in offered.values) {
      registration.cancel();
    }
    offered.clear();
  });
}

/// [command]'s arguments as a tool's input schema: an object with one
/// property per argument hint, each required when it has no default.
Map<String, Object?> commandInputSchema(
  PluginCommandInfo command,
) => <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    for (final argument in command.arguments) argument.key: argument.jsonSchema,
  },
  'required': <String>[
    for (final argument in command.arguments)
      if (argument.defaultValue == null) argument.key,
  ],
};
