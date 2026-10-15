import 'package:flutter3d_mcp/kit.dart';

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
const String modelMcpVersion = '1.0.0-rc.1+1';

/// The version of this server's tools — names and input schemas — as the
/// `initialize` result announces it beside [modelMcpVersion].
///
/// It moves only when `api/flutter3d_mcp.mcp` does: a minor for a new
/// tool or optional argument, a major for anything that breaks a caller.
/// The tools a GUI host adds through `extraTools` are not part of it: they
/// are the host's, and no headless server lists them.
///
/// **1.0.0 with the first stable release** (decided 2026-10-09, task F3 of
/// the architecture review): the minors it counted before were moves within
/// a surface nobody had been promised yet, and a host meeting 1.2.0 at a
/// first release would look for a 1.0 and 1.1 that never shipped.
///
/// 1.1.0 with the American spellings: `paint.stroke` and
/// `paint.vertexColor` take `color` and a sample's `center`, and
/// `object.setOrigin` takes `boundsCenter`. The British words are still
/// read, so no caller breaks. `light.add` takes an `area` light, the
/// scene's fourth kind.
const String modelMcpSchemaVersion = '1.1.0';

/// What each of the modeller's tools is published as, `area.verb`, and what
/// it does to the project. The written name — the model command's own word,
/// which `history.batch` and the command journal still use — stays an alias until
/// 2.0.
const Map<String, ToolName> modelToolNames = <String, ToolName>{
  'addClip': ToolName('clip.add', hints: ToolHints.writes),
  'addImage': ToolName('image.add', hints: ToolHints.writes),
  'addJoint': ToolName('joint.add', hints: ToolHints.writes),
  'addLathe': ToolName('object.addLathe', hints: ToolHints.writes),
  'addLight': ToolName('light.add', hints: ToolHints.writes),
  'addLod': ToolName('lod.add', hints: ToolHints.writes),
  'addMaterial': ToolName('material.add', hints: ToolHints.writes),
  'addModifier': ToolName('modifier.add', hints: ToolHints.writes),
  'addNode': ToolName('textureGraph.addNode', hints: ToolHints.writes),
  'addPrimitive': ToolName('object.addPrimitive', hints: ToolHints.writes),
  'addShapeDriver': ToolName('shapeDriver.add', hints: ToolHints.writes),
  'addShapeFromMesh': ToolName('shapeKey.addFromMesh', hints: ToolHints.writes),
  'addSkeleton': ToolName('skeleton.add', hints: ToolHints.writes),
  'addSocket': ToolName('object.addSocket', hints: ToolHints.writes),
  'adoptTexture': ToolName('paint.adoptTexture', hints: ToolHints.writes),
  'amend': ToolName('history.amend', hints: ToolHints.writes),
  'applyClipResult': ToolName('clip.applyResult', hints: ToolHints.writes),
  'applyJobResult': ToolName('mesh.applyJobResult', hints: ToolHints.writes),
  'applyModifier': ToolName('modifier.apply', hints: ToolHints.writes),
  'applySimulationCache': ToolName(
    'simulation.applyCache',
    hints: ToolHints.writes,
  ),
  'applyTransform': ToolName('object.applyTransform', hints: ToolHints.writes),
  'assignMaterial': ToolName('material.assign', hints: ToolHints.writes),
  'audit': ToolName('asset.audit', hints: ToolHints.writes),
  'autoRig': ToolName('rig.auto', hints: ToolHints.writes),
  'bakeDrivers': ToolName('clip.bakeDrivers', hints: ToolHints.writes),
  'bakeIk': ToolName('clip.bakeIk', hints: ToolHints.writes),
  'bakeMaps': ToolName('texture.bakeMaps', hints: ToolHints.writes),
  'bakeRootMotionIntoClip': ToolName(
    'clip.bakeRootMotion',
    hints: ToolHints.writes,
  ),
  'bakeSimulationToShapes': ToolName(
    'simulation.bakeToShapes',
    hints: ToolHints.writes,
  ),
  'bakeTextureGraph': ToolName('textureGraph.bake', hints: ToolHints.writes),
  'bakeToMesh': ToolName('object.bakeToMesh', hints: ToolHints.writes),
  'batch': ToolName('history.batch', hints: ToolHints.writes),
  'bendJoint': ToolName('joint.bend', hints: ToolHints.writes),
  'bevelEdges': ToolName('mesh.bevel', hints: ToolHints.writes),
  'bindSkin': ToolName('skin.bind', hints: ToolHints.writes),
  'bridgeLoops': ToolName('mesh.bridgeLoops', hints: ToolHints.writes),
  'buildFrom': ToolName('object.buildFrom', hints: ToolHints.writes),
  'buildTopology': ToolName('mesh.buildTopology', hints: ToolHints.writes),
  'check': ToolName('project.check', hints: ToolHints.reads),
  'cleanup': ToolName('mesh.cleanup', hints: ToolHints.writes),
  'deleteElements': ToolName('mesh.deleteElements', hints: ToolHints.writes),
  'deleteKeys': ToolName('key.delete', hints: ToolHints.writes),
  'deleteObjects': ToolName('object.delete', hints: ToolHints.writes),
  'deleteShape': ToolName('shapeKey.delete', hints: ToolHints.writes),
  'describe': ToolName('object.describe', hints: ToolHints.reads),
  'describe_type': ToolName('type.describe', hints: ToolHints.reads),
  'dissolveEdges': ToolName('mesh.dissolveEdges', hints: ToolHints.writes),
  'drawQuad': ToolName('retopology.drawQuad', hints: ToolHints.writes),
  'duplicateMaterial': ToolName('material.duplicate', hints: ToolHints.writes),
  'duplicateObjects': ToolName('object.duplicate', hints: ToolHints.writes),
  'embedMaterial': ToolName('material.embed', hints: ToolHints.writes),
  'export': ToolName('project.export', hints: ToolHints.destroys),
  'extractRootMotion': ToolName(
    'clip.extractRootMotion',
    hints: ToolHints.writes,
  ),
  'extrude': ToolName('mesh.extrude', hints: ToolHints.writes),
  'fillHoles': ToolName('mesh.fillHoles', hints: ToolHints.writes),
  'growSelection': ToolName('selection.grow', hints: ToolHints.writes),
  'import': ToolName('project.import', hints: ToolHints.writes),
  'insetFaces': ToolName('mesh.inset', hints: ToolHints.writes),
  'inspect': ToolName('project.inspect', hints: ToolHints.reads),
  'invertSelection': ToolName('selection.invert', hints: ToolHints.writes),
  'journal': ToolName('project.journal', hints: ToolHints.destroys),
  'keyShape': ToolName('shapeKey.key', hints: ToolHints.writes),
  'link': ToolName('textureGraph.link', hints: ToolHints.writes),
  'linkMaterialFile': ToolName('material.linkFile', hints: ToolHints.writes),
  'linkToSource': ToolName('object.linkSource', hints: ToolHints.writes),
  'list': ToolName('project.list', hints: ToolHints.reads),
  'listMaterials': ToolName('material.list', hints: ToolHints.reads),
  'loopCut': ToolName('mesh.loopCut', hints: ToolHints.writes),
  'makeGameReady': ToolName('project.makeGameReady', hints: ToolHints.writes),
  'markSeam': ToolName('uv.markSeam', hints: ToolHints.writes),
  'mergeByDistance': ToolName('mesh.mergeByDistance', hints: ToolHints.writes),
  'mirrorJoints': ToolName('joint.mirror', hints: ToolHints.writes),
  'moveBy': ToolName('selection.move', hints: ToolHints.writes),
  'moveKeys': ToolName('key.move', hints: ToolHints.writes),
  'moveNode': ToolName('textureGraph.moveNode', hints: ToolHints.writes),
  'packAtlas': ToolName('uv.packAtlas', hints: ToolHints.writes),
  'paintStroke': ToolName('paint.stroke', hints: ToolHints.writes),
  'paintVertexColour': ToolName('paint.vertexColor', hints: ToolHints.writes),
  'paintWeights': ToolName('skin.paintWeights', hints: ToolHints.writes),
  'poseJoint': ToolName('joint.pose', hints: ToolHints.writes),
  'recalculateNormals': ToolName(
    'mesh.recalculateNormals',
    hints: ToolHints.writes,
  ),
  'redo': ToolName('history.redo', hints: ToolHints.writes),
  'regenerateLods': ToolName('lod.regenerate', hints: ToolHints.writes),
  'reimport': ToolName('object.reimport', hints: ToolHints.writes),
  'removeAnimationGraph': ToolName(
    'animationGraph.remove',
    hints: ToolHints.writes,
  ),
  'removeJoint': ToolName('joint.remove', hints: ToolHints.writes),
  'removeLight': ToolName('light.remove', hints: ToolHints.writes),
  'removeMaterial': ToolName('material.remove', hints: ToolHints.writes),
  'removeModifier': ToolName('modifier.remove', hints: ToolHints.writes),
  'removeNode': ToolName('textureGraph.removeNode', hints: ToolHints.writes),
  'removeShapeDriver': ToolName('shapeDriver.remove', hints: ToolHints.writes),
  'rename': ToolName('object.rename', hints: ToolHints.writes),
  'renameJoint': ToolName('joint.rename', hints: ToolHints.writes),
  'renameShape': ToolName('shapeKey.rename', hints: ToolHints.writes),
  'render': ToolName('view.render', hints: ToolHints.reads),
  'renderSheet': ToolName('view.renderSheet', hints: ToolHints.reads),
  'renderSnapshot': ToolName('view.renderSnapshot', hints: ToolHints.reads),
  'reorderModifier': ToolName('modifier.reorder', hints: ToolHints.writes),
  'reparentJoint': ToolName('joint.reparent', hints: ToolHints.writes),
  'retargetClip': ToolName('clip.retarget', hints: ToolHints.writes),
  'retopologize': ToolName('mesh.retopologize', hints: ToolHints.writes),
  'rotateBy': ToolName('selection.rotate', hints: ToolHints.writes),
  'save': ToolName('project.save', hints: ToolHints.destroys),
  'scaleBy': ToolName('selection.scale', hints: ToolHints.writes),
  'sculptStroke': ToolName('sculpt.stroke', hints: ToolHints.writes),
  'select': ToolName('selection.set', hints: ToolHints.writes),
  'selectAll': ToolName('selection.all', hints: ToolHints.writes),
  'selectByMaterial': ToolName('selection.byMaterial', hints: ToolHints.writes),
  'selectEdgeLoop': ToolName('selection.edgeLoop', hints: ToolHints.writes),
  'selectEdgeRing': ToolName('selection.edgeRing', hints: ToolHints.writes),
  'selectFacing': ToolName('selection.facing', hints: ToolHints.writes),
  'selectLinked': ToolName('selection.linked', hints: ToolHints.writes),
  'selectNear': ToolName('selection.near', hints: ToolHints.writes),
  'selectNone': ToolName('selection.none', hints: ToolHints.writes),
  'separate': ToolName('mesh.separate', hints: ToolHints.writes),
  'setAnimationGraph': ToolName('animationGraph.set', hints: ToolHints.writes),
  'setEnvironment': ToolName('scene.setEnvironment', hints: ToolHints.writes),
  'setInterpolation': ToolName(
    'track.setInterpolation',
    hints: ToolHints.writes,
  ),
  'setKey': ToolName('key.set', hints: ToolHints.writes),
  'setLightField': ToolName('light.setField', hints: ToolHints.writes),
  'setLightTransform': ToolName('light.setTransform', hints: ToolHints.writes),
  'setLodRatio': ToolName('lod.setRatio', hints: ToolHints.writes),
  'setMaterialField': ToolName('material.setField', hints: ToolHints.writes),
  'setMaterialGraph': ToolName('textureGraph.set', hints: ToolHints.writes),
  'setModifierField': ToolName('modifier.setField', hints: ToolHints.writes),
  'setNodeField': ToolName(
    'textureGraph.setNodeField',
    hints: ToolHints.writes,
  ),
  'setObjectLocked': ToolName('object.setLocked', hints: ToolHints.writes),
  'setObjectVisible': ToolName('object.setVisible', hints: ToolHints.writes),
  'setOrigin': ToolName('object.setOrigin', hints: ToolHints.writes),
  'setPanorama': ToolName('scene.setPanorama', hints: ToolHints.writes),
  'setParametric': ToolName('object.setParametric', hints: ToolHints.writes),
  'setParent': ToolName('object.setParent', hints: ToolHints.writes),
  'setProfileLimits': ToolName('rig.setLimits', hints: ToolHints.writes),
  'setRestPose': ToolName('joint.setRestPose', hints: ToolHints.writes),
  'setRig': ToolName('rig.set', hints: ToolHints.writes),
  'setSceneLightingField': ToolName(
    'scene.setLightingField',
    hints: ToolHints.writes,
  ),
  'setShapeDriverField': ToolName(
    'shapeDriver.setField',
    hints: ToolHints.writes,
  ),
  'setShapeWeight': ToolName('shapeKey.setWeight', hints: ToolHints.writes),
  'setTangent': ToolName('key.setTangent', hints: ToolHints.writes),
  'setTexture': ToolName('material.setTexture', hints: ToolHints.writes),
  'setTransform': ToolName('object.setTransform', hints: ToolHints.writes),
  'shrinkSelection': ToolName('selection.shrink', hints: ToolHints.writes),
  'slideEdges': ToolName('mesh.slideEdges', hints: ToolHints.writes),
  'subdivideMesh': ToolName('mesh.subdivide', hints: ToolHints.writes),
  'toggleModifier': ToolName('modifier.toggle', hints: ToolHints.writes),
  'toggleModifierExport': ToolName(
    'modifier.toggleExport',
    hints: ToolHints.writes,
  ),
  'transformElements': ToolName(
    'mesh.transformElements',
    hints: ToolHints.writes,
  ),
  'triangulate': ToolName('mesh.triangulate', hints: ToolHints.writes),
  'undo': ToolName('history.undo', hints: ToolHints.writes),
  'unlink': ToolName('textureGraph.unlink', hints: ToolHints.writes),
  'unlinkSource': ToolName('object.unlinkSource', hints: ToolHints.writes),
  'unwrap': ToolName('uv.unwrap', hints: ToolHints.writes),
  'validateRig': ToolName('rig.validate', hints: ToolHints.reads),
};

/// [tool]'s own [Answer], carried into a [Answer] with a null `png` —
/// every tool in [modelTools] answers this way; [renderTool] (`mcp-06n`) is
/// the one tool built against [Answer] directly, since it is the one
/// tool that actually draws. This is the seam that keeps the other hundred or
/// so tool bodies in `model_tools.dart` untouched: the server answers in one
/// type because [ToolTableServer] is generic over exactly one, and this is
/// where that type is decided rather than in every tool that has no picture
/// to offer.
ModelPictureTool _picture(ModelTool tool) =>
    ModelPictureTool(tool.spec, (call) async {
      final Answer answer = await tool.run(call);
      return Answer(did: answer.did, says: answer.says, png: null);
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
  tool.spec.copyWith(outputSchema: modelAnswerSchema),
  (call) async {
    final session = call.session;
    final List<int> before = session.objectIds;
    // `ux-20`: cleared here rather than by whoever sets it, so that a
    // targeted call's own selection is reported by the call that made it
    // and by no call after it.
    session.reportedSelection = null;
    final Answer answer = await tool.run(call);
    _made = session.madeSince(before);
    return answer;
  },
);

/// The shape of every model tool's `structuredContent` — what
/// `ModelSession.structured` writes — as the `outputSchema` each tool
/// declares.
const Map<String, Object?> modelAnswerSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'did': <String, Object?>{'type': 'boolean'},
    'says': <String, Object?>{'type': 'string'},
    'ids': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'integer'},
    },
    'selection': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'mode': <String, Object?>{'type': 'string'},
        'objects': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'integer'},
        },
        'level': <String, Object?>{'type': 'string'},
        'elements': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'integer'},
        },
        'object': <String, Object?>{'type': 'integer'},
      },
      'required': <String>['mode', 'objects'],
    },
  },
  'required': <String>['did', 'says', 'ids', 'selection'],
};

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
ToolResult _resultOf(Answer answer, ModelSession session) {
  final ToolResult base = pictureResultOf(answer);
  return ToolResult(
    content: base.content,
    isError: base.isError,
    structuredContent: session.structured(
      Answer(did: answer.did, says: answer.says),
      made: _made,
    ),
  );
}

/// A model project, offered to an agent as a table of tools.
///
/// **One project, one process, and no window** — the same shape
/// `flutter3d_mcp/editor.dart` chose, and for the same reason: a socket into a
/// running editor, so an agent and a person share one view, is two writers on
/// one undo stack and a camera that has to follow somebody else's selection.
/// This is the half that can be checked without a GPU: a process started by
/// `dart run`, one `ModelHistory` in it, deterministic text out, and a suite
/// that drives the real protocol over a pair of streams in memory. `view.render`
/// draws a real picture through `flutter3d_cpu`'s own `CpuDevice` without
/// costing this guarantee — see `render_tool.dart`'s own doc comment, and
/// `tool/structure/repository.dart`'s `flatDartPackages` entry for
/// `flutter3d_cpu`, for why that dependency no longer carries the Flutter SDK
/// in.
///
/// Everything a server is beyond its tools — registering them, turning an
/// answer into a result — is `flutter3d_mcp/kit.dart`'s [ToolTableServer].
base class ModelMcpServer extends ToolTableServer<ModelSession, Answer> {
  /// [extraTools] is `mcp-16d`'s own door: a caller that already has a live
  /// GUI to drive (`ModelHttpServer.start`, never `bin/model_mcp.dart`'s
  /// stdio path) can offer more tools beside the ones every build gets,
  /// without this class knowing what they are. Empty for every server this
  /// package starts on its own — which is what keeps a headless
  /// `flutter3d_mcp/model.dart` server from ever listing one.
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
    super.projectTools,
    super.onProjectCall,
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
         name: 'flutter3d.model',
         version: modelMcpVersion,
         schemaVersion: modelMcpSchemaVersion,
         names: modelToolNames,
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
         toResult: (Answer answer) => _resultOf(answer, session),
         // `ux-43`: an argument this server does not take is refused by name
         // rather than ignored, and the refusal travels back the same way an
         // edit's own does — structured, marked as an error, readable.
         refusal: (String says) => Answer(did: false, says: says, png: null),
         prompts: modelPrompts,
       );
}

/// What the host puts in front of the model before it calls anything.
const String _instructions = '''
A 3D model project, open and editable: objects, each a shape that still knows
its own parameters or a mesh with topology, painted with materials from a
shared table.

Every tool is named for what it acts on and what it does to it:
`object.addPrimitive`, `mesh.extrude`. The names from before 1.0
(`addPrimitive`, `extrude`) still answer, and are the command names
`history.batch` takes inside its list.

Work in this order: `project.list` to see what is there and each thing's id,
`selection.set` some of it, then the commands that change it. Commands that
add something select what they made; everything else acts on the selection.
Mesh commands (`mesh.extrude`, `mesh.loopCut`, …) need `selection.set` with an
`object` and a `level` first.

Do not guess an element id. `object.describe` says where every vertex, edge
and face of an object is and which way it faces; `selection.facing` picks the
faces pointing a given way ("the top" is an axis of [0,1,0]) and
`selection.near` a region round a point. Every answer's `structuredContent`
says what the call did, the ids it created and what is selected now.

`view.render` draws one of seven views and `view.renderSheet` four at once.
`history.amend` replaces the step on top of the undo stack, so an extrude
tried at 0.5 can be tried at 0.3 without leaving both. `mesh.cleanup`,
`project.makeGameReady` and `object.buildFrom` are recipes, each one step.
`type.describe` says what fields a modifier, a shape or a texture node takes.
The `modelling_strategy` prompt is the order to do all of it in.

`project.check` says what an export would object to; `asset.audit` checks and
repairs an imported asset. `project.save` writes the project's own format,
`project.export` writes `.f3d`, `.glb`, `.obj`, `.stl` or `.usdz`,
`project.import` brings another file's objects in, and `project.journal`
writes this session's commands to a recovery file. `history.undo` and
`history.redo` walk one tool call at a time; `history.batch` runs several
commands as one step, taken back whole if any of them refuses.

Units, everywhere: distances are metres, angles are radians unless a field
says degrees, the world is Y-up and right-handed, and a transform is sixteen
numbers in `Matrix4.storage` (column-major) order. An argument this server
does not take is refused by name rather than ignored: a sentence about a key
means a misspelling.
''';
