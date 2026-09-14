/// `TutorialScenario`/`TutorialStep` parsing and the screenshot-filename
/// convention — the pure pieces `shoot.dart`'s own doc comment says this
/// stage can be verified by with no running modeler at all.
///
///     dart test tool/tutorial/test/scenario_test.dart
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tutorial/tutorial.dart';

void main() {
  test('the placeholder smoke-test fixture itself parses', () {
    // Relative to this package's own root, the way `window_id_test.dart`'s
    // own comment explains `dart test` is run in this repository.
    final scenario = TutorialScenario.parse(
      File('test/fixtures/smoke_scenario.json').readAsStringSync(),
    );
    expect(scenario.name, 'placeholder-smoke-test');
    expect(scenario.steps, isNotEmpty);
    expect(
      scenario.steps
          .where((s) => s.screenshot != null)
          .map((s) => s.screenshot),
      <String>['01-front.png', '02-iso.png'],
    );
  });

  group('TutorialStep.fromJson', () {
    test('reads tool, args and screenshot', () {
      final step = TutorialStep.fromJson(<String, Object?>{
        'tool': 'ui.setMode',
        'args': <String, Object?>{'mode': 'object'},
        'screenshot': '01-object-mode.png',
      });
      expect(step.tool, 'ui.setMode');
      expect(step.args, <String, Object?>{'mode': 'object'});
      expect(step.screenshot, '01-object-mode.png');
    });

    test('args defaults to empty and screenshot to null when absent', () {
      final step = TutorialStep.fromJson(<String, Object?>{'tool': 'ui.say'});
      expect(step.args, isEmpty);
      expect(step.screenshot, isNull);
    });

    test('refuses a step with no tool name', () {
      expect(
        () => TutorialStep.fromJson(<String, Object?>{
          'args': <String, Object?>{},
        }),
        throwsFormatException,
      );
    });

    test('refuses an empty tool name', () {
      expect(
        () => TutorialStep.fromJson(<String, Object?>{'tool': ''}),
        throwsFormatException,
      );
    });

    test('refuses "args" that is not an object', () {
      expect(
        () => TutorialStep.fromJson(<String, Object?>{
          'tool': 'ui.say',
          'args': 'nope',
        }),
        throwsFormatException,
      );
    });

    test('round-trips through toJson', () {
      const step = TutorialStep(
        tool: 'ui.standardView',
        args: <String, Object?>{'view': 'front'},
        screenshot: '02-front.png',
      );
      expect(TutorialStep.fromJson(step.toJson()).toJson(), step.toJson());
    });

    test('toJson omits empty args and a null screenshot', () {
      const step = TutorialStep(
        tool: 'ui.frameSubject',
        args: <String, Object?>{},
      );
      expect(step.toJson(), <String, Object?>{'tool': 'ui.frameSubject'});
    });
  });

  group('TutorialScenario.parse', () {
    test('parses a scenario with several steps, in order', () {
      final scenario = TutorialScenario.parse('''
      {
        "name": "smoke-test",
        "steps": [
          {"tool": "ui.setMode", "args": {"mode": "object"}},
          {"tool": "ui.standardView", "args": {"view": "front"}, "screenshot": "01-front.png"}
        ]
      }
      ''');
      expect(scenario.name, 'smoke-test');
      expect(scenario.steps, hasLength(2));
      expect(scenario.steps[0].tool, 'ui.setMode');
      expect(scenario.steps[1].screenshot, '01-front.png');
    });

    test('an empty "steps" list is a scenario with nothing to play', () {
      final scenario = TutorialScenario.parse('{"name": "empty", "steps": []}');
      expect(scenario.steps, isEmpty);
    });

    test('refuses a scenario with no name', () {
      expect(
        () => TutorialScenario.parse('{"steps": []}'),
        throwsFormatException,
      );
    });

    test('refuses a scenario with no steps list', () {
      expect(
        () => TutorialScenario.parse('{"name": "x"}'),
        throwsFormatException,
      );
    });

    test('refuses text that is not JSON', () {
      expect(() => TutorialScenario.parse('not json'), throwsFormatException);
    });
  });

  group('TutorialScenario.screenshotPath', () {
    test('joins outDir, the scenario name and the screenshot filename', () {
      const scenario = TutorialScenario(name: 'a-prop-from-a-scan', steps: []);
      expect(
        scenario.screenshotPath(
          'cloud/server/web/assets/learn/modeler',
          '20-import.png',
        ),
        'cloud/server/web/assets/learn/modeler/a-prop-from-a-scan/20-import.png',
      );
    });
  });
}
