import 'package:flutter3d_mcp/kit.dart';

import 'diagnostic_session.dart';
import 'diagnostic_tools.dart';

/// The version this server tells a client it is: the pubspec's.
///
/// A constant, because a compiled server has no pubspec to read. It said
/// 0.1.0 while the package moved on, since "kept beside the pubspec's" was a
/// comment and nothing checked it; `server_version_test.dart` does now.
const String renderMcpVersion = '1.0.0-rc.1';

/// The version of this server's tools — names and input schemas — as the
/// `initialize` result announces it beside [renderMcpVersion].
///
/// It moves only when the diagnostics server's half of
/// `api/flutter3d_sim_mcp.mcp` does: a minor for a new tool or optional
/// argument, a major for anything that breaks a caller.
///
/// **1.0.0 with the first stable release** (decided 2026-10-09, task F3 of
/// the architecture review): the minors it counted before were moves within
/// a surface nobody had been promised yet, and a host meeting 1.2.0 at a
/// first release would look for a 1.0 and 1.1 that never shipped.
const String renderMcpSchemaVersion = '1.0.0';

/// What each of the diagnostics server's tools is published as, `area.verb`.
/// The written name stays an alias until 2.0.
const Map<String, ToolName> diagnosticToolNames = <String, ToolName>{
  'frame': ToolName('render.frame', ToolHints.reads),
  'open': ToolName('level.open', ToolHints.writes),
  'passes': ToolName('render.passes', ToolHints.reads),
  'pixel': ToolName('render.pixel', ToolHints.reads),
  'scanNaN': ToolName('render.scanNan', ToolHints.reads),
};

/// A rendered frame, offered to an agent as a table of tools — `par-02`.
///
/// One level, one process, no window — the same shape every server here
/// settled on, and the same [ToolTableServer] underneath it.
base class DiagnosticMcpServer
    extends ToolTableServer<DiagnosticSession, PictureAnswer> {
  DiagnosticMcpServer(
    super.channel, {
    required super.session,
    super.projectTools,
    super.onProjectCall,
  }) : super(
         name: 'flutter3d.diagnostics',
         version: renderMcpVersion,
         schemaVersion: renderMcpSchemaVersion,
         names: diagnosticToolNames,
         instructions: _instructions,
         tools: diagnosticTools,
         toResult: pictureResultOf,
       );
}

const String _instructions = '''
Why is the frame wrong, without guessing. `level.open` a level, `render.frame` it from
wherever the question is — an eye position and a look direction, not a point
to stand at — in one of four views: `lit` for the ordinary picture,
`normals` for the surface buffer, `shadowMap`/`staticShadowMap` for the two
point-shadow atlases.

`render.pixel` reads one pixel of whatever was last drawn, unclamped: a depth or a
NaN that the picture itself would have rounded into an ordinary colour.
`render.passes` says what the frame graph actually ran, in order. `render.scanNan` finds
the first pixel that is not finite, if there is one.

Work in this order: `level.open`, `render.frame`, then `render.pixel`/`render.passes`/`render.scanNan` against
that same frame — draw again after moving the eye or changing the view.
''';
