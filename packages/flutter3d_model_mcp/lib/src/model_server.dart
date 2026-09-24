import 'package:dart_mcp/server.dart' show CallToolResult;
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';

import 'model_prompts.dart';
import 'model_session.dart';
import 'model_tools.dart';
import 'render_tool.dart';

/// The version this server tells a client it is: the pubspec's.
///
/// A constant, because a compiled server has no pubspec to read. It said
/// 0.1.0 while the package moved through 0.6.0 to 0.7.0, since "kept beside
/// the pubspec's" was a comment and nothing checked it;
/// `server_version_test.dart` does now.
const String modelMcpVersion = '0.8.0';

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

/// [tool], with the ids it made recorded around it — `ux-19`.
///
/// **The bracket is here because only here knows where a call begins.**
/// `structuredContent` promises an agent the ids of what the call it just made
/// created, and "what the newest history step made" is a different question:
/// a call that makes no step at all would answer with the previous call's new
/// objects, which is worse than answering with none. So the object ids are
/// taken before the tool runs and diffed after, whichever tool it was — the
/// render tools included, which answer with an empty list and are honest about
/// it rather than repeating whatever the last edit made.
ModelPictureTool _watched(ModelPictureTool tool) => ModelPictureTool(
  tool.tool,
  (ModelSession session, Map<String, Object?> arguments) async {
    final List<int> before = session.objectIds;
    // `ux-20`: cleared here rather than by whoever sets it, so that a
    // targeted call's own selection is reported by the call that made it
    // and by no call after it.
    session.reportedSelection = null;
    final PictureAnswer answer = await tool.run(session, arguments);
    _made = session.madeSince(before);
    return answer;
  },
);

/// What the call that is answering right now created.
///
/// **A variable between the two halves of one call, and that is safe here for
/// the reason the whole server rests on: one session, one project, and — since
/// `dart_mcp` awaits a tool body before it builds the result — no second call
/// running between this being written and [_resultOf] reading it.** The
/// alternative was widening `Answer` itself, which is a record two packages
/// and a few hundred call sites use to mean "did it, and what to say".
List<int> _made = const <int>[];

/// [answer] as a result, with `ux-19`'s own machine-readable half beside the
/// sentence: what the call did, what it made, and what is selected now.
CallToolResult _resultOf(PictureAnswer answer, ModelSession session) {
  final CallToolResult base = pictureResultOf(answer);
  return CallToolResult(
    content: base.content,
    isError: base.isError,
    structuredContent: session.structured((
      did: answer.did,
      says: answer.says,
    ), made: _made),
  );
}

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
  // `session` is a plain parameter rather than a `super.session`, and the
  // lint that asks for one is off here: the initializer list below has to
  // name it, because `toResult` closes over it — a super parameter cannot be
  // referred to from the very initializer list that forwards it.
  // ignore: use_super_parameters
  ModelMcpServer(
    super.channel, {
    required ModelSession session,
    List<ModelPictureTool> extraTools = const <ModelPictureTool>[],
    super.pausedBecause,
    super.onCall,
    void Function(String clientName)? onInitialize,
  }) : super(
         session: session,
         // `ux-45`: the name the client said hello with is what every step
         // this session makes is stamped with, so an undo stack shared with
         // a person — and possibly with a second agent — says which of them
         // did what. Set here rather than left to each caller's own hook,
         // because a caller that forgot would leave the stack unable to tell
         // two agents apart and nothing would say so.
         onInitialize: (String clientName) {
           session.client = clientName;
           onInitialize?.call(clientName);
         },
         name: 'flutter3d_model_mcp',
         version: modelMcpVersion,
         instructions: _instructions,
         tools: <ModelPictureTool>[
           for (final ModelPictureTool tool in <ModelPictureTool>[
             ...modelTools.map(_picture),
             renderTool,
             renderSheetTool,
             renderSnapshotTool,
             auditTool,
             ...extraTools,
           ])
             _watched(tool),
         ],
         // `ux-19`: a closure over the session rather than the bare
         // `pictureResultOf`, because the structured half of an answer is
         // read off the session after the call — what is selected now, and
         // what this call made.
         toResult: (PictureAnswer answer) => _resultOf(answer, session),
         // `ux-43`: an argument this server does not take is refused by name
         // rather than ignored, and the refusal travels back the same way an
         // edit's own does — structured, marked as an error, readable.
         refusal: (String says) => (did: false, says: says, png: null),
         prompts: modelPrompts,
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

Do not guess an element id. `describe` says where every vertex, edge and face
of an object is, which way it faces and how big it is, and `selectFacing`
picks the faces pointing a given way — "the top" is `selectFacing` with an
axis of [0,1,0], not a number you hoped was right. `selectNear` takes a region
round a point. Every answer also carries `structuredContent`: what the call
did, the ids of any objects it created, and what is selected now — so the id
of something you just duplicated or imported is in the reply rather than
something to go looking for.

`render` draws the project from one of seven views and `renderSheet` draws four
at once — the cheap way to see whether a shape is right before editing it
again. `amend` replaces the step on top of the undo stack rather than adding a
second one, which is how you try an extrude at 0.3 after trying it at 0.5.
`cleanup`, `makeGameReady` and `buildFrom` are recipes: a run of edits that is
the same every time, as one step. `describe_type` says what fields a modifier
kind, a shape or a texture node takes. The `modelling_strategy` prompt is the
order to do all of it in.

`check` says what is wrong with the project as an export would see it; `audit`
checks an imported asset's size, origin and meshes, and can repair them. `save` writes the project's own format;
`export` writes `.f3d`, `.glb`, `.obj`, `.stl` or `.usdz` for something else to
read. `import` brings another file's objects in. `journal` writes every command
run this session to a recovery file.

`undo`/`redo` walk the history one step at a time, where a step is whatever one
tool call did — except a drag of many small changes, which nothing here can
send as one call anyway. `batch` is the other way round: several commands as
one step, taken back whole if any of them refuses.

Units, everywhere: distances are metres, angles are radians unless a field
says degrees, the world is Y-up and right-handed, and a transform is sixteen
numbers in `Matrix4.storage` (column-major) order. An argument this server
does not take is refused by name rather than ignored, so a call that comes
back with a sentence about a key is a call with a misspelling in it, not a
project that would not do what you asked.
''';
