/// `ls-e-00`'s own row: a real five-step engine teardown, opened the way
/// `main.dart` actually opens it — not a hand-built fixture like
/// `lesson_view_test.dart`'s own `_steps()`, but the shipped
/// `assets/levels/teardown.json` read through `LessonCubit.open`, the same
/// path `lesson_cubit_test.dart` already proves for the tour. This is what
/// answers the row's own acceptance: five steps in order, each naming a
/// part, and the part a step says to hide is actually gone from the scene
/// once that step applies.
///
///     flutter test test/teardown_test.dart
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_lesson_viewer/main.dart';
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
    asset: 'assets/levels/teardown.json',
  );
  final state = cubit.state;
  expect(state, isA<LessonReady>());
  return state as LessonReady;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the five steps resolve in order, each with its own caption', () async {
    final ready = await _opened();
    expect(ready.player.steps.map((EntityDef e) => e.name), <String>[
      'step-1',
      'step-2',
      'step-3',
      'step-4',
      'step-5',
    ]);
    expect(ready.player.current?.string('caption'), 'Двигатель в сборе');
  });

  test('every part the level places is a real, named node', () async {
    final ready = await _opened();
    expect(
      ready.nodes.keys,
      containsAll(<String>[
        'engine-block',
        'valve-cover',
        'air-filter',
        'spark-plug',
      ]),
    );
    for (final node in ready.nodes.values) {
      expect(node.visible, isTrue, reason: 'nothing has been torn down yet');
    }
  });

  test(
    'stepping to "remove the valve cover" actually hides it, and only it',
    () async {
      final ready = await _opened();
      ready.player.next(); // step-2: "Снимаем крышку клапанов"
      ready.player.applyCurrent(ready.camera, nodes: ready.nodes);

      expect(ready.nodes['valve-cover']!.visible, isFalse);
      expect(ready.nodes['engine-block']!.visible, isTrue);
      expect(ready.nodes['air-filter']!.visible, isTrue);
      expect(ready.nodes['spark-plug']!.visible, isTrue);
    },
  );

  test('by the last step, everything but the block has been removed', () async {
    final ready = await _opened();
    // Each step's own hidden list only names what changes *that* step —
    // `applyLessonStepToCamera`'s own doc comment: a name a step does not
    // mention is left exactly as the previous step left it. So a real
    // viewer applies every step it passes through, not just the last one it
    // lands on.
    for (var i = 0; i < 4; i++) {
      ready.player.next();
      ready.player.applyCurrent(ready.camera, nodes: ready.nodes);
    }

    expect(ready.player.current?.name, 'step-5');
    expect(ready.nodes['engine-block']!.visible, isTrue);
    expect(ready.nodes['valve-cover']!.visible, isFalse);
    expect(ready.nodes['air-filter']!.visible, isFalse);
    expect(ready.nodes['spark-plug']!.visible, isFalse);
  });
}
