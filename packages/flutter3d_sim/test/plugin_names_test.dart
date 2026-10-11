/// Every name a plugin registers on the simulation side is in its namespace
/// (D23): component codecs, events, phases, systems, assimilations, snapshot
/// parts, entity kinds, behavior kinds, probe samplers and questions.
///
///     dart test test/plugin_names_test.dart
///
/// Each registry is checked three ways: a plugin from outside registering a
/// bare name is refused with the name in the sentence, the same name in its
/// namespace is taken, and one of the engine's own packages registers the
/// engine's bare names. Mutation: drop the `nameProblem` call from any one
/// registry and two outside plugins that both register `health` meet in a
/// save file.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// A plugin that runs [registers] when installed.
final class _Plugin extends Flutter3dPlugin {
  _Plugin(this.id, this.registers);

  final String id;
  final void Function(PluginHost host) registers;

  @override
  PluginManifest get manifest =>
      PluginManifest(id: id, apiVersion: PluginApiVersion.current);

  @override
  void install(PluginHost host) => registers(host);
}

final class _Health {
  const _Health(this.points);

  final int points;
}

final class _Hurt extends BusEvent {
  const _Hurt();

  @override
  String get name => 'acme.hurt';
}

final class _Crate extends EntityKind {
  const _Crate(super.type);
}

/// Installs one plugin named [id] that runs [registers] into a fresh loop.
void _install(String id, void Function(PluginHost host) registers) {
  EngineLoop(
    input: InputState(),
    registries: <PluginRegistry>[
      EntityKinds(),
      BehaviorKindsRegistry(BehaviorKinds()),
    ],
    plugins: <Flutter3dPlugin>[_Plugin(id, registers)],
  );
}

/// A refusal that names [name] and the namespace it should be in.
Matcher _refused(String name) => throwsA(
  isA<PluginException>().having(
    (e) => e.message,
    'message',
    allOf(contains('"$name"'), contains('acme.<name>')),
  ),
);

/// Each simulation-side registry, as a function registering [name] there.
final Map<String, void Function(PluginHost host, String name)> _registries =
    <String, void Function(PluginHost host, String name)>{
      'a component codec': (host, name) =>
          host.registry<ComponentRegistry>().register<_Health>(
            ComponentCodec<_Health>.of(
              id: name,
              encode: (health) => health.points,
              decode: (data, _) => data is int ? _Health(data) : null,
            ),
          ),
      'an event': (host, name) => host.events.declare<_Hurt>(name),
      'a phase': (host, name) => host.loop.addPhase(
        LoopPhase.step(name),
        after: <String>[LoopPhase.physics.name],
      ),
      'a system': (host, name) =>
          host.loop.addSystem(name, LoopPhase.rules, (_) {}),
      'an assimilation': (host, name) =>
          host.loop.addAssimilation(name, Assimilation.of((_) {})),
      'a snapshot part': (host, name) => host.registry<SnapshotRegistry>().add(
        SnapshotPart.of(id: name, capture: () => null, restore: (_, _) {}),
      ),
      'an entity kind': (host, name) =>
          host.registry<EntityKinds>().add(_Crate(name)),
      'a behavior leaf': (host, name) => host
          .registry<BehaviorKindsRegistry>()
          .leaf(name, BehaviorKinds().leafBuilder('wait')!),
      'a probe sampler': (host, name) => host.registry<ProbeSamplers>().add(
        name,
        ProbeSampler.of((_) => null),
      ),
      'a question': (host, name) =>
          host.registry<SimulationQueryRegistry>().add(name, (_, _) => null),
    };

void main() {
  for (final MapEntry(key: what, value: register) in _registries.entries) {
    group(what, () {
      test('is refused outside the plugin\'s namespace, by name', () {
        expect(
          () => _install('acme', (h) => register(h, 'health')),
          _refused('health'),
        );
      });

      test('is taken in the plugin\'s namespace', () {
        expect(
          () => _install('acme', (h) => register(h, 'acme.health')),
          returnsNormally,
        );
      });

      test('is taken bare from one of the engine\'s own packages', () {
        expect(
          () => _install('flutter3d_game_racing', (h) => register(h, 'health')),
          returnsNormally,
        );
      });
    });
  }

  test('a package named like the engine\'s is held to its namespace', () {
    // Mutation: decide engine-ness by the `flutter3d_` prefix again.
    expect(
      () => _install(
        'flutter3d_frost',
        (h) => h.loop.addSystem('melt', LoopPhase.rules, (_) {}),
      ),
      throwsA(isA<PluginException>()),
    );
  });

  test('a snapshot part may be named after the plugin that adds it', () {
    // A genre's run is a part under its plugin id, which no other plugin of
    // the engine has.
    expect(
      () => _install(
        'acme',
        (h) => h.registry<SnapshotRegistry>().add(
          SnapshotPart.of(id: 'acme', capture: () => null, restore: (_, _) {}),
        ),
      ),
      returnsNormally,
    );
  });

  test('an entity kind of the level format\'s own words is shared', () {
    // A door is the format's word, not one a plugin takes: a plugin may
    // bring the kind that spawns it.
    expect(
      () => _install(
        'acme',
        (h) => h.registry<EntityKinds>().add(const DoorKind()),
      ),
      returnsNormally,
    );
  });

  test('a standard behavior kind may be replaced by a plugin', () {
    expect(
      () => _install(
        'acme',
        (h) => h.registry<BehaviorKindsRegistry>().leaf(
          'wait',
          BehaviorKinds().leafBuilder('wait')!,
          replace: true,
        ),
      ),
      returnsNormally,
    );
  });
}
