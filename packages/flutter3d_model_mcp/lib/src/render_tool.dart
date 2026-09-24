/// `render`: `mcp-06n`'s own tool — a picture of the project, from one of
/// seven named views, as real MCP image content rather than a base64 string
/// inside a text block. Built on `renderProject` (`mcp-05n`,
/// `flutter3d_model_core`) and `flutter3d_cpu`'s own `CpuDevice`.
///
/// **A separate file, and its own [OfferedTool] answer type.** Every other
/// tool in [modelTools] answers with a plain [Answer] — no picture, ever —
/// and `render` is the one tool a real project's own picture belongs beside.
/// Rather than migrate a hundred existing tool bodies to a [PictureAnswer]
/// each carrying a null `png`, `model_server.dart` wraps [modelTools] once at
/// the point they are handed to the server; this file only has to define the
/// one tool that actually draws.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:dart_mcp/server.dart';
import 'package:flutter3d_core/flutter3d_core.dart' show PerspectiveProjection;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart';

import 'model_session.dart';

typedef ModelPictureTool = OfferedTool<ModelSession, PictureAnswer>;

GraphicsDevice _cpuDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// [value] as one of [RenderProjectView.values], or [RenderProjectView.iso]
/// for anything else — the same tolerant fallback `_lightingModelNamed`
/// (`flutter3d_model_core/lib/src/project_format.dart`) already uses for a
/// document field naming something this build does not recognise, since the
/// schema already constrains a well-behaved caller to a name from the list.
RenderProjectView _viewNamed(Object? value) {
  if (value is! String) return RenderProjectView.iso;
  for (final view in RenderProjectView.values) {
    if (view.name == value) return view;
  }
  return RenderProjectView.iso;
}

/// Every mode an agent can ask for — `mcp-08n`'s own four, plus
/// `selection`, which the row does not count because it is not a shading
/// mode. `wireframe` landed 2026-09-17 as geometry rather than as a line
/// topology; `RenderShading.wireframe` and `wire_overlay.dart` both say why.
///
/// Plain strings rather than a type of their own — this never leaves the
/// tool boundary as a value another package's code holds onto, only ever a
/// JSON argument in and a `RenderRequest` out, so there is no `switch`
/// anywhere for a sixth member to break.
const List<String> renderModes = <String>[
  'material',
  'normals',
  'selection',
  'weights',
  'wireframe',
];

/// [value] turned into what `RenderRequest` actually wants: a [RenderShading]
/// and a highlight set. `'selection'` reads [ModelSession.history]'s own
/// current selection rather than asking a caller to repeat object ids it
/// already gave `select` — the same reason `render`'s own `mode` argument
/// needs no `selection` argument beside it. `'weights'` reads [joint]
/// instead — a joint's own object id has no session-held equivalent to fall
/// back on the way a selection does.
({RenderShading shading, Set<int> selection}) _modeOf(
  Object? value,
  ModelSession session,
) => switch (value) {
  'normals' => (shading: RenderShading.normals, selection: const <int>{}),
  'selection' => (
    shading: RenderShading.material,
    selection: session.history.selection.objects.toSet(),
  ),
  'weights' => (shading: RenderShading.weights, selection: const <int>{}),
  'wireframe' => (shading: RenderShading.wireframe, selection: const <int>{}),
  _ => (shading: RenderShading.material, selection: const <int>{}),
};

/// [value] as an object id for [RenderRequest.weightsJoint], or null — an
/// argument only `'weights'` mode reads, the same tolerant-to-nonsense
/// reading `_viewNamed` already gives a malformed `view`: a caller that
/// sent something other than a whole number gets no weight painted rather
/// than a refusal, and `_isWeightsTarget` already treats a joint that
/// names no real skeleton as "nothing to paint."
int? _jointNamed(Object? value) => value is int ? value : null;

Schema _modeSchema(String about) =>
    UntitledSingleSelectEnumSchema(description: about, values: renderModes);

/// A picture of the project as it stands.
final ModelPictureTool renderTool = ModelPictureTool(
  Tool(
    name: 'render',
    description:
        'A picture of the project as it stands, from one of seven views — '
        'front, back, left, right, top, bottom, or the three-quarter iso '
        'view (the default). Framed to fit whatever is in the project. An '
        'empty project refuses rather than handing back a blank picture.',
    inputSchema: ObjectSchema(
      properties: <String, Schema>{
        'view': UntitledSingleSelectEnumSchema(
          description: 'Which way to look at the project. Defaults to iso.',
          values: <String>[for (final v in RenderProjectView.values) v.name],
        ),
        'mode': _modeSchema(
          'How the surface is shaded. material (default): the project\'s own '
          'materials. normals: each face coloured by its own direction — an '
          'inside-out shell or an unwelded seam reads as a colour seam. '
          'selection: material, with whatever `select` last picked tinted '
          'towards orange. weights: the weight-paint gradient for `joint`, '
          'unlit — everything not bound to that joint\'s own skeleton draws '
          'as material instead of going blank. wireframe: the document\'s '
          'own polygon edges as dark wires over a flat pale surface — the '
          'edges the model has, not the triangles it is drawn with, so an '
          'n-gon shows as an n-sided cell rather than as a fan of '
          'triangles; an imported mesh with no editable topology behind it '
          'gets the flat surface and no wires.',
        ),
        'joint': IntegerSchema(
          description:
              'Which joint `weights` mode paints the gradient for, by its '
              'own object id — the id `setRig`/`paintWeights` already name a '
              'joint with. Ignored by every other mode.',
        ),
        // `ux-44`: a picture costs tokens, and 512×512 is more of them than
        // "is the cube still a cube" needs. A caller that is checking a shape
        // asks for 256; one that is showing somebody the result asks for
        // more. Capped because a picture nobody can hold is not a kindness
        // either — and because this draws on a CPU rasteriser, where the cost
        // is linear in pixels and paid on this thread.
        'size': IntegerSchema(
          description:
              'How big the picture is, in pixels, square. 512 by default; '
              '128 to 1024, which is what renderProject itself draws '
              'between. Smaller is cheaper to look at.',
        ),
      },
    ),
  ),
  (ModelSession session, Map<String, Object?> arguments) async {
    final project = session.history.project;
    if (project.objects.isEmpty) {
      return (
        did: false,
        says: 'Nothing to render: the project has no objects yet.',
        png: null,
      );
    }
    final view = _viewNamed(arguments['view']);
    final mode = _modeOf(arguments['mode'], session);
    final int size = switch (arguments['size']) {
      // `renderProject`'s own ceiling, not a second one invented here:
      // asking past it refuses, and a caller that typed a big number
      // wanted a big picture rather than an error.
      final int asked => asked.clamp(128, 1024),
      _ => 512,
    };
    final png = await renderProject(
      RenderRequest(
        project: project,
        view: view,
        width: size,
        height: size,
        shading: mode.shading,
        selection: mode.selection,
        weightsJoint: _jointNamed(arguments['joint']),
      ),
      deviceFactory: _cpuDevice,
    );
    return (
      did: true,
      says: 'Rendered from the ${view.name} view, $size×$size.',
      png: png,
    );
  },
);

/// A contact sheet of `renderSheetViews` — `mcp-07n`'s own tool. Labelled:
/// each quadrant carries the name of the view it is, drawn with
/// `tiny_font.dart` rather than a widget, since this runs in a plain Dart
/// process with no canvas in it.
final ModelPictureTool renderSheetTool = ModelPictureTool(
  Tool(
    name: 'renderSheet',
    description:
        'A 2×2 contact sheet: front, right, top and iso, one picture, each '
        'quadrant labelled with the view it is — the whole silhouette an '
        'agent more often needs than any single view. An empty project '
        'refuses rather than handing back a blank sheet.',
    inputSchema: ObjectSchema(
      properties: <String, Schema>{
        'mode': _modeSchema(
          'How the surface is shaded on every quadrant — see `render`\'s '
          'own `mode` argument for what each one means.',
        ),
        'joint': IntegerSchema(
          description:
              'Which joint `weights` mode paints — see `render`\'s own '
              '`joint` argument.',
        ),
      },
    ),
  ),
  (ModelSession session, Map<String, Object?> arguments) async {
    final project = session.history.project;
    if (project.objects.isEmpty) {
      return (
        did: false,
        says: 'Nothing to render: the project has no objects yet.',
        png: null,
      );
    }
    final mode = _modeOf(arguments['mode'], session);
    final png = await renderSheet(
      project: project,
      shading: mode.shading,
      selection: mode.selection,
      weightsJoint: _jointNamed(arguments['joint']),
      deviceFactory: _cpuDevice,
    );
    return (
      did: true,
      says: 'Rendered a 2×2 sheet: front, right, top, iso.',
      png: png,
    );
  },
);

/// `audit`: [AssetAudit] in words and the asset from all seven views in one
/// picture, with `repair` to put right what has one right answer.
///
/// **A picture tool because the findings are about what the asset looks
/// like placed.** "The origin is 1.02 m from the base" is a number; the sheet
/// is the same fact as a crate floating beside the grid, and the underside
/// the other four-view sheet never shows is where a generated asset hides
/// its holes. With `repair` the words carry the audit before, what was done
/// and the audit after, and the picture is the repaired asset.
final ModelPictureTool auditTool = ModelPictureTool(
  Tool(
    name: 'audit',
    description:
        'Check an asset that came from somewhere else before it goes into a '
        'game: its overall size (outside 1 cm…100 m is a unit mistake), its '
        'origin against the middle of its base, duplicate materials, what '
        'rebuilding each imported mesh would have to drop or split, and '
        'every `check` issue including the triangle and texture budgets — '
        'with a 4×2 sheet of all seven views. repair: true rebuilds imported '
        'meshes, moves the base onto the origin, bakes transforms, sets '
        'origins and runs makeGameReady for profile, as one undo step; units '
        'and duplicate materials are only reported.',
    inputSchema: ObjectSchema(
      properties: <String, Schema>{
        'repair': BooleanSchema(
          description: 'put right what has one right answer; default false',
        ),
        'profile': UntitledSingleSelectEnumSchema(
          values: <String>['desktop', 'mobile', 'web'],
          description:
              'the texture budget repair fits images to, as makeGameReady '
              'does; default "desktop"',
        ),
      },
    ),
  ),
  (ModelSession session, Map<String, Object?> arguments) async {
    if (session.history.project.objects.isEmpty) {
      return (
        did: false,
        says: 'Nothing to audit: the project has no objects yet.',
        png: null,
      );
    }
    final String before = session.audit();
    final Answer? repaired = arguments['repair'] == true
        ? session.repairAsset(switch (arguments['profile']) {
            final String profile => profile,
            _ => 'desktop',
          })
        : null;
    final png = await renderSheet(
      project: session.history.project,
      width: 1024,
      height: 512,
      views: RenderProjectView.values,
      deviceFactory: _cpuDevice,
    );
    return (
      did: repaired?.did ?? true,
      says: repaired == null
          ? before
          : 'before:\n$before\n\nrepair: ${repaired.says}\n\n'
                'after:\n${session.audit()}',
      png: png,
    );
  },
);

/// `pro-rn-04`: a snapshot at a size and a supersample a person chooses,
/// through `pro-rn-02`'s own tiled job.
///
/// **Not `render` with more arguments.** `render` answers "what does this
/// look like" and is framed for you, capped small and cheap enough to ask
/// every few seconds; this answers "give me the picture", at the size and
/// the quality somebody is going to keep, rendered tile by tile so a frame
/// larger than one device can hold is still one image at the end. Folding
/// the two would make the cheap one carry the expensive one's arguments and
/// the expensive one inherit the cheap one's cap.
final ModelPictureTool renderSnapshotTool = ModelPictureTool(
  Tool(
    name: 'renderSnapshot',
    description:
        'A full-quality picture of the project at a size you choose, '
        'rendered one tile at a time and stitched — `pro-rn-04`. Framed on '
        'the project the same way `render` frames it, with the camera taken '
        'from one of the seven named views. ssaa 2 renders at twice the '
        'side and resolves back down, which is four times the work and the '
        'difference between a picture to look at and one to keep. An empty '
        'project refuses rather than handing back a blank frame.',
    inputSchema: ObjectSchema(
      properties: <String, Schema>{
        'view': UntitledSingleSelectEnumSchema(
          description: 'Which way to look at the project. Defaults to iso.',
          values: <String>[for (final v in RenderProjectView.values) v.name],
        ),
        'width': IntegerSchema(
          description: 'The picture\'s width in pixels, 64 to 4096',
        ),
        'height': IntegerSchema(
          description: 'The picture\'s height in pixels, 64 to 4096',
        ),
        'ssaa': IntegerSchema(
          description:
              'Supersampling: 1 for none (the default), 2 for a 2×2 '
              'supersample resolved back down',
        ),
        'tiles': IntegerSchema(
          description:
              'How many tiles a side the frame is rendered in; default 1. '
              'The width and the height must each divide by it.',
        ),
      },
    ),
  ),
  (ModelSession session, Map<String, Object?> arguments) async {
    final project = session.history.project;
    if (project.objects.isEmpty) {
      return (
        did: false,
        says: 'Nothing to render: the project has no objects yet.',
        png: null,
      );
    }
    final int width = switch (arguments['width']) {
      final int asked => asked.clamp(64, 4096),
      _ => 960,
    };
    final int height = switch (arguments['height']) {
      final int asked => asked.clamp(64, 4096),
      _ => 540,
    };
    final int ssaa = switch (arguments['ssaa']) {
      final int asked => asked.clamp(1, 2),
      _ => 1,
    };
    final int tiles = switch (arguments['tiles']) {
      final int asked => asked.clamp(1, 8),
      _ => 1,
    };
    if (width % tiles != 0 || height % tiles != 0) {
      return (
        did: false,
        says:
            'A frame of $width×$height does not divide into $tiles tiles a '
            'side; pick a tile count both sides divide by.',
        png: null,
      );
    }

    final view = _viewNamed(arguments['view']);
    final SnapshotCamera framed = _framedOn(project, view);
    final png = await RenderSnapshotJob(
      project,
      RenderPreset(
        width: width,
        height: height,
        camera: framed,
        ssaa: ssaa,
        tilesX: tiles,
        tilesY: tiles,
      ),
      tileDevice: _cpuDevice,
      // **The agent is waiting on this one**, which is what makes the cores
      // worth spending: `render` is a tool call, and a tool call that takes
      // three seconds instead of one is three seconds of somebody's session.
      // Measured on an 11-core machine, 1024x1024 in a 4x4 grid: 3283 ms on
      // one worker against 993 on eight.
      //
      // `Platform.numberOfProcessors` is reachable here and not inside
      // `flutter3d_model_core`, which is a flat Dart package that a `dart:io`
      // import would take off the web with it. This is a server; it has io.
      concurrency: Platform.numberOfProcessors,
    ).run();
    return (
      did: true,
      says:
          'Rendered a snapshot from the ${view.name} view, $width×$height'
          '${ssaa > 1 ? ', $ssaa× supersampled' : ''}'
          '${tiles > 1 ? ', in ${tiles * tiles} tiles' : ''}.',
      png: png,
    );
  },
);

/// Where a camera has to stand to see all of [project] from [view].
///
/// **The same arithmetic `renderProject` frames with, written out here**
/// rather than exported from it: that one places a live `CameraNode` inside
/// a scene it has already built on a device, and a snapshot has no scene yet
/// — it builds one per tile. What is shared is the rule, not the code, and
/// the rule is short enough to say twice: the world box of everything in the
/// project, a distance that fits its radius inside the field of view with a
/// margin, and the view's own yaw and pitch away from the middle of it.
SnapshotCamera _framedOn(ModelProject project, RenderProjectView view) {
  Aabb3? box;
  for (final ModelObject object in project.objects) {
    final Aabb3? local = _boundsOf(object.geometry);
    if (local == null) continue;
    final Aabb3 world = Aabb3.copy(local)
      ..transform(worldTransformOf(project, object.id));
    box = box == null ? world : (box..hull(world));
  }
  final Vector3 centre = box?.center ?? Vector3.zero();
  final double radius = box == null
      ? 1.0
      : math.max(box.min.distanceTo(box.max) / 2, 1e-5);
  const double fovY = math.pi / 4;
  final double distance = radius / math.sin(fovY / 2) * 1.2;
  final double cosPitch = math.cos(view.pitch);
  final Vector3 offset = Vector3(
    math.sin(view.yaw) * cosPitch,
    math.sin(view.pitch),
    math.cos(view.yaw) * cosPitch,
  )..scale(distance);
  return SnapshotCamera(
    position: centre + offset,
    target: centre,
    projection: PerspectiveProjection(
      fovYRadians: fovY,
      near: math.max(distance * 0.01, 1e-6),
      far: distance * 10.0 + 10.0,
    ),
  );
}

/// [geometry]'s own local bounding box, or null where it has none.
Aabb3? _boundsOf(Geometry geometry) {
  final Vector3 min = Vector3.all(double.infinity);
  final Vector3 max = Vector3.all(double.negativeInfinity);
  var any = false;
  void grow(Vector3 at) {
    any = true;
    Vector3.min(min, at, min);
    Vector3.max(max, at, max);
  }

  switch (geometry) {
    case EditedGeometry(:final mesh):
      final Vector3 at = Vector3.zero();
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (!mesh.isVertexAlive(v)) continue;
        grow(mesh.positionOf(v, at));
      }
    case ParametricGeometry(:final shape):
      final built = shape.drawn.build();
      final Vector3 at = Vector3.zero();
      for (var v = 0; v < built.vertexCount; v++) {
        grow(built.positionAt(v, at));
      }
    case ImportedGeometry(:final data):
      final Vector3 at = Vector3.zero();
      for (var v = 0; v < data.vertexCount; v++) {
        grow(data.positionAt(v, at));
      }
    case SocketGeometry():
      break;
  }
  return any ? Aabb3.minMax(min, max) : null;
}
