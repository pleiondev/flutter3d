/// A server that is a table of tools over one session.
library;

import 'dart:async';

import 'package:dart_mcp/server.dart';

/// One tool: what an agent is offered, and what calling it does to the
/// session.
///
/// **A pair rather than a table and a switch.** The obvious arrangement is a
/// list of [Tool] for `tools/list` and a `switch` on the name in `tools/call`,
/// and the two drift the moment somebody adds one and forgets the other — an
/// offered tool that answers "no tool registered with that name", which
/// nothing notices because both halves compile. Here a tool that is offered is
/// a tool that has a body, because they are the same object.
final class OfferedTool<S, A> {
  const OfferedTool(this.tool, this.run);

  /// What `tools/list` hands the agent: a name, a sentence and a schema.
  final Tool tool;

  /// What calling it does to [S]. `FutureOr`, so a tool that decodes a file
  /// and one that renames an object are the same kind of value.
  final FutureOr<A> Function(S session, Map<String, Object?> arguments) run;

  String get name => tool.name;
}

/// A server offering [tools] over one [session], every answer turned into a
/// result by [toResult].
///
/// **One session, one process, and no window** — the shape every server here
/// settled on: two writers on one undo stack, or on one run, is a different
/// and much harder program, and this is the half a suite can drive over a pair
/// of streams with nothing running for real behind them.
base class ToolTableServer<S, A> extends MCPServer with ToolsSupport {
  ToolTableServer(
    super.channel, {
    required this.session,
    required this.tools,
    required this.toResult,
    required String name,
    required String version,
    required String instructions,
    this.onCall,
  }) : super.fromStreamChannel(
         implementation: Implementation(name: name, version: version),
         instructions: instructions,
       );

  /// The state every tool acts on, for the life of the process.
  final S session;

  /// What an agent is offered, in the order `tools/list` gives them.
  final List<OfferedTool<S, A>> tools;

  /// How an answer travels back — see `resultOf` and `pictureResultOf`.
  final CallToolResult Function(A answer) toResult;

  /// `tut-16`'s own hook, run after every call answers, whichever of [tools]
  /// it was — a caller with a screen open beside this server (`mcp-13n`'s
  /// `--mcp-port`) wants to show a live feed of what an agent is doing, and
  /// this is the one seam every call already passes through regardless of
  /// which tool it named. Null for every server that has nobody watching,
  /// which is every server this repository starts headless.
  final void Function(
    String toolName,
    Map<String, Object?> arguments,
    A answer,
    Duration elapsed,
  )?
  onCall;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    for (final OfferedTool<S, A> offered in tools) {
      registerTool(offered.tool, (CallToolRequest call) async {
        final Map<String, Object?> arguments =
            call.arguments ?? const <String, Object?>{};
        // Null exactly when [onCall] is: a headless server (nobody
        // watching) never reads the clock at all, not even to throw the
        // answer away — see `repeatableStepExempt`'s own entry for this
        // file, `tool/structure/repository.dart`.
        final Stopwatch? stopwatch = onCall == null
            ? null
            : (Stopwatch()..start());
        final A answer = await offered.run(session, arguments);
        stopwatch?.stop();
        onCall?.call(
          offered.name,
          arguments,
          answer,
          stopwatch?.elapsed ?? Duration.zero,
        );
        return toResult(answer);
      });
    }
    return super.initialize(request);
  }
}
