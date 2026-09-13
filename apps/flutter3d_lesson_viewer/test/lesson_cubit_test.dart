/// Loading the one lesson this app ships.
///
///     flutter test test/lesson_cubit_test.dart
///
/// Driven with `CpuDevice` rather than a window, the same door
/// `flutter3d_template_app/test/level_cubit_test.dart` uses — `LevelLoader`
/// needs a device and does not need one.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_lesson_viewer/main.dart';
import 'package:flutter_test/flutter_test.dart';

GraphicsDevice _device() =>
    CpuDevice(width: 16, height: 9, shaders: CpuShaderLibrary(builtinCpuShaders()));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening the shipped tour resolves its four steps in order', () async {
    final cubit = LessonCubit();
    expect(cubit.state, isA<LessonLoading>());

    await cubit.open(_device(), camera: CameraNode());

    final state = cubit.state;
    expect(state, isA<LessonReady>());
    final player = (state as LessonReady).player;
    expect(player.steps.map((EntityDef e) => e.name), <String>[
      'view-front',
      'view-side',
      'view-top',
      'quiz-steps',
    ]);
    expect(player.current?.string('caption'), 'Вид спереди');
  });

  test('a lesson that is not there fails loudly rather than silently', () async {
    final cubit = LessonCubit();

    await cubit.open(
      _device(),
      camera: CameraNode(),
      asset: 'assets/levels/no_such_lesson.json',
    );

    expect(cubit.state, isA<LessonFailed>());
  });
}
