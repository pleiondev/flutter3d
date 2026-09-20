/// Loading the one lesson this app ships.
///
///     flutter test test/lesson_cubit_test.dart
///
/// Driven with `CpuDevice` rather than a window, the same door
/// `flutter3d_template_app/test/level_cubit_test.dart` uses — `LevelLoader`
/// needs a device and does not need one.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_lesson_viewer/main.dart';
import 'package:flutter_test/flutter_test.dart';

GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 9,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening the shipped tour resolves its four steps in order', () async {
    final cubit = LessonCubit();
    expect(cubit.state, isA<LessonLoading>());

    await cubit.open(_device(), camera: CameraNode());

    final state = cubit.state;
    expect(state, isA<LessonReady>());
    final player = (state as LessonReady).player!;
    expect(player.steps.map((EntityDef e) => e.name), <String>[
      'view-front',
      'view-side',
      'view-top',
      'quiz-steps',
    ]);
    expect(player.current?.string('caption'), 'Вид спереди');
  });

  test(
    'edu-07: the teardown demo opens and its prop is reachable by name',
    () async {
      final cubit = LessonCubit();

      await cubit.open(
        _device(),
        camera: CameraNode(),
        asset: 'assets/levels/teardown-demo.json',
      );

      final state = cubit.state;
      expect(state, isA<LessonReady>());
      final ready = state as LessonReady;
      expect(ready.player!.steps.map((EntityDef e) => e.name), <String>[
        'step-1',
        'step-2',
      ]);
      final props = ready.props;
      expect(props, isNotNull);
      expect(props!.nodes.keys, contains('engine-body#valve_cover'));
      expect(props.nodes.keys, contains('engine-body'));
    },
  );

  test('edu-05b: a sampler edu_data_source resolves through this app\'s own '
      'registry and writes a real material field on the bound step', () async {
    final cubit = LessonCubit();

    await cubit.open(
      _device(),
      camera: CameraNode(),
      asset: 'assets/levels/teardown-demo.json',
    );

    final ready = cubit.state as LessonReady;
    final dataSources = ready.dataSources;
    expect(dataSources, isNotNull);

    final step = ready.player!.current!;
    expect(step.name, 'step-1', reason: 'the step carrying the binding');

    final before =
        (ready.nodes['engine-body']! as MeshNode).material.emissiveStrength;
    applyLessonStepBindings(step, 10, dataSources!, nodes: ready.nodes);
    applyLessonStepBindings(step, 20, dataSources, nodes: ready.nodes);
    final after =
        (ready.nodes['engine-body']! as MeshNode).material.emissiveStrength;

    expect(
      after,
      isNot(before),
      reason: 'a live sampler keeps moving, not a constant',
    );
  });

  test(
    'edu-05b: an unsupported edu_data_source kind is reported, and its own '
    'source is left out of the registry rather than given a made-up value',
    () async {
      final cubit = LessonCubit();
      final issues = <String>[];

      await cubit.open(
        _device(),
        camera: CameraNode(),
        asset: 'assets/levels/unsupported-source-demo.json',
        onIssue: (issue) => issues.add(issue.message),
      );

      final ready = cubit.state as LessonReady;
      expect(issues, hasLength(1));
      expect(issues.single, contains('line-rpm'));
      expect(issues.single, contains('mqtt'));
      expect(ready.dataSources!['line-rpm'], isNull);
    },
  );

  test(
    'a lesson that is not there fails loudly rather than silently',
    () async {
      final cubit = LessonCubit();

      await cubit.open(
        _device(),
        camera: CameraNode(),
        asset: 'assets/levels/no_such_lesson.json',
      );

      expect(cubit.state, isA<LessonFailed>());
    },
  );

  test('`ls-x-00`/`ls-x-01`/`ls-x-03`: asStereo builds a StereoRig instead of '
      'a camera, and the same steps through it', () async {
    final cubit = LessonCubit();

    await cubit.open(_device(), asStereo: true);

    final ready = cubit.state as LessonReady;
    expect(ready.camera, isNull);
    expect(ready.player, isNull);
    expect(ready.rig, isNotNull);
    expect(ready.stereoPlayer!.steps.map((EntityDef e) => e.name), <String>[
      'view-front',
      'view-side',
      'view-top',
      'quiz-steps',
    ]);
  });
}
