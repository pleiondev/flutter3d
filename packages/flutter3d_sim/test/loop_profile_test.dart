/// The loop's simulation profile: carried by its simulation version, handed
/// to plugins and the world, and what the double-step check asks.
///
///     dart test test/loop_profile_test.dart
library;

import 'package:flutter3d_physics/flutter3d_physics.dart' show CollisionWorld;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  test('the default loop is deterministic and its version reads as before', () {
    final loop = EngineLoop(input: InputState());
    expect(loop.profile, SimulationProfile.deterministic);
    expect(loop.simulationVersion, SimulationVersion.engineOnly);
    expect(loop.simulationVersion.toJson(), <String, Object?>{'engine': 1});
  });

  test('an accurate loop names its profile, and a run on it is refused on '
      'the default', () {
    final loop = EngineLoop(
      input: InputState(),
      profile: SimulationProfile.accurate,
    );
    expect(loop.simulationVersion.profile, SimulationProfile.accurate);
    expect(
      loop.simulationVersion.refusalOn(
        EngineLoop(input: InputState()).simulationVersion,
      ),
      contains('accurate'),
    );
    expect(loop.plugins.profile, SimulationProfile.accurate);
  });

  test('the double-step check runs only under a bit-exact profile', () {
    final check = DeterminismCheck();
    expect(
      EngineLoop(
        input: InputState(),
        determinismCheck: check,
      ).checksDeterminism,
      isTrue,
    );
    // Mutation: arm it whatever the profile, and an accurate laboratory
    // fails a check its profile never promised.
    expect(
      EngineLoop(
        input: InputState(),
        determinismCheck: check,
        profile: SimulationProfile.accurate,
      ).checksDeterminism,
      isFalse,
    );
  });

  test('a staged world takes the loop\'s profile, and the default world is '
      'left as it was', () {
    final world = CollisionWorld();
    final before = world.properties;
    EngineLoop(input: InputState()).stageWorld(world);
    expect(identical(world.properties, before), isTrue);
    EngineLoop(
      input: InputState(),
      profile: SimulationProfile.accurate,
    ).stageWorld(world);
    expect(world.properties.profile, SimulationProfile.accurate);
  });
}
