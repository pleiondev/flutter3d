/// A data plugin's `effects`: `.f3dfx` documents it names or carries,
/// installed into the engine's `ParticleEffects` and started by the bus.
///
///     dart test test/data_plugin_effects_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        BusEvent,
        DataSection,
        EventDigestSink,
        Flutter3dPlugin,
        PluginRegistry;
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

String _document(Map<String, Object?> rest) => jsonEncode(<String, Object?>{
  'f3dplugin': 1,
  'manifest': <String, Object?>{'id': 'sparks', 'apiVersion': '1.0'},
  ...rest,
});

MemoryPluginSource _files(Map<String, String> files) =>
    MemoryPluginSource(<String, Uint8List>{
      for (final MapEntry(:key, :value) in files.entries)
        key: Uint8List.fromList(utf8.encode(value)),
    });

/// One effect, bursting 12 on the plugin's own `flare` and on the engine's
/// `elements.exploded`, and asking for a collision this build lacks.
const String _flare = '''
{
  "f3dfx": 1,
  "effects": [
    {
      "name": "flare",
      "count": 12,
      "lifetime": [0.3, 0.5],
      "size": 0.1,
      "color": [2.0, 1.2, 0.4],
      "emitter": {"shape": "sphere", "speed": [1.0, 3.0]},
      "affectors": [{"type": "collide", "against": "depth"}],
      "on": [{"event": "flare"}, {"event": "elements.exploded", "at": [0.0, 1.0, 0.0]}]
    }
  ]
}
''';

const String _flareEvent = 'flare';

/// A loader that reads `effects`, the section the particles register.
final DataPluginLoader _loader = DataPluginLoader(
  sections: DataSections(<DataSection>[effectsSection]),
);

void main() {
  test('a document the plugin names is read, installed and started', () async {
    // Mutation: leave the effects unread, or subscribe the trigger to the
    // bare "flare". The plugin's own event is published as "sparks.flare".
    final plugin = await _loader.load(
      _document(<String, Object?>{
        'events': <Object?>[
          <String, Object?>{'name': _flareEvent},
        ],
        'effects': <Object?>[
          <String, Object?>{'source': 'flare.f3dfx'},
        ],
      }),
      _files(const <String, String>{'flare.f3dfx': _flare}),
    );
    expect(plugin.document.resources, <String>['flare.f3dfx']);

    final particles = ParticleSystem(capacity: 256, seed: 3);
    final effects = ParticleEffects(particles);
    final loop = EngineLoop(
      input: InputState(),
      backend: RuntimeBackends.cpu,
      registries: <PluginRegistry>[effects],
      plugins: <Flutter3dPlugin>[plugin],
    );
    expect(effects.names, <String>['sparks.flare']);
    expect(plugin.notes.single, contains('depth'));

    // A position in Q16.16, as a module or a script hands it over.
    loop.events.publish(
      PluginDataEvent('sparks.flare', <int>[
        Fixed16.one * 2,
        Fixed16.one,
        -Fixed16.one * 3,
      ]),
    );
    loop.frame(0.0);
    expect(particles.aliveCount, 12);
    expect(effects.triggerCounts, (fired: 1, unplaced: 0));

    // Switched off, its effect and its subscriptions go with it.
    loop.plugins.disable('sparks');
    loop.runSteps(1);
    expect(effects.names, isEmpty);
    loop.events.publish(PluginDataEvent('sparks.flare', <int>[0, 0, 0]));
    loop.frame(0.0);
    expect(effects.triggerCounts.fired, 1);
  });

  test('a document written in place is read as one in a file is', () async {
    final plugin = await _loader.load(
      _document(<String, Object?>{
        'effects': <Object?>[jsonDecode(_flare)],
      }),
      _files(const <String, String>{}),
    );
    final effects = ParticleEffects(ParticleSystem(capacity: 64));
    EngineLoop(
      input: InputState(),
      backend: RuntimeBackends.webgpu,
      registries: <PluginRegistry>[effects],
      plugins: <Flutter3dPlugin>[plugin],
    );
    expect(effects['sparks.flare']!.effect.count, 12);
  });

  test(
    'a document that does not read refuses the plugin when it is loaded',
    () async {
      await expectLater(
        _loader.load(
          _document(<String, Object?>{
            'effects': <Object?>[
              <String, Object?>{'source': 'bad.f3dfx'},
            ],
          }),
          _files(const <String, String>{'bad.f3dfx': '{"f3dfx": 99}'}),
        ),
        throwsA(
          isA<DataPluginFormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('bad.f3dfx'), contains('newer engine')),
          ),
        ),
      );
    },
  );

  test(
    'an engine with no ParticleEffects refuses the effects by name',
    () async {
      final plugin = await _loader.load(
        _document(<String, Object?>{
          'effects': <Object?>[
            <String, Object?>{'source': 'flare.f3dfx'},
          ],
        }),
        _files(const <String, String>{'flare.f3dfx': _flare}),
      );
      expect(
        () => EngineLoop(
          input: InputState(),
          backend: RuntimeBackends.cpu,
          plugins: <Flutter3dPlugin>[plugin],
        ),
        throwsA(
          isA<PluginException>().having(
            (e) => e.message,
            'message',
            allOf(contains('flare'), contains('ParticleEffects')),
          ),
        ),
      );
      // An engine that draws nothing installs the rest and says so.
      EngineLoop(input: InputState(), plugins: <Flutter3dPlugin>[plugin]);
      expect(plugin.notes.single, contains('draws nothing'));
    },
  );

  test('an event of the plugin\'s carries its numbers in Q16.16', () {
    final numbers = DataPlugin.numbersOfDataEvent(
      PluginDataEvent('x.y', <int>[
        Fixed16.one,
        Fixed16.one * 2,
        Fixed16.one * 3,
        0,
        Fixed16.one,
        0,
      ]),
    )!;
    expect(numbers, <double>[1.0, 2.0, 3.0, 0.0, 1.0, 0.0]);
    expect(
      DataPlugin.numbersOfDataEvent(const _OtherEvent()),
      isNull,
      reason: 'only a data plugin\'s event carries numbers',
    );
  });
}

final class _OtherEvent extends BusEvent {
  const _OtherEvent();

  @override
  String get name => 'other';

  @override
  void digestInto(EventDigestSink sink) {}
}
