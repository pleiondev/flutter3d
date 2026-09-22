/// `runScenario`'s own step sequencing, against fake [ToolCaller]/
/// [FrameWaiter]/[Capturer] rather than a real MCP socket or a real
/// `screencapture` — the "step sequencing" piece `shoot.dart`'s own doc
/// comment says was verified headlessly.
///
///     dart test tool/tutorial/test/shoot_runner_test.dart
library;

import 'package:test/test.dart';
import 'package:tutorial/tutorial.dart';

void main() {
  test('calls each step\'s tool, in order, with its own args', () async {
    final toolNames = <String>[];
    final toolArgs = <Map<String, Object?>>[];
    const scenario = TutorialScenario(
      name: 'case',
      steps: <TutorialStep>[
        TutorialStep(
          tool: 'ui.setMode',
          args: <String, Object?>{'mode': 'object'},
        ),
        TutorialStep(
          tool: 'ui.standardView',
          args: <String, Object?>{'view': 'front'},
        ),
      ],
    );

    await runScenario(
      scenario,
      callTool: (tool, args) async {
        toolNames.add(tool);
        toolArgs.add(args);
      },
      waitFrame: () async {},
      capture: (_) async => fail('no step in this scenario names a screenshot'),
      outDir: 'out',
    );

    expect(toolNames, <String>['ui.setMode', 'ui.standardView']);
    expect(toolArgs, <Map<String, Object?>>[
      <String, Object?>{'mode': 'object'},
      <String, Object?>{'view': 'front'},
    ]);
  });

  test('waits a frame after every step, including the last', () async {
    var waits = 0;
    const scenario = TutorialScenario(
      name: 'case',
      steps: <TutorialStep>[
        TutorialStep(tool: 'ui.say', args: <String, Object?>{'text': 'a'}),
        TutorialStep(tool: 'ui.say', args: <String, Object?>{'text': 'b'}),
        TutorialStep(tool: 'ui.say', args: <String, Object?>{'text': 'c'}),
      ],
    );

    await runScenario(
      scenario,
      callTool: (_, _) async {},
      waitFrame: () async => waits++,
      capture: (_) async {},
      outDir: 'out',
    );

    expect(waits, 3);
  });

  test('captures only the steps that name a screenshot', () async {
    final captured = <String>[];
    const scenario = TutorialScenario(
      name: 'case',
      steps: <TutorialStep>[
        TutorialStep(
          tool: 'ui.setMode',
          args: <String, Object?>{'mode': 'object'},
        ),
        TutorialStep(
          tool: 'ui.standardView',
          args: <String, Object?>{'view': 'front'},
          screenshot: '01-front.png',
        ),
        TutorialStep(tool: 'ui.setTool', args: <String, Object?>{}),
        TutorialStep(
          tool: 'ui.openDialog',
          args: <String, Object?>{'dialog': 'export'},
          screenshot: '02-export.png',
        ),
      ],
    );

    final executed = await runScenario(
      scenario,
      callTool: (_, _) async {},
      waitFrame: () async {},
      capture: (path) async => captured.add(path),
      outDir: 'cloud/server/web/assets/learn/modeler',
    );

    expect(captured, <String>[
      'cloud/server/web/assets/learn/modeler/case/01-front.png',
      'cloud/server/web/assets/learn/modeler/case/02-export.png',
    ]);
    expect(executed.map((step) => step.screenshotPath).toList(), <String?>[
      null,
      'cloud/server/web/assets/learn/modeler/case/01-front.png',
      null,
      'cloud/server/web/assets/learn/modeler/case/02-export.png',
    ]);
  });

  test('an empty scenario calls nothing and captures nothing', () async {
    const scenario = TutorialScenario(name: 'empty', steps: <TutorialStep>[]);
    var toolCalls = 0;
    var captures = 0;

    final executed = await runScenario(
      scenario,
      callTool: (_, _) async => toolCalls++,
      waitFrame: () async {},
      capture: (_) async => captures++,
      outDir: 'out',
    );

    expect(executed, isEmpty);
    expect(toolCalls, 0);
    expect(captures, 0);
  });

  test(
    'a tool call that throws stops the scenario before later steps run',
    () async {
      final calls = <String>[];
      const scenario = TutorialScenario(
        name: 'case',
        steps: <TutorialStep>[
          TutorialStep(
            tool: 'ui.setMode',
            args: <String, Object?>{'mode': 'bogus'},
          ),
          TutorialStep(
            tool: 'ui.say',
            args: <String, Object?>{'text': 'never'},
          ),
        ],
      );

      await expectLater(
        runScenario(
          scenario,
          callTool: (tool, args) async {
            calls.add(tool);
            throw StateError('tool "$tool" refused the call');
          },
          waitFrame: () async {},
          capture: (_) async {},
          outDir: 'out',
        ),
        throwsStateError,
      );

      expect(calls, <String>['ui.setMode']);
    },
  );
}
