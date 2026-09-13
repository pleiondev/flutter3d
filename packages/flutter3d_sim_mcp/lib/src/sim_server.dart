import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';

import 'sim_session.dart';
import 'sim_tools.dart';

/// The version this server tells a client it is. Kept beside the pubspec's.
const String simMcpVersion = '0.1.0';

/// A shooter level, offered to an agent as a table of tools — `ai-00`.
///
/// **One level, one process, no window** — the same shape
/// `flutter3d_editor_mcp` already settled on, for the same reason: two
/// writers on one run is a different, harder program, and this is the half
/// that a `dart_mcp` client can drive over a pair of streams with nothing
/// running for real behind them.
base class SimMcpServer extends MCPServer with ToolsSupport {
  SimMcpServer(super.channel, {required this.session})
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'flutter3d_sim_mcp',
          version: simMcpVersion,
        ),
        instructions: _instructions,
      );

  /// The level being played, for the life of the process.
  final SimSession session;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    for (final offered in simTools) {
      registerTool(
        offered.tool,
        (CallToolRequest request) => _call(offered, request),
      );
    }
    return super.initialize(request);
  }

  /// Runs one tool and turns its answer into a result.
  ///
  /// **A refusal comes back as an error result, not as a thrown
  /// exception**, the same reason `flutter3d_editor_mcp` gives for its own
  /// `_call`: "no level open" is something the model sees and can act on,
  /// not a broken server.
  Future<CallToolResult> _call(SimTool offered, CallToolRequest request) async {
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

/// What the host puts in front of the model before it calls anything.
const String _instructions = '''
A shooter level, played blind — open a level, step it forward with an
intent (move, look, fire), and read back where things stand in words rather
than in pixels. `snapshot` is the tool worth calling most: it says the
player's position, health, and the same for every actor the level spawned.
`frame` draws an actual picture when that is worth the time; most of the
time it is not.

`digest` and `writeRun` are for handing a run to something else: `digest`
is what `net-04`'s divergence check compares, and `writeRun` writes a
`.f3drun` that `apps/flutter3d_editor`'s timeline opens like any other
recorded run.

Work in this order: `open` a level, `step` it forward in the direction you
mean, `snapshot` to see what happened, and repeat. `writeRun` once, at the
end, if the run is worth keeping.
''';
