/// A plugin that touches only tooling, an editor's or an agent's, beside the
/// racing game: the run's version and the racing tape are those of the game
/// alone, and a claim of tooling does not cover a solver or a step phase.
///
///     flutter test test/tooling_plugin_test.dart
///
/// The digests are the ones `default_simulation_test.dart` recorded before
/// the registries, and are never re-recorded to make this green.
library;

import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outside_plugin/outside_plugin.dart';

import 'racing_tape.dart';
import 'support/install_refusal.dart';

/// The racing tape's digest every 60 steps of 600, as recorded.
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

/// The racing loop's version with no plugin beside the genre.
const Map<String, Object?> _recordedVersion = <String, Object?>{
  'engine': 1,
  'genre': 'racing',
  'genreVersion': 1,
  'plugins': <String, Object?>{'flutter3d_game_racing': 1},
};

/// A plugin that says it touches only tooling, with a simulation number
/// that would show in the version if it were read, and does [body] when
/// installed.
final class _Tooling extends Flutter3dPlugin {
  _Tooling([this.body]);

  final void Function(PluginHost host)? body;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: 'outside.editor',
    // The version it was written against, as a plugin states it: a
    // literal, never `current`, which moves with the engine it runs on.
    apiVersion: PluginApiVersion(1, 0),
    simulationVersion: 7,
    touches: PluginTouches.tooling,
  );

  @override
  void install(PluginHost host) => body?.call(host);
}

/// A step phase of the plugin's own.
const LoopPhase _cooling = LoopPhase.step('outside.cooling');

/// The refusal of the tooling plugin for [what]: kept in its status, the
/// plugin switched off.
Matcher _refused(String what) => isA<PluginException>().having(
  (PluginException e) => e.message,
  'message',
  allOf(
    contains('"outside.editor"'),
    contains('only tooling'),
    contains(what),
  ),
);

/// A loop with only [plugin] beside it, and what its install was refused.
Object? _refusalOf(Flutter3dPlugin plugin) {
  final loop = EngineLoop(
    input: InputState(),
    plugins: <Flutter3dPlugin>[plugin],
  );
  expect(loop.plugins.isEnabled('outside.editor'), isFalse);
  return installRefusal(loop.plugins);
}

void main() {
  test('installed beside the racing game, it leaves the version and the '
      'tape alone', () {
    // Mutation: count a tooling plugin among those that simulate. Its
    // number would join `plugins`, and a run recorded in the editor would
    // be refused by the game that never installs it.
    final loop = racingLoop(
      plugins: <Flutter3dPlugin>[
        _Tooling((host) {
          // What a tooling plugin may do in a loop: hear the frame.
          host.events.onFrame<ContactEvent>('outside.editor.seen', (_) {});
        }),
      ],
    );
    expect(loop.plugins.isEnabled('outside.editor'), isTrue);
    expect(loop.simulationVersion.toJson(), _recordedVersion);
    expect(digestsOf(loop), _recorded);
  });

  test('claiming tooling, it is refused a solver, even one its profile '
      'leaves off', () {
    // Mutation: refuse only a solver that runs. Switched on by a profile,
    // the plugin would step the world it said it does not touch.
    expect(
      _refusalOf(
        _Tooling((host) {
          host.registry<FieldRegistry>().declare(heatField);
          host.registry<SubsystemRegistry>().register(Warming());
        }),
      ),
      _refused('the subsystem "${Warming.id}"'),
    );
  });

  test('and a step phase, a step system and a step subscription', () {
    for (final (what, body) in <(String, void Function(PluginHost))>[
      ('the step phase', (host) => host.loop.addPhase(_cooling)),
      (
        'the system',
        (host) => host.loop.addSystem('outside.cool', LoopPhase.rules, (_) {}),
      ),
      (
        'subscribed',
        (host) => host.events.onStep<ContactEvent>('outside.heard', (_) {}),
      ),
    ]) {
      expect(_refusalOf(_Tooling(body)), _refused(what), reason: what);
    }
  });
}
