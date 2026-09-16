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

import 'package:dart_mcp/server.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

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

/// `mcp-08n`'s own four reachable modes, `tut-11`'s own fix landing the
/// fourth: `wireframe` still waits on `view-07`'s own edge-drawing landing
/// in the engine, the same honest gap `RenderShading` itself already names.
///
/// Plain strings rather than a type of their own — this never leaves the
/// tool boundary as a value another package's code holds onto, only ever a
/// JSON argument in and a `RenderRequest` out, so there is no `switch`
/// anywhere for a fifth member to break.
const List<String> renderModes = <String>[
  'material',
  'normals',
  'selection',
  'weights',
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
          'as material instead of going blank.',
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

/// A contact sheet of `renderSheetViews` — `mcp-07n`'s own tool. See
/// `render_sheet.dart`'s own doc comment for the real, named gap: no labels
/// yet, since nothing in this workspace draws text into a raster with no
/// `dart:ui` behind it.
final ModelPictureTool renderSheetTool = ModelPictureTool(
  Tool(
    name: 'renderSheet',
    description:
        'A 2×2 contact sheet: front, right, top and iso, one picture — the '
        'whole silhouette an agent more often needs than any single view. '
        'An empty project refuses rather than handing back a blank sheet.',
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
