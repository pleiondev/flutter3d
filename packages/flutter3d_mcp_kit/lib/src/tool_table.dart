/// A server that is a table of tools over one session.
library;

import 'dart:async';

import 'package:dart_mcp/server.dart';

import 'argument_check.dart';

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
    this.refusal,
    this.onCall,
    this.onInitialize,
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

  /// A refusal, as the answer type this server speaks — `ux-43`.
  ///
  /// **Given rather than built here, because only the caller knows what an
  /// [A] is.** A server whose answers carry a picture has a null one to put
  /// in; one whose answers are a bare `(did, says)` has nothing to add. What
  /// this buys is that an argument refused before a tool ever runs travels
  /// back through [toResult] like every other answer — marked as an error,
  /// and carrying whatever machine-readable half that server attaches — so a
  /// misspelt key and a refused edit read the same way to whoever called.
  ///
  /// Null leaves the framework's own validation in place, which says the same
  /// thing as a JSON Schema path expression.
  final A Function(String says)? refusal;

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

  /// `ux-05`'s own hook: a client has said hello, with the name it gave.
  ///
  /// A name rather than the whole `Implementation`, so an application
  /// watching this needs no `dart_mcp` import of its own — the name is all a
  /// badge has room for anyway.
  ///
  /// **Distinct from [onCall], and a screen needs both.** An open port is not
  /// an agent: the live run found the modeller giving a third of its window
  /// to an agent panel and a contact sheet from the first frame, with nobody
  /// connected and nothing to show in either. `initialize` is the first
  /// moment there is somebody there, and it arrives whether or not that
  /// somebody ever calls a tool.
  ///
  /// Run before the answer goes back, and — like [onCall] — never allowed to
  /// fail it: whatever a watching screen does with the news is its own
  /// business and none of the client's.
  final void Function(String clientName)? onInitialize;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    try {
      onInitialize?.call(request.clientInfo.name);
    } catch (_) {}
    for (final OfferedTool<S, A> offered in tools) {
      registerTool(offered.tool, (CallToolRequest call) async {
        final Map<String, Object?> arguments =
            call.arguments ?? const <String, Object?>{};
        // `ux-43`: checked here rather than by `registerTool`'s own
        // `validateArguments`, which is switched off below — see [refusal]
        // for why, and `argument_check.dart` for what it catches that the
        // framework's own pass does not.
        if (refusal case final A Function(String) asRefusal) {
          final String? wrong = refuseArguments(offered.tool, arguments);
          if (wrong != null) return toResult(asRefusal(wrong));
        }
        // Null exactly when [onCall] is: a headless server (nobody
        // watching) never reads the clock at all, not even to throw the
        // answer away — see `repeatableStepExempt`'s own entry for this
        // file, `tool/structure/repository.dart`.
        final Stopwatch? stopwatch = onCall == null
            ? null
            : (Stopwatch()..start());
        final A answer = await offered.run(session, arguments);
        stopwatch?.stop();
        // **A watcher never fails a call.** [onCall] is somebody else's
        // screen, redrawn beside this server; whatever it does with the news
        // is its own business and none of the client's. `ux-02` found out
        // what the alternative costs: a re-sync inside this hook threw for an
        // object a device had refused, so the *answer* — already computed,
        // already correct — came back to the agent as a stack trace instead,
        // and did so again for every call after it.
        try {
          onCall?.call(
            offered.name,
            arguments,
            answer,
            stopwatch?.elapsed ?? Duration.zero,
          );
        } catch (_) {}
        return toResult(answer);
      }, validateArguments: refusal == null);
    }
    return super.initialize(request);
  }
}
