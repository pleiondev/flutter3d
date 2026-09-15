/// `tut-16`'s own screen 26: the tool-call feed, and the author-badged
/// history beside it.
///
///     flutter test test/agent_session_panel_test.dart
library;

import 'package:flutter/material.dart' hide Matrix4;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/modeler_state.dart';
import 'package:flutter3d_modeler/src/ui/agent_session_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The same one-cube fixture `history_author_test.dart`
/// (`flutter3d_model_core`) already builds `mcp-10n`'s own suite from — a
/// real, runnable [ModelHistory] rather than a hand-built [HistoryStep],
/// since [ModelHistory.run]'s own `author` argument is the actual door
/// `ModelSession.run` and a person's own edit both go through.
ModelHistory freshHistory() {
  var project = const ModelProject();
  project = project.added(
    (int id) => ModelObject(
      id: id,
      name: 'block',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.identity(),
    ),
  );
  final history = ModelHistory(project);
  history.selection = ProjectSelection(
    mode: SelectionMode.object,
    objects: const <int>[1],
  );
  return history;
}

Future<void> _pump(
  WidgetTester tester, {
  required List<AgentToolCall> calls,
  required ModelHistory history,
  VoidCallback? onUndoAgentSteps,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: SizedBox(
        width: 330,
        child: AgentSessionPanel(
          calls: calls,
          history: history,
          onUndoAgentSteps: onUndoAgentSteps ?? () {},
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('an empty session says so on both lists, undo disabled', (
    tester,
  ) async {
    await _pump(
      tester,
      calls: const <AgentToolCall>[],
      history: freshHistory(),
    );

    expect(find.text('No tool calls yet this session'), findsOneWidget);
    expect(find.text('Nothing done yet'), findsOneWidget);
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Undo agent steps'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'the feed shows a tool call the instant one lands, most recent last',
    (tester) async {
      final first = AgentToolCall(
        tool: 'ui.setMode',
        arguments: const <String, Object?>{'mode': 'animation'},
        did: true,
        says: 'mode set to animation',
        elapsed: const Duration(milliseconds: 40),
        at: DateTime(2026, 1, 1),
      );
      await _pump(
        tester,
        calls: const <AgentToolCall>[],
        history: freshHistory(),
      );
      expect(find.textContaining('ui.setMode'), findsNothing);

      // A second real MCP tool call answering — `onToolCall`'s own shape,
      // the same one `mcp_bootstrap_io.dart` wires into
      // `ModelerCubit.agentToolCalled` — landing while the panel is already
      // on screen, the same as a live `BlocBuilder` rebuild would deliver.
      await _pump(
        tester,
        calls: <AgentToolCall>[first],
        history: freshHistory(),
      );

      expect(
        find.textContaining('ui.setMode(mode: animation)'),
        findsOneWidget,
      );
      expect(find.text('mode set to animation'), findsOneWidget);

      final second = AgentToolCall(
        tool: 'render',
        arguments: const <String, Object?>{'view': 'front'},
        did: true,
        says: 'Rendered from the front view.',
        elapsed: const Duration(milliseconds: 620),
        at: DateTime(2026, 1, 1, 0, 0, 1),
      );
      await _pump(
        tester,
        calls: <AgentToolCall>[first, second],
        history: freshHistory(),
      );

      // Mutation: keep only the newest call instead of appending. Both
      // rows have to survive the second arrival, in call order.
      final rows = tester.widgetList<Text>(
        find.textContaining(RegExp(r'^(ui\.setMode|render)\(')),
      );
      expect(rows.map((Text t) => t.data), <String>[
        'ui.setMode(mode: animation)',
        'render(view: front)',
      ]);
    },
  );

  testWidgets(
    'a refused call reads in the error colour, not the ordinary one',
    (tester) async {
      final refused = AgentToolCall(
        tool: 'ui.setMode',
        arguments: const <String, Object?>{'mode': 'nonsense'},
        did: false,
        says: 'no such mode: nonsense',
        elapsed: const Duration(milliseconds: 5),
        at: DateTime(2026, 1, 1),
      );
      await _pump(
        tester,
        calls: <AgentToolCall>[refused],
        history: freshHistory(),
      );

      final theme = modelerTheme();
      final says = tester.widget<Text>(find.text('no such mode: nonsense'));
      // Mutation: colour every result the same regardless of `did`. A
      // refusal sitting in the feed unmarked reads as though it worked.
      expect(says.style?.color, theme.colorScheme.error);
    },
  );

  testWidgets(
    "a person's step and an agent's step show distinct badges, newest first",
    (tester) async {
      final history = freshHistory();
      history.run(MoveBy(Vector3(1, 0, 0)), author: StepAuthor.agent);
      history.run(MoveBy(Vector3(0, 1, 0)));

      await _pump(tester, calls: const <AgentToolCall>[], history: history);

      expect(find.text('Agent'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);

      // Newest first: the person's own step (run second, with no author —
      // `StepAuthor.person` by default) sits above the agent's.
      final badges = tester.widgetList<Text>(
        find.byWidgetPredicate(
          (Widget w) => w is Text && (w.data == 'You' || w.data == 'Agent'),
        ),
      );
      expect(badges.map((Text t) => t.data), <String>['You', 'Agent']);
    },
  );

  testWidgets(
    "undo agent steps is enabled only while the top step is the agent's own",
    (tester) async {
      final agentOnTop = freshHistory()
        ..run(MoveBy(Vector3(1, 0, 0)), author: StepAuthor.agent);
      var undone = 0;
      await _pump(
        tester,
        calls: const <AgentToolCall>[],
        history: agentOnTop,
        onUndoAgentSteps: () => undone++,
      );

      final enabled = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Undo agent steps'),
      );
      expect(enabled.onPressed, isNotNull);
      await tester.tap(find.widgetWithText(TextButton, 'Undo agent steps'));
      expect(undone, 1);

      final personOnTop = freshHistory()
        ..run(MoveBy(Vector3(1, 0, 0)), author: StepAuthor.agent)
        ..run(MoveBy(Vector3(0, 1, 0)));
      await _pump(tester, calls: const <AgentToolCall>[], history: personOnTop);

      // Mutation: leave the button enabled regardless of `topStepAuthor` —
      // `mcp-10n`'s own restriction would be offered a button that ignores
      // it.
      final disabled = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Undo agent steps'),
      );
      expect(disabled.onPressed, isNull);
    },
  );
}
