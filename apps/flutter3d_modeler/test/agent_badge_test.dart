/// `ux-05`: an open port is not an agent, and an agent is not a panel.
///
///     flutter test test/agent_badge_test.dart
///
/// **What the live run actually saw.** With `--mcp-port` open and nothing
/// connected, the "Agent session" column took the right-hand side of the
/// window and a contact sheet reading "No render/renderSheet call yet this
/// session" took about a third of the viewport's height, from the first frame
/// onward. Both were built from `kMcpPort >= 0` — a socket listening, which
/// says nothing at all about whether anybody is on the other end of it.
library;

import 'package:flutter/material.dart' hide Material, Matrix4;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/ui/agent_session_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/top_bar_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ModelerCubit opened() {
  final it = cpuTestDevice(width: 8, height: 8);
  final history = ModelHistory(
    const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'cube',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
      ),
    ),
  );
  return ModelerCubit()..opened(
    history,
    renderer: Renderer.create(device: it.device),
    stage: ModelerStage.fromProject(
      device: it.device,
      project: history.project,
    ),
  );
}

ModelerReady ready(ModelerCubit cubit) => cubit.state as ModelerReady;

AgentToolCall aCall() => AgentToolCall(
  tool: 'list',
  arguments: const <String, Object?>{},
  did: true,
  says: 'one object',
  elapsed: Duration.zero,
  at: DateTime(2026, 1, 1),
);

Future<void> showBar(
  WidgetTester tester, {
  String? agentClient,
  int calls = 0,
  VoidCallback? onToggle,
}) async {
  tester.view.physicalSize = const Size(1400, 200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: modelerTheme(),
      home: Scaffold(
        body: TopBarActions(
          canUndo: false,
          canRedo: false,
          undoSays: null,
          redoSays: null,
          onUndo: () {},
          onRedo: () {},
          onAddPrimitive: (_) {},
          onOpen: () {},
          onImport: () {},
          onSave: () {},
          onExport: (_) {},
          onMaterialStudio: () {},
          onPlay: (_) {},
          onPreview: () {},
          onShortcutHelp: () {},
          onStartScreen: () {},
          onReportProblem: () {},
          agentClient: agentClient,
          agentCallCount: calls,
          onToggleAgentPanel: onToggle,
        ),
      ),
    ),
  );
}

void main() {
  group('the cubit knows when somebody is actually there', () {
    test('a fresh session has no agent', () {
      // Mutation: read `kMcpPort >= 0` for this, which is what the screen
      // did. Every launch with the port open then claims an agent.
      expect(ready(opened()).agentClient, isNull);
    });

    test('initialize names the client, and says so out loud', () {
      final cubit = opened();

      cubit.agentConnected('claude-code');

      // An agent arriving on a shared undo stack is news: it can edit the
      // same history the person is editing.
      expect(ready(cubit).agentClient, 'claude-code');
      expect(ready(cubit).said, contains('claude-code'));
      expect(ready(cubit).saidIsImportant, isTrue);
    });

    test('and a tool call afterwards does not forget it', () {
      final cubit = opened()..agentConnected('claude-code');

      cubit.agentToolCalled(aCall());

      // Mutation: rebuild the state in `agentToolCalled` without carrying
      // `agentClient` across. The badge would vanish on the agent's first
      // call, which is exactly when it starts mattering.
      expect(ready(cubit).agentClient, 'claude-code');
      expect(ready(cubit).agentCalls, hasLength(1));
    });
  });

  group('the badge', () {
    // The whole bar, in a window wide enough for it — the desktop shell's
    // own width. How the actions behave when there is not room for them all
    // is `ux-21`'s row, and a narrow surface here would be this test asking
    // that question instead of its own.
    setUp(() {});

    testWidgets('nothing at all while nobody has connected', (
      WidgetTester tester,
    ) async {
      await showBar(tester);

      expect(find.byIcon(Icons.smart_toy), findsNothing);
    });

    testWidgets('a badge once one has, counting the calls', (
      WidgetTester tester,
    ) async {
      var toggled = 0;
      await showBar(
        tester,
        agentClient: 'claude-code',
        calls: 3,
        onToggle: () => toggled++,
      );

      expect(find.byIcon(Icons.smart_toy), findsOne);
      expect(find.text('3'), findsOne);

      await tester.tap(find.byIcon(Icons.smart_toy));
      expect(toggled, 1);
    });

    testWidgets('and no count before the first call', (
      WidgetTester tester,
    ) async {
      await showBar(tester, agentClient: 'claude-code');

      // A badge reading "0" is a badge that says nothing. Mutation: show the
      // label unconditionally.
      expect(find.byIcon(Icons.smart_toy), findsOne);
      expect(find.text('0'), findsNothing);
    });
  });

  group('the panel', () {
    testWidgets('holds the contact sheet as a tab rather than a bottom slot', (
      WidgetTester tester,
    ) async {
      final cubit = opened()..agentConnected('claude-code');
      cubit.agentToolCalled(aCall());

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: modelerTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 600,
              child: AgentSessionPanel(
                calls: ready(cubit).agentCalls,
                history: ready(cubit).history,
                onUndoAgentSteps: () {},
                clientName: 'claude-code',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Agent · claude-code'), findsOne);
      expect(find.text('TOOL CALLS'), findsOne);

      await tester.tap(find.text('Renders'));
      await tester.pumpAndSettle();

      // Mutation: leave the sheet in the shell's own `bottom` slot. It then
      // takes a third of the viewport's height whether or not a render has
      // ever been asked for — which it had not been, in the live run.
      expect(find.byType(AgentContactSheet), findsOne);
      expect(find.text('TOOL CALLS'), findsNothing);
    });

    testWidgets('and closes from its own header', (WidgetTester tester) async {
      final cubit = opened()..agentConnected('claude-code');
      var closed = 0;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: modelerTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 600,
              child: AgentSessionPanel(
                calls: const <AgentToolCall>[],
                history: ready(cubit).history,
                onUndoAgentSteps: () {},
                clientName: 'claude-code',
                onClose: () => closed++,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Hide the agent panel'));
      expect(closed, 1);
    });
  });
}
