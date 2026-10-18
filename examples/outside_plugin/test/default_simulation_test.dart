/// The default simulation with the new registries and this plugin's solver
/// registered: the racing tape digests as it did before either existed.
///
///     flutter test test/default_simulation_test.dart
///
/// **The table below was recorded on the tree before fields and
/// subsystems** (the commit before "A solver says what it reads and writes,
/// and a field what it holds"), and is never re-recorded to make this
/// green: a solver a minor adds and a profile switches on leaves the
/// default simulation, its tapes and its matches alone, and this is the
/// tape that says so.
library;

import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outside_plugin/outside_plugin.dart';

import 'racing_tape.dart';

/// The racing tape's digest every 60 steps of 600, recorded before the
/// registries.
const List<String> _recorded = <String>[
  'c6685f8d',
  '7001875a',
  '30d413b6',
  'a629313d',
  'ecec2f64',
  'ce447b2',
  '505d626',
  'a15f107a',
  '657b94a6',
  '10f4bfb4',
];

/// The racing loop's version as the tree before the registries wrote it.
const Map<String, Object?> _recordedVersion = <String, Object?>{
  'engine': 1,
  'genre': 'racing',
  'genreVersion': 1,
  'plugins': <String, Object?>{'flutter3d_game_racing': 1},
};

/// Registers the plugin's field and solver with the loop as the
/// application, without installing the plugin: the registries on, a solver
/// in them, and the default profile.
void _registerWarming(EngineLoop loop) {
  loop.fields.declare(heatField);
  loop.subsystems.register(Warming());
}

void main() {
  test('the racing tape digests as recorded with a solver registered and '
      'not switched on', () {
    final loop = racingLoop(also: _registerWarming);
    expect(loop.subsystems.declared.single.id, Warming.id);
    expect(loop.subsystems.running, isEmpty);
    // Mutation: compose the version from every subsystem registered, or
    // write `subsystems: {}` for none. A hello of the default racing game
    // would no longer match one from before.
    expect(loop.simulationVersion.toJson(), _recordedVersion);
    // Mutation: snapshot a host field when it is declared. Its zeros would
    // join the state and every checkpoint below would move.
    expect(digestsOf(loop), _recorded);
  });

  test('and with nothing registered, the registries alone', () {
    final loop = racingLoop();
    expect(loop.simulationVersion.toJson(), _recordedVersion);
    expect(digestsOf(loop), _recorded);
  });

  test('switched on by its profile, the solver is the simulation\'s and the '
      'version names it', () {
    final loop = EngineLoop(
      input: InputState(),
      profile: warmingProfile,
      plugins: <Flutter3dPlugin>[OutsidePlugin()],
    );
    expect(loop.subsystems.running.single.id, Warming.id);
    expect(loop.simulationVersion.subsystems, <String, int>{Warming.id: 1});
    expect(
      loop.simulationVersion.refusalOn(
        SimulationVersion.engineOnly.withProfile(warmingProfile),
      ),
      isNotNull,
    );
    expect(heatField.residence, FieldResidence.host);
  });
}
