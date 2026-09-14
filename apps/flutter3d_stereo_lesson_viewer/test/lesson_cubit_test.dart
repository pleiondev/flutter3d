/// Loading the one lesson this app ships, and playing it through — the
/// stereo counterpart of `flutter3d_lesson_viewer/test/lesson_cubit_test.dart`
/// and `flutter3d_lesson_viewer/test/teardown_test.dart` both.
///
///     flutter test test/lesson_cubit_test.dart
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_stereo_lesson_viewer/main.dart';
import 'package:flutter_test/flutter_test.dart';

GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 9,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'opening the shipped teardown resolves its five steps in order',
    () async {
      final cubit = LessonCubit();
      expect(cubit.state, isA<LessonLoading>());

      await cubit.open(_device());

      final state = cubit.state;
      expect(state, isA<LessonReady>());
      final ready = state as LessonReady;
      expect(ready.player.steps.map((EntityDef e) => e.name), <String>[
        'step-1',
        'step-2',
        'step-3',
        'step-4',
        'step-5',
      ]);
      expect(ready.player.current?.string('caption'), 'Двигатель в сборе');
    },
  );

  test(
    'a lesson that is not there fails loudly rather than silently',
    () async {
      final cubit = LessonCubit();

      await cubit.open(_device(), asset: 'assets/levels/no_such_lesson.json');

      expect(cubit.state, isA<LessonFailed>());
    },
  );

  test('every part the level places is a real, named node', () async {
    final cubit = LessonCubit();
    await cubit.open(_device());
    final ready = cubit.state as LessonReady;

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

  test('stepping to "remove the valve cover" hides it, and only it', () async {
    final cubit = LessonCubit();
    await cubit.open(_device());
    final ready = cubit.state as LessonReady;

    ready.player.next();
    ready.player.applyCurrent(ready.rig, nodes: ready.nodes);

    expect(ready.nodes['valve-cover']!.visible, isFalse);
    expect(ready.nodes['engine-block']!.visible, isTrue);
    expect(ready.nodes['air-filter']!.visible, isTrue);
    expect(ready.nodes['spark-plug']!.visible, isTrue);
  });

  test("ls-x-01's own prerequisite: the level's widget_surface resolves onto "
      'the stereo scene', () async {
    final cubit = LessonCubit();
    await cubit.open(_device());
    final ready = cubit.state as LessonReady;

    expect(ready.widgetSurfaces.surfaces, hasLength(1));
    final surface = ready.widgetSurfaces.surfaces.single;
    expect(ready.scene.meshes, contains(surface.node));
  });
}
