/// Case 6 — "An agent beside you": case 1's own STL-to-GLB flow, redone
/// through the real MCP tool surface (`modelTools`, JSON arguments, the same
/// way `tools_test.dart`'s own tests drive a tool) rather than through the
/// raw `ModelCommand` constructors cases 1-5 called directly — and, this
/// time, with a person's own edit landing on the same shared `ModelHistory`
/// in between two of the agent's own tool calls, the way `mcp_bootstrap_io
/// .dart`'s own doc comment describes: `startMcpServer` binds a
/// `ModelSession` "over ... the same document a person already has open," so
/// one `ModelHistory` really does carry both kinds of step, in whatever
/// order they actually happen — not two agent calls back to back with a
/// person nowhere in the picture.
///
/// The starting project is `case1ImportedProject` itself (`case1_scenario
/// .dart`), unchanged — this case re-imports nothing new, on purpose: it is
/// case 1's own STL, brought in the same non-tool way `tut-01`
/// (`doc/modeler-tutorial-gaps.md`) already names — the `import` MCP tool
/// takes only a path, no unit or axis, so an agent calling it today would
/// land the teapot at 1x scale, in metres, not the millimetre scale case 1's
/// own import screen chose. Case 6 does not re-litigate that gap; it starts
/// from the same already-imported, already-welded project case 1's own
/// fixture builds directly, and spends its own steps on the tool surface and
/// the shared-history question instead.
///
///     dart test test/tutorial_scenarios_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';

/// Looks a tool up by name the way `tools_test.dart`'s own tests do —
/// `modelTools.firstWhere`, not an import of the command class behind it,
/// since the whole point of this case is calling the tool surface an MCP
/// client actually has.
ModelTool _toolNamed(String name) =>
    modelTools.firstWhere((ModelTool tool) => tool.name == name);

/// Runs [name] with [arguments] the way an MCP client's own tool call would:
/// through [_toolNamed] and `ModelTool.run`, which reaches the exact same
/// `session.run(command)` cases 1-5 called directly, built this time from a
/// JSON map through `modelCommandFromJson` (`model_tools.dart`'s own
/// `_command`) — the same reader the project file and `CommandJournal` use,
/// rather than a typed Dart constructor call. Throws on refusal, the same
/// "must" shape `case1_scenario.dart` uses.
Future<void> _agentCalls(
  ModelSession session,
  String name,
  Map<String, Object?> arguments,
) async {
  final Answer answer = await _toolNamed(name).run(session, arguments);
  if (!answer.did) {
    throw StateError('$name refused over the tool surface: ${answer.says}');
  }
}

/// A person's own live edit, landing on [session]'s shared [ModelHistory]
/// directly — the exact door `ModelerCubit.run` uses in the real app
/// (`now.history.run(command)`, no author named, which defaults to
/// [StepAuthor.person]) rather than `ModelSession.run`'s tool surface, which
/// always names [StepAuthor.agent]. This is case 6's whole point: an
/// `--mcp-port` session is bound over the very `ModelHistory` a person
/// already has open, so both kinds of step really do land on one shared
/// undo stack. **`tut-15`, closed** (`doc/modeler-tutorial-gaps.md`):
/// `ModelHistory.run` itself now records to whichever recovery journal is
/// attached, so this step reaches this session's own `.jsonl` too, under
/// [StepAuthor.person], exactly like every step [_agentCalls] runs reaches
/// it under [StepAuthor.agent] — the two doors write to the one journal
/// now, not only the tool surface's own.
void _personEdits(ModelSession session, ModelCommand command) {
  final String? refused = session.history.run(command);
  if (refused != null) {
    throw StateError("the person's own edit refused: $refused");
  }
}

/// Every step case 6's own page (`cloud/server/content/learn/modeler/
/// 06-an-agent-beside-you.md`) walks through, run against [session] — case
/// 1's own five steps, but with the roughness edit made directly against the
/// shared document rather than through the tool surface, so the project
/// this reaches carries a real mix of [StepAuthor.agent] and
/// [StepAuthor.person] steps for the undo-restriction test to act on.
Future<void> runCase6Scenario(ModelSession session) async {
  await _agentCalls(session, 'rename', <String, Object?>{
    'id': 1,
    'to': 'teapot',
  });
  await _agentCalls(session, 'addMaterial', <String, Object?>{
    'materialName': 'glazed ceramic',
  });
  await _agentCalls(session, 'setMaterialField', <String, Object?>{
    'index': 0,
    'field': 'baseColor',
    'value': <double>[0.92, 0.89, 0.82, 1.0],
  });
  await _agentCalls(session, 'setMaterialField', <String, Object?>{
    'index': 0,
    'field': 'metallic',
    'value': 0.0,
  });
  // The person, watching the same window, nudges the roughness slider
  // themselves while the agent is still working — on the identical
  // `ModelHistory` the tool calls before and after it act on, but never
  // through `ModelSession.run`/the tool surface.
  _personEdits(
    session,
    const SetMaterialField(index: 0, field: 'roughness', value: 0.35),
  );
  await _agentCalls(session, 'assignMaterial', <String, Object?>{
    'id': 1,
    'to': 0,
  });
}
