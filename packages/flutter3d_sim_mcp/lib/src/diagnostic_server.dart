import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';

import 'diagnostic_session.dart';
import 'diagnostic_tools.dart';

/// The version this server tells a client it is: the pubspec's.
///
/// A constant, because a compiled server has no pubspec to read. It said
/// 0.1.0 while the package moved on, since "kept beside the pubspec's" was a
/// comment and nothing checked it; `server_version_test.dart` does now.
const String renderMcpVersion = '0.7.0';

/// A rendered frame, offered to an agent as a table of tools — `par-02`.
///
/// One level, one process, no window — the same shape every server here
/// settled on, and the same [ToolTableServer] underneath it.
base class DiagnosticMcpServer
    extends ToolTableServer<DiagnosticSession, PictureAnswer> {
  DiagnosticMcpServer(super.channel, {required super.session})
    : super(
        name: 'flutter3d_sim_mcp diagnostics',
        version: renderMcpVersion,
        instructions: _instructions,
        tools: diagnosticTools,
        toResult: pictureResultOf,
      );
}

const String _instructions = '''
Why is the frame wrong, without guessing. `open` a level, `frame` it from
wherever the question is — an eye position and a look direction, not a point
to stand at — in one of four views: `lit` for the ordinary picture,
`normals` for the surface buffer, `shadowMap`/`staticShadowMap` for the two
point-shadow atlases.

`pixel` reads one pixel of whatever was last drawn, unclamped: a depth or a
NaN that the picture itself would have rounded into an ordinary colour.
`passes` says what the frame graph actually ran, in order. `scanNaN` finds
the first pixel that is not finite, if there is one.

Work in this order: `open`, `frame`, then `pixel`/`passes`/`scanNaN` against
that same frame — draw again after moving the eye or changing the view.
''';
