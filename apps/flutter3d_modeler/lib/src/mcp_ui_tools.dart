/// Turns a [UiActions] into the seven `ui.*` tools `mcp-16d` offers a
/// GUI-mode agent beside the ordinary document ones — `ModelHttpServer.
/// start`'s own `extraTools`.
///
/// **Imported only from `mcp_bootstrap_io.dart`.** This file reaches
/// `package:flutter3d_model_mcp`, whose barrel export reaches `dart:io`
/// through `ModelHttpServer` — see `mcp_ui_actions.dart`'s own doc comment
/// for why that keeps this file, and not the interface it builds tools
/// from, out of anything the web build compiles.
library;

import 'package:dart_mcp/server.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';

import 'mcp_ui_actions.dart';

/// [body] wrapped the way every tool `ModelMcpServer` offers already is:
/// an [Answer]-shaped result with no picture, `session` itself unread since
/// every `ui.*` tool acts on the live screen [actions] already closes over
/// rather than on the document [session] carries.
ModelPictureTool _ui(
  Tool tool,
  UiAnswer Function(Map<String, Object?> arguments) body,
) => ModelPictureTool(tool, (
  ModelSession session,
  Map<String, Object?> arguments,
) async {
  final UiAnswer answer = body(arguments);
  return (did: answer.did, says: answer.says, png: null);
});

/// The seven tools, each a thin call into [actions] — see [UiActions] for
/// what each one does and refuses. GUI build only: nothing calls this except
/// `mcp_bootstrap_io.dart`'s own `startMcpServer`, and only when a screen
/// hands it a live [UiActions].
List<ModelPictureTool> uiToolsFor(UiActions actions) => <ModelPictureTool>[
  _ui(
    Tool(
      name: 'ui.setMode',
      description:
          'Switches the mode switcher — object, mesh, material, animation, '
          'scene, and whatever else this build offers — the same as '
          'clicking it. For driving a screenshot script. Refuses cleanly '
          'for a name the switcher does not have.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'mode': StringSchema(description: 'a mode switcher name, lowercase'),
        },
        required: <String>['mode'],
      ),
    ),
    (Map<String, Object?> arguments) =>
        actions.setMode(arguments['mode']! as String),
  ),
  _ui(
    Tool(
      name: 'ui.setSubmode',
      description:
          'Changes the open mode\'s own second switcher — the mesh mode\'s '
          'vertex/edge/face today, and whatever a later mode adds one for. '
          'Refuses cleanly for a name the open mode does not offer.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'submode': StringSchema(description: 'a submode name, lowercase'),
        },
        required: <String>['submode'],
      ),
    ),
    (Map<String, Object?> arguments) =>
        actions.setSubmode(arguments['submode']! as String),
  ),
  _ui(
    Tool(
      name: 'ui.setTool',
      description:
          'Lights the tool rail\'s id, the same as clicking it. Omit "id" '
          'to clear it back to none.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': StringSchema(
            description: 'a tool id from the rail; omit to clear',
          ),
        },
      ),
    ),
    (Map<String, Object?> arguments) =>
        actions.setTool(arguments['id'] as String?),
  ),
  _ui(
    Tool(
      name: 'ui.standardView',
      description:
          'Points the camera at one of the app\'s own six standard views.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'view': StringSchema(
            description: 'front, back, left, right, top or bottom',
          ),
        },
        required: <String>['view'],
      ),
    ),
    (Map<String, Object?> arguments) =>
        actions.standardView(arguments['view']! as String),
  ),
  _ui(
    Tool(
      name: 'ui.frameSubject',
      description:
          'Frames the current subject in the viewport, the same framing a '
          'fresh open already gives it.',
      inputSchema: ObjectSchema(),
    ),
    (Map<String, Object?> _) => actions.frameSubject(),
  ),
  _ui(
    Tool(
      name: 'ui.openDialog',
      description:
          'Opens one of this app\'s own dialogs — export, lathe, autorig, '
          'preview — without waiting for it to close, so a screenshot '
          'script can catch it on screen. Refuses cleanly for a dialog this '
          'build has not wired up yet.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'dialog': StringSchema(
            description: 'export, lathe, autorig or preview',
          ),
        },
        required: <String>['dialog'],
      ),
    ),
    (Map<String, Object?> arguments) =>
        actions.openDialog(arguments['dialog']! as String),
  ),
  _ui(
    Tool(
      name: 'ui.say',
      description:
          'Puts a sentence on the status line, marked to survive a routine '
          'clear — for a screenshot script to caption the step it is about '
          'to catch.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'text': StringSchema(description: 'the sentence to show'),
        },
        required: <String>['text'],
      ),
    ),
    (Map<String, Object?> arguments) =>
        actions.say(arguments['text']! as String),
  ),
  // `ux-25`: the command palette's own list, and the same door it presses.
  _ui(
    Tool(
      name: 'run_command',
      description:
          'Runs one of the editor\'s own commands by id — the same list the '
          'command palette shows a person, pressed the same way. Some ids '
          'arm a tool and wait for a pointer (move, rotate, scale); the '
          'rest act at once. Call it with no id to get the list back '
          'instead of running anything.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': StringSchema(
            description: 'a command id, such as "mesh.triangulate"',
          ),
        },
      ),
    ),
    (Map<String, Object?> arguments) => switch (arguments['id']) {
      final String id => actions.runCommand(id),
      // No id: the catalogue, which is what an agent that has never seen
      // this editor needs before it can ask for anything by name.
      _ => (
        did: true,
        says: actions
            .commands()
            .map(
              (({String id, String label, String mode}) it) =>
                  '${it.id} (${it.label}, ${it.mode})',
            )
            .join('\n'),
      ),
    },
  ),
];
