/// Opening the one level this seed has, and the genre that walks it.
///
///     flutter test test/open_level_test.dart
///
/// Driven with `CpuDevice` rather than a window: `LevelLoader` needs a device
/// and does not need a window, and the genre needs neither.
library;

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_example/main.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 9,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening the shipped level puts a body where its spawn is', () async {
    final status = await openLevel(_device());

    expect(status, isA<RunPlaying<WalkableLevel>>());
    expect(
      (status as RunPlaying<WalkableLevel>).level.walk.body.position.y,
      greaterThan(0.0),
      reason: 'lifted off the spawn point, not left standing in the floor',
    );
  });

  test('a level that is not there fails loudly rather than silently', () async {
    // **This used to be a black screen for ever.** The load caught its own
    // throw and printed it, which is a line in a console nobody playing the
    // game can see.
    final status = await openLevel(
      _device(),
      asset: 'assets/levels/no_such_level.json',
    );

    expect(status, isA<RunFailed<WalkableLevel>>());
  });

  test('the genre steps the walk and says on the bus when it lands', () async {
    // Mutation: publish `Landed` on every grounded step. The screen would
    // hear a landing sixty times a second while the body stood still.
    final status = await openLevel(_device()) as RunPlaying<WalkableLevel>;
    final input = InputState();
    final genre = WalkGenre(input: input);
    final loop = EngineLoop(input: input, plugins: <Flutter3dPlugin>[genre]);
    genre.simulation = status.level.walk;
    final landings = <double>[];
    loop.events.onFrame<Landed>(
      'test',
      (Delivered<Landed> delivered) => landings.add(delivered.event.speed),
    );

    // Settled onto the floor first, whatever the spawn's height.
    for (var i = 0; i < 120; i++) {
      loop.frame(1 / 60);
    }
    landings.clear();

    input.press(GameAction.jump);
    loop.frame(1 / 60);
    input.release(GameAction.jump);
    for (var i = 0; i < 180; i++) {
      loop.frame(1 / 60);
    }

    expect(landings, hasLength(1), reason: 'one jump, one landing');
    expect(landings.single, greaterThan(0.0));
  });
}
