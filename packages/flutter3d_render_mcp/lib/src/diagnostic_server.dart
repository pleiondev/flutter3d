import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';

import 'diagnostic_session.dart';
import 'diagnostic_tools.dart';

/// The version this server tells a client it is. Kept beside the pubspec's.
const String renderMcpVersion = '0.1.0';

/// A rendered frame, offered to an agent as a table of tools — `par-02`.
///
/// One level, one process, no window — the same shape
/// `flutter3d_sim_mcp`/`flutter3d_editor_mcp` already settled on.
base class DiagnosticMcpServer extends MCPServer with ToolsSupport {
  DiagnosticMcpServer(super.channel, {required this.session})
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'flutter3d_render_mcp',
          version: renderMcpVersion,
        ),
        instructions: _instructions,
      );

  final DiagnosticSession session;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    for (final offered in diagnosticTools) {
      registerTool(
        offered.tool,
        (CallToolRequest request) => _call(offered, request),
      );
    }
    return super.initialize(request);
  }

  Future<CallToolResult> _call(
    DiagnosticTool offered,
    CallToolRequest request,
  ) async {
    final answer = await offered.run(
      session,
      request.arguments ?? const <String, Object?>{},
    );
    final png = answer.png;
    return CallToolResult(
      content: <Content>[
        Content.text(text: answer.says),
        if (png != null)
          Content.image(data: base64Encode(png), mimeType: 'image/png'),
      ],
      isError: answer.did ? null : true,
    );
  }
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
