/// Loading the one level this seed has.
///
///     flutter test test/level_cubit_test.dart
///
/// Small, because [LevelCubit] is: there is no restart, no next level and no
/// save here, only the two ways opening a level can go. Driven with
/// `CpuDevice` rather than a window, the same door
/// `flutter3d_demo_dungeon/test/run_cubit_test.dart` uses — `LevelLoader`
/// needs a device and does not need a window.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_template_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

GraphicsDevice _device() => CpuDevice(
      width: 16,
      height: 9,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening the shipped level puts a body where its spawn is', () async {
    final cubit = LevelCubit();
    expect(cubit.state, isA<LevelLoading>());

    await cubit.open(_device(), world: CollisionWorld(), camera: CameraNode());

    final state = cubit.state;
    expect(state, isA<LevelReady>());
    expect((state as LevelReady).body.position.y, greaterThan(0.0),
        reason: 'lifted off the spawn point, not left standing in the floor');
  });

  test('a level that is not there fails loudly rather than silently', () async {
    // **This used to be a black screen for ever.** The load caught its own
    // throw and printed it, which is a line in a console nobody playing the
    // game can see.
    final cubit = LevelCubit();

    await cubit.open(
      _device(),
      world: CollisionWorld(),
      camera: CameraNode(),
      asset: 'assets/levels/no_such_level.json',
    );

    expect(cubit.state, isA<LevelFailed>());
  });
}
