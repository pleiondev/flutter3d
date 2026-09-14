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
    final png = await renderProject(
      RenderRequest(project: project, view: view),
      deviceFactory: _cpuDevice,
    );
    return (did: true, says: 'Rendered from the ${view.name} view.', png: png);
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
    inputSchema: ObjectSchema(),
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
    final png = await renderSheet(project: project, deviceFactory: _cpuDevice);
    return (
      did: true,
      says: 'Rendered a 2×2 sheet: front, right, top, iso.',
      png: png,
    );
  },
);
