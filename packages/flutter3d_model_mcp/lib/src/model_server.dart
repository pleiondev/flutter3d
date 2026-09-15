import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';

import 'model_session.dart';
import 'model_tools.dart';
import 'render_tool.dart';

/// The version this server tells a client it is. Kept beside the pubspec's.
const String modelMcpVersion = '0.1.0';

/// [tool]'s own [Answer], carried into a [PictureAnswer] with a null `png` —
/// every tool in [modelTools] answers this way; [renderTool] (`mcp-06n`) is
/// the one tool built against [PictureAnswer] directly, since it is the one
/// tool that actually draws. This is the seam that keeps the other hundred or
/// so tool bodies in `model_tools.dart` untouched: the server answers in one
/// type because [ToolTableServer] is generic over exactly one, and this is
/// where that type is decided rather than in every tool that has no picture
/// to offer.
ModelPictureTool _picture(ModelTool tool) => ModelPictureTool(tool.tool, (
  ModelSession session,
  Map<String, Object?> arguments,
) async {
  final Answer answer = await tool.run(session, arguments);
  return (did: answer.did, says: answer.says, png: null);
});

/// A model project, offered to an agent as a table of tools.
///
/// **One project, one process, and no window** — the same shape
/// `flutter3d_editor_mcp` chose, and for the same reason: a socket into a
/// running editor, so an agent and a person share one view, is two writers on
/// one undo stack and a camera that has to follow somebody else's selection.
/// This is the half that can be checked without a GPU: a process started by
/// `dart run`, one `ModelHistory` in it, deterministic text out, and a suite
/// that drives the real protocol over a pair of streams in memory. `render`
/// draws a real picture through `flutter3d_cpu`'s own `CpuDevice` without
/// costing this guarantee — see `render_tool.dart`'s own doc comment, and
/// `tool/structure/repository.dart`'s `flatDartPackages` entry for
/// `flutter3d_cpu`, for why that dependency no longer carries the Flutter SDK
/// in.
///
/// Everything a server is beyond its tools — registering them, turning an
/// answer into a result — is `flutter3d_mcp_kit`'s [ToolTableServer].
base class ModelMcpServer extends ToolTableServer<ModelSession, PictureAnswer> {
  /// [extraTools] is `mcp-16d`'s own door: a caller that already has a live
  /// GUI to drive (`ModelHttpServer.start`, never `bin/model_mcp.dart`'s
  /// stdio path) can offer more tools beside the ones every build gets,
  /// without this class knowing what they are. Empty for every server this
  /// package starts on its own — which is what keeps a headless
  /// `flutter3d_model_mcp` server from ever listing one.
  ModelMcpServer(
    super.channel, {
    required super.session,
    List<ModelPictureTool> extraTools = const <ModelPictureTool>[],
    super.onCall,
    super.onInitialize,
  }) : super(
         name: 'flutter3d_model_mcp',
         version: modelMcpVersion,
         instructions: _instructions,
         tools: <ModelPictureTool>[
           ...modelTools.map(_picture),
           renderTool,
           renderSheetTool,
           ...extraTools,
         ],
         toResult: pictureResultOf,
       );
}

/// What the host puts in front of the model before it calls anything.
const String _instructions = '''
A 3D model project, open and editable: objects, each a shape that still knows
its own parameters or a mesh with topology, painted with materials from a
shared table.

Work in this order: call `list` to see what is there and what id each thing
has, `select` some of it, then the commands that change it. Commands that add
something — `addPrimitive`, `addLathe` — select what they made; everything
else that moves or deletes acts on the current selection. Mesh commands
(`extrude`, `loopCut`, …) need `select` with an `object` and a `level` first.

`check` says what is wrong with the project as an export would see it, and is
worth calling before `export`. `save` writes the project's own format;
`export` writes `.f3d`, `.glb`, `.obj`, `.stl` or `.usdz` for something else to
read. `import` brings another file's objects in. `journal` writes every command
run this session to a recovery file.

`undo`/`redo` walk the history one step at a time, where a step is whatever one
tool call did — except a drag of many small changes, which nothing here can
send as one call anyway.
''';
