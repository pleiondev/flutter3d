/// `ls-e-02`'s own row: a second subject vertical after engineering — cell
/// structure, layers peeled back one at a time, a checked question at every
/// step — opened the way `main.dart` actually opens it, the same shape
/// `teardown_test.dart`/`housing_test.dart` already prove.
///
/// **The row's own acceptance is split.** "A student clears the lesson
/// within three attempts at the question" is checked here, against a real
/// `CheckSpec` parsed from the shipped document. "The result is visible to
/// the instructor through `edu-03`" is not: `edu-03` is LTI/xAPI, explicitly
/// out of scope for the standing goal this row serves ("без Moodle").
///
///     flutter test test/cell_test.dart
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_lesson_viewer/main.dart';
import 'package:flutter3d_lesson_viewer/src/check_prompt.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 9,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

Future<LessonReady> _opened() async {
  final cubit = LessonCubit();
  await cubit.open(
    _device(),
    camera: CameraNode(),
    asset: 'assets/levels/cell.json',
  );
  final state = cubit.state;
  expect(state, isA<LessonReady>());
  return state as LessonReady;
}

void _advance(LessonReady ready, int count) {
  for (var i = 0; i < count; i++) {
    ready.player.next();
    ready.player.applyCurrent(ready.camera, nodes: ready.nodes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the four steps resolve in order, each with its own caption', () async {
    final ready = await _opened();
    expect(ready.player.steps.map((EntityDef e) => e.name), <String>[
      'step-1',
      'step-2',
      'step-3',
      'step-4',
    ]);
    expect(ready.player.current?.string('caption'), 'Клетка в целом');
  });

  test('every layer the level places starts visible', () async {
    final ready = await _opened();
    expect(
      ready.nodes.keys,
      containsAll(<String>[
        'cell-membrane',
        'cytoplasm',
        'mitochondria',
        'nucleus',
      ]),
    );
    for (final node in ready.nodes.values) {
      expect(
        node.isVisible,
        isTrue,
        reason: 'nothing has been peeled back yet',
      );
    }
  });

  test('by step 3, the membrane and cytoplasm are both peeled away', () async {
    final ready = await _opened();
    _advance(ready, 2);

    expect(ready.player.current?.name, 'step-3');
    expect(ready.nodes['cell-membrane']!.isVisible, isFalse);
    expect(ready.nodes['cytoplasm']!.isVisible, isFalse);
    expect(ready.nodes['mitochondria']!.isVisible, isTrue);
    expect(ready.nodes['nucleus']!.isVisible, isTrue);
  });

  test('every step carries a real, gradeable question', () async {
    final ready = await _opened();
    for (final step in ready.player.steps) {
      final spec = CheckSpec.fromStep(step);
      expect(spec, isNotNull, reason: '${step.name} names no check');
      expect(spec!.attempts, 3);
      expect(spec.accepts('nonsense answer'), isFalse);
    }
  });

  test(
    'step 3\'s question accepts a correctly-cased, trimmed answer',
    () async {
      final ready = await _opened();
      _advance(ready, 2);
      final spec = CheckSpec.fromStep(ready.player.current!)!;
      expect(spec.accepts('  Выработка Энергии  '), isTrue);
      // What mitochondria make is ATP; a pupil who says so is right.
      expect(spec.accepts('синтез АТФ'), isTrue);
    },
  );

  test('the cell\'s fluid is cytoplasm, cytosol or hyaloplasm', () async {
    // Mutation: accept "цитоплазма" alone. The liquid the organelles sit in
    // is the cytosol, or hyaloplasm in the Russian school's word; a pupil who
    // knows that should not be marked wrong.
    final ready = await _opened();
    _advance(ready, 1);
    final spec = CheckSpec.fromStep(ready.player.current!)!;
    for (final answer in <String>['цитоплазма', 'цитозоль', 'гиалоплазма']) {
      expect(spec.accepts(answer), isTrue, reason: answer);
    }
  });
}
