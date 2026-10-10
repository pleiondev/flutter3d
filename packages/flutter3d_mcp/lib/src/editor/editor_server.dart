import 'package:flutter3d_mcp/kit.dart';

import 'editor_session.dart';
import 'editor_tools.dart';

/// The version this server tells a client it is: the pubspec's.
///
/// A constant, because a compiled server has no pubspec to read. It said
/// 0.1.0 while the package moved on, since "kept beside the pubspec's" was a
/// comment and nothing checked it; `server_version_test.dart` does now.
const String editorMcpVersion = '1.0.0-rc.1';

/// The version of this server's tools — names and input schemas — as the
/// `initialize` result announces it beside [editorMcpVersion].
///
/// It moves only when `api/flutter3d_mcp.mcp` does: a minor for a new
/// tool or optional argument, a major for anything that breaks a caller.
///
/// **1.0.0 with the first stable release** (decided 2026-10-09, task F3 of
/// the architecture review): the minors it counted before were moves within
/// a surface nobody had been promised yet, and a host meeting 1.2.0 at a
/// first release would look for a 1.0 and 1.1 that never shipped.
const String editorMcpSchemaVersion = '1.0.0';

/// What each of [editorTools] is published as, `area.verb`, and what it does
/// to the document. The name a tool is written under — the editor command's
/// own word, which `EditorCommand.fromJson` reads — stays answerable as an
/// alias until 2.0.
const Map<String, ToolName> editorToolNames = <String, ToolName>{
  'addBrush': ToolName('brush.add', ToolHints.writes),
  'addLight': ToolName('light.add', ToolHints.writes),
  'applyOverrides': ToolName('prefab.applyOverrides', ToolHints.writes),
  'brighten': ToolName('light.brighten', ToolHints.writes),
  'capture_draw': ToolName('capture.draw', ToolHints.reads),
  'capture_open': ToolName('capture.open', ToolHints.reads),
  'command.run': ToolName('command.run', ToolHints.writes),
  'createPrefab': ToolName('prefab.create', ToolHints.writes),
  'delete': ToolName('selection.delete', ToolHints.writes),
  'duplicate': ToolName('selection.duplicate', ToolHints.writes),
  'generate': ToolName('kit.place', ToolHints.writes),
  'generate_level': ToolName('level.generate', ToolHints.destroys),
  'list': ToolName('level.list', ToolHints.reads),
  'moveBy': ToolName('selection.move', ToolHints.writes),
  'optimizeLights': ToolName('light.optimize', ToolHints.writes),
  'place': ToolName('level.place', ToolHints.writes),
  'placePrefab': ToolName('prefab.place', ToolHints.writes),
  'play': ToolName('play.start', ToolHints(openWorld: true)),
  'play_build': ToolName(
    'play.build',
    ToolHints(readOnly: true, openWorld: true),
  ),
  'play_devices': ToolName(
    'play.devices',
    ToolHints(readOnly: true, openWorld: true),
  ),
  'play_events': ToolName('play.events', ToolHints.reads),
  // Writes over a tape kept under the same name.
  'play_keep_tape': ToolName('play.keepTape', ToolHints.destroys),
  'play_send_level': ToolName('play.sendLevel', ToolHints.writes),
  'play_status': ToolName('play.status', ToolHints.reads),
  'play_stop': ToolName('play.stop', ToolHints.destroys),
  'play_swap': ToolName('play.swap', ToolHints.writes),
  'prefabs': ToolName('prefab.list', ToolHints.reads),
  'redo': ToolName('history.redo', ToolHints.writes),
  'removeBehaviour': ToolName('behavior.remove', ToolHints.writes),
  'removeCutscene': ToolName('cutscene.remove', ToolHints.writes),
  // Writes over whatever file is at the path it is given.
  'render_capture_save': ToolName('render.saveCapture', ToolHints.destroys),
  'render_debug_views': ToolName('render.debugViews', ToolHints.reads),
  'render_draw': ToolName('render.draw', ToolHints.reads),
  'render_draws': ToolName('render.draws', ToolHints.reads),
  'render_memory': ToolName('render.memory', ToolHints.reads),
  'render_pass_output': ToolName('render.passOutput', ToolHints.reads),
  'render_passes': ToolName('render.passes', ToolHints.reads),
  'render_pick': ToolName('render.pick', ToolHints.reads),
  'render_read_pixel': ToolName('render.readPixel', ToolHints.reads),
  'render_scan_nan': ToolName('render.scanNan', ToolHints.reads),
  'render_stats': ToolName('render.stats', ToolHints.reads),
  'report': ToolName('view.report', ToolHints.reads),
  'resize': ToolName('selection.resize', ToolHints.writes),
  'revertOverrides': ToolName('prefab.revertOverrides', ToolHints.writes),
  'save': ToolName('level.save', ToolHints.destroys),
  'screenshot': ToolName('view.screenshot', ToolHints.reads),
  'select': ToolName('selection.set', ToolHints.writes),
  'setBehaviour': ToolName('behavior.set', ToolHints.writes),
  'setCutscene': ToolName('cutscene.set', ToolHints.writes),
  'setField': ToolName('selection.setField', ToolHints.writes),
  'setLights': ToolName('light.replaceAll', ToolHints.writes),
  'setOverride': ToolName('prefab.setOverride', ToolHints.writes),
  'setPrefabField': ToolName('prefab.setField', ToolHints.writes),
  'turn': ToolName('selection.turn', ToolHints.writes),
  'undo': ToolName('history.undo', ToolHints.writes),
  'unpackPrefab': ToolName('prefab.unpack', ToolHints.writes),
  'validate': ToolName('level.validate', ToolHints.reads),
};

/// A level editor, offered to an agent as a table of tools.
///
/// **One document, one process, and no window.** The alternative — a socket
/// into a running editor, so an agent and a person share a view — is a
/// different program and a much harder one: two writers on one undo stack, a
/// camera that has to follow somebody else's selection, and a test that needs
/// a GPU before it can assert anything. This is the small half, and it is the
/// half that can be checked: a process started by `dart run`, one `Editing` in
/// it, deterministic text out, and a suite that drives the real protocol over a
/// pair of streams in memory.
///
/// Everything it can do to the document is an `EditorCommand` — the same values
/// the keyboard and the inspector in `apps/flutter3d_editor` go through — so an
/// agent's edit and a person's edit land on the document by one route, get one
/// name in the history, and are undone by the same key. What a server is beyond
/// its tools is `flutter3d_mcp/kit.dart`'s [ToolTableServer].
base class EditorMcpServer
    extends ToolTableServer<EditorSession, PictureAnswer> {
  // `session` is a plain parameter, as `ModelMcpServer`'s is: `toResult`
  // closes over it, and a super parameter cannot be named in the initializer
  // list that forwards it.
  // ignore: use_super_parameters
  EditorMcpServer(
    super.channel, {
    required EditorSession session,
    super.projectTools,
    super.onProjectCall,
  }) : super(
         session: session,
         name: 'flutter3d.editor',
         version: editorMcpVersion,
         schemaVersion: editorMcpSchemaVersion,
         names: editorToolNames,
         instructions: _instructions,
         tools: <EditorTool>[
           for (final EditorTool tool in editorTools)
             tool.withSpec(
               tool.spec.copyWith(outputSchema: editorAnswerSchema),
             ),
         ],
         toResult: (PictureAnswer answer) => _resultOf(answer, session),
       );
}

/// The shape of every editor tool's `structuredContent`, as the
/// `outputSchema` each tool declares: whether the call did what it was asked
/// ([did], false for a refusal), its sentence, the selection after it in the
/// words `level.list` uses, and whether a picture came with it.
///
/// **The same four keys for every tool**, so an agent reads one shape
/// whatever it called, and a refusal is told apart from a success without
/// parsing the sentence.
const Map<String, Object?> editorAnswerSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'did': <String, Object?>{'type': 'boolean'},
    'says': <String, Object?>{'type': 'string'},
    'selection': <String, Object?>{'type': 'string'},
    'hasPicture': <String, Object?>{'type': 'boolean'},
  },
  'required': <String>['did', 'says', 'selection', 'hasPicture'],
};

/// [answer] as a result: the sentence and the picture, and beside them the
/// machine-readable half [editorAnswerSchema] describes.
ToolResult _resultOf(PictureAnswer answer, EditorSession session) {
  final ToolResult base = pictureResultOf(answer);
  return ToolResult(
    content: base.content,
    isError: base.isError,
    structuredContent: <String, Object?>{
      'did': answer.did,
      'says': answer.says,
      'selection': session.selection,
      'hasPicture': answer.png != null,
    },
  );
}

/// What the host puts in front of the model before it calls anything.
///
/// Short on purpose. The three facts an agent gets wrong without being told are
/// all here — that a selection has to be made before most verbs do anything,
/// that indices move when something is deleted, and that a generated document
/// will not be written over — and the rest is in the tools' own descriptions,
/// where it is read at the moment it matters.
const String _instructions = '''
A level document for a flutter3d game, open and editable. It is JSON: some
materials, a list of boxes called brushes, a list of lights, and a list of
entities — everything else the game names, each a position and a word.

Every tool is named for what it acts on and what it does to it: `brush.add`,
`selection.move`, `prefab.place`. The names from before 1.0 (`addBrush`,
`moveBy`) still answer, and say what to call instead.

Work in this order: call `level.list` to see what is there and what index
each thing has, `selection.set` one of them, then the verbs that change it.
`level.place`, `brush.add` and `light.add` do not need a selection;
everything else does. Deleting renumbers what follows it, so call
`level.list` again afterwards rather than counting. `command.run` runs any
command the editor knows by name, a plugin's (`<plugin id>.<name>`)
included.

`level.validate` says what is wrong with the document as the game would see
it, and is worth calling before `level.save`. `history.undo` goes back sixty-four steps.

`view.screenshot` draws the level in software, untextured, from a camera you may
name; `view.report` says for every brush, light and entity how much of it that
camera sees and what is in the way. Look before and after you change things.

`play.start` runs the game this level belongs to. While it runs, every
`level.save` goes to it and the game takes the level without starting over; `play.status`
shows its console, `play.events` what the game posted since a cursor (a level
loaded, the player died), and `play.swap` puts changed code into it.
''';
