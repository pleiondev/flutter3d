import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_lesson_viewer/src/check_prompt.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

EntityDef _stepWithCheck(Map<String, Object?>? check) => EntityDef(
  type: 'edu_step',
  name: 'step-1',
  properties: <String, Object?>{'check': ?check},
);

void main() {
  group('CheckSpec.fromStep', () {
    test('reads question, answers and attempts from a real check object', () {
      final spec = CheckSpec.fromStep(
        _stepWithCheck(<String, Object?>{
          'question': 'Какой момент затяжки?',
          'answers': <String>['80 Нм', '80 нм', '80'],
          'attempts': 3,
        }),
      );
      expect(spec, isNotNull);
      expect(spec!.question, 'Какой момент затяжки?');
      expect(spec.answers, <String>['80 Нм', '80 нм', '80']);
      expect(spec.attempts, 3);
    });

    test('defaults attempts to 1 when absent or not a positive number', () {
      final spec = CheckSpec.fromStep(
        _stepWithCheck(<String, Object?>{
          'question': 'Q',
          'answers': <String>['a'],
        }),
      );
      expect(spec!.attempts, 1);
    });

    test('a step with no check property answers null', () {
      expect(CheckSpec.fromStep(_stepWithCheck(null)), isNull);
    });

    test(
      'a check missing a question or with no answers is read as absent, not thrown',
      () {
        expect(
          CheckSpec.fromStep(
            _stepWithCheck(<String, Object?>{
              'answers': <String>['a'],
            }),
          ),
          isNull,
        );
        expect(
          CheckSpec.fromStep(
            _stepWithCheck(<String, Object?>{
              'question': 'Q',
              'answers': <String>[],
            }),
          ),
          isNull,
        );
      },
    );
  });

  group('CheckSpec.accepts', () {
    const spec = CheckSpec(
      question: 'Q',
      answers: <String>['80 Нм', '80'],
      attempts: 3,
    );

    test('matches an exact answer', () => expect(spec.accepts('80'), isTrue));

    test(
      'ignores case and surrounding whitespace',
      () => expect(spec.accepts('  80 нм  '), isTrue),
    );

    test(
      'refuses anything not in the list',
      () => expect(spec.accepts('81'), isFalse),
    );
  });

  group('CheckPrompt', () {
    Widget host(CheckSpec spec, {Key? key}) => MaterialApp(
      home: Scaffold(
        body: CheckPrompt(key: key, spec: spec),
      ),
    );

    testWidgets('a correct answer says so and stops taking input', (
      tester,
    ) async {
      const spec = CheckSpec(
        question: 'Q',
        answers: <String>['80'],
        attempts: 3,
      );
      await tester.pumpWidget(host(spec));

      await tester.enterText(find.byType(TextField), '80');
      await tester.tap(find.byTooltip('Submit answer'));
      await tester.pump();

      expect(find.text('Верно.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a wrong answer counts down, and reveals the answer at zero', (
      tester,
    ) async {
      const spec = CheckSpec(
        question: 'Q',
        answers: <String>['80'],
        attempts: 2,
      );
      await tester.pumpWidget(host(spec));

      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.byTooltip('Submit answer'));
      await tester.pump();
      expect(find.textContaining('1'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'still nope');
      await tester.tap(find.byTooltip('Submit answer'));
      await tester.pump();

      expect(find.text('Попытки кончились. Ответ: 80'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a fresh key resets the attempt count', (tester) async {
      const spec = CheckSpec(
        question: 'Q',
        answers: <String>['80'],
        attempts: 1,
      );
      await tester.pumpWidget(host(spec, key: const ValueKey('step-1')));

      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.byTooltip('Submit answer'));
      await tester.pump();
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'one attempt, spent',
      );

      await tester.pumpWidget(host(spec, key: const ValueKey('step-2')));
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: 'a new key is a new step, with its own fresh attempt count',
      );
    });
  });
}
