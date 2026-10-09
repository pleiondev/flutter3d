/// The plugin host before any loop: versions, ids, dependency order, and
/// switching at a boundary.
///
///     dart test test/plugin_manager_test.dart
///
/// Against a registry that writes down what was registered, so a test reads
/// the effect of installing rather than the manager's own bookkeeping. Each
/// test was written by breaking what it covers; the mutation is named.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

/// A loop that keeps the systems registered, in registration order, by name.
final class _Loop extends LoopRegistry {
  final List<String> systems = <String>[];

  @override
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => Registration(() {});

  @override
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    systems.add(name);
    return Registration(() => systems.remove(name));
  }

  @override
  LoopRegistry forPlugin(PluginScope scope) => _ScopedLoop(this, scope);
}

final class _ScopedLoop extends LoopRegistry {
  _ScopedLoop(this._loop, this._scope);

  final _Loop _loop;
  final PluginScope _scope;

  @override
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => _loop.addPhase(phase);

  @override
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    final registration = _loop.addSystem(name, phase, system);
    _scope.track(registration);
    return registration;
  }

  @override
  LoopRegistry forPlugin(PluginScope scope) => _loop.forPlugin(scope);
}

final class _Events extends EventRegistry {
  @override
  List<EventDeclaration> get declared => const <EventDeclaration>[];

  @override
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    String? description,
    EventCodec<T>? codec,
  }) => Registration(() {});

  @override
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  void publish(BusEvent event) {}

  @override
  EventRegistry forPlugin(PluginScope scope) => this;
}

/// A plugin that registers one system named after itself.
final class _Plugin extends Flutter3dPlugin {
  _Plugin(
    this.id, {
    this.dependsOn = const <String>[],
    this.api = PluginApiVersion.current,
    this.backends = const <String>{},
  });

  final String id;
  final List<String> dependsOn;
  final PluginApiVersion api;
  final Set<String> backends;
  int uninstalled = 0;

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: api,
    dependsOn: dependsOn,
    backends: backends,
  );

  @override
  void install(PluginHost host) {
    host.loop.addSystem(id, LoopPhase.rules, (_) {});
  }

  @override
  void uninstall(PluginHost host) => uninstalled++;
}

void main() {
  late _Loop loop;
  PluginManager manager({String? backend}) {
    loop = _Loop();
    return PluginManager(loop: loop, events: _Events(), backend: backend);
  }

  group('the API version', () {
    test(
      'an older minor installs, a newer minor or another major does not',
      () {
        // Mutation: compare only majors. The newer-minor case installs.
        const engine = PluginApiVersion(1, 2);
        expect(const PluginApiVersion(1, 0).refusalOn(engine), isNull);
        expect(const PluginApiVersion(1, 2).refusalOn(engine), isNull);
        expect(
          const PluginApiVersion(1, 3).refusalOn(engine),
          allOf(contains('needs plugin API 1.3'), contains('provides 1.2')),
        );
        expect(
          const PluginApiVersion(2, 0).refusalOn(engine),
          allOf(contains('2.0'), contains('major version')),
        );
        expect(
          const PluginApiVersion(0, 9).refusalOn(engine),
          contains('major version'),
        );
      },
    );

    test('install refuses a plugin for another API, naming it', () {
      // Mutation: skip the check in installAll. Nothing throws, and the
      // system of a plugin written for API 2 is registered.
      final plugins = manager();
      expect(
        () => plugins.installAll(<Flutter3dPlugin>[
          _Plugin('future', api: const PluginApiVersion(2, 0)),
        ]),
        throwsA(
          isA<PluginException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"future"'), contains('2.0'), contains('1.0')),
          ),
        ),
      );
      expect(loop.systems, isEmpty);
    });

    test('reads MAJOR.MINOR and refuses anything else', () {
      expect(PluginApiVersion.parse('1.4'), const PluginApiVersion(1, 4));
      expect(() => PluginApiVersion.parse('1'), throwsFormatException);
      expect(() => PluginApiVersion.parse('1.0.0'), throwsFormatException);
    });
  });

  group('the manifest', () {
    test('a kind of touch this build does not know is kept, and held to '
        'the simulation\'s rules', () {
      // Mutation: read an unknown name as `simulation`, and writing the
      // manifest back turns a later minor's kind into the wrong word.
      final manifest = PluginManifest.fromJson(<String, Object?>{
        'id': 'trails',
        'apiVersion': '1.0',
        'touches': 'audio',
      });
      expect(manifest.touches.name, 'audio');
      expect(manifest.touches.isKnown, isFalse);
      expect(manifest.touches.simulates, isTrue);
      expect(manifest.toJson()['touches'], 'audio');
      expect(PluginTouches.named('view'), PluginTouches.view);
    });

    test('keeps keys it does not know, and writes them back', () {
      // Mutation: drop `extra` from toJson. A tool that rewrites a manifest
      // strips a later minor's fields.
      final manifest = PluginManifest.fromJson(<String, Object?>{
        'id': 'trails',
        'apiVersion': '1.0',
        'touches': 'view',
        'catalogue': <String, Object?>{'tag': 'effects'},
      });
      expect(manifest.touches, PluginTouches.view);
      expect(manifest.extra, <String, Object?>{
        'catalogue': <String, Object?>{'tag': 'effects'},
      });
      expect(manifest.toJson()['catalogue'], <String, Object?>{
        'tag': 'effects',
      });
    });

    test('a touches this build does not know reads as the simulation', () {
      // The safe misreading: a toggle of it is journalled as one that
      // changes the run.
      expect(PluginTouches.named('network-tick'), PluginTouches.simulation);
      expect(PluginTouches.named('network-tick').simulates, isTrue);
    });

    test('an id that cannot be a namespace is refused', () {
      expect(
        () => manager().installAll(<Flutter3dPlugin>[_Plugin('My Plugin')]),
        throwsA(isA<PluginException>()),
      );
      expect(
        () =>
            manager().installAll(<Flutter3dPlugin>[_Plugin('a'), _Plugin('a')]),
        throwsA(
          isA<PluginException>().having(
            (e) => e.message,
            'message',
            contains('two plugins are named "a"'),
          ),
        ),
      );
    });
  });

  group('dependency order', () {
    test('dependencies install first, and ties keep the order given', () {
      // Heat moves up to the place of fire, which waits for it; ui keeps its
      // place after fire. Mutation: take the earliest ready plugin instead of
      // the one the earliest waiting plugin needs. Ui slips ahead of heat.
      final plugins = manager()
        ..installAll(<Flutter3dPlugin>[
          _Plugin('fire', dependsOn: <String>['heat']),
          _Plugin('ui'),
          _Plugin('heat'),
          _Plugin('smoke', dependsOn: <String>['fire']),
        ]);
      expect(plugins.order, <String>['heat', 'fire', 'ui', 'smoke']);
      expect(loop.systems, <String>['heat', 'fire', 'ui', 'smoke']);
    });

    test('a missing dependency names the plugin and what it wanted', () {
      expect(
        () => manager().installAll(<Flutter3dPlugin>[
          _Plugin('fire', dependsOn: <String>['heat']),
        ]),
        throwsA(
          isA<PluginException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"fire"'), contains('"heat"')),
          ),
        ),
      );
    });

    test('a cycle is an error naming every plugin in it', () {
      // Mutation: return the partial order instead of throwing. The three
      // plugins in the cycle are silently never installed.
      expect(
        () => manager().installAll(<Flutter3dPlugin>[
          _Plugin('free'),
          _Plugin('a', dependsOn: <String>['c']),
          _Plugin('b', dependsOn: <String>['a']),
          _Plugin('c', dependsOn: <String>['b']),
        ]),
        throwsA(
          isA<ConstraintCycleException>()
              .having((e) => e.what, 'what', 'plugins')
              .having((e) => e.cycle.toSet(), 'cycle', <String>{'a', 'b', 'c'})
              .having((e) => e.toString(), 'message', contains('→')),
        ),
      );
    });

    test('a plugin for another backend is installed off, with a reason', () {
      final plugins = manager(backend: 'webgl')
        ..installAll(<Flutter3dPlugin>[
          _Plugin('compute', backends: <String>{'webgpu'}),
          _Plugin('needs-compute', dependsOn: <String>['compute']),
        ]);
      expect(loop.systems, isEmpty);
      expect(plugins.statuses.map((s) => s.reason), <Matcher>[
        contains('webgpu'),
        contains('"compute"'),
      ]);
      expect(() => plugins.enable('compute'), throwsA(isA<PluginException>()));
    });
  });

  group('switching', () {
    test('takes effect at the boundary, and is journalled with its step', () {
      // Mutation: install in `enable` itself. The system is there before
      // the boundary, which is in the middle of whatever step is running.
      final heat = _Plugin('heat');
      final plugins = manager()..installAll(<Flutter3dPlugin>[heat]);
      plugins.disable('heat');
      expect(loop.systems, <String>['heat'], reason: 'not before the boundary');
      final applied = plugins.applyPending(12);
      expect(loop.systems, isEmpty);
      expect(heat.uninstalled, 1);
      expect(applied.single, isA<PluginDisabled>());
      expect(applied.single.step, 12);
      expect(applied.single.affectsSimulation, isTrue);

      plugins.enable('heat');
      plugins.applyPending(20);
      expect(loop.systems, <String>['heat']);
      expect(plugins.journal.map((c) => c.toString()), <String>[
        'disable heat at step 12',
        'enable heat at step 20',
      ]);
    });

    test('a dependency cannot be switched off under an enabled dependent', () {
      final plugins = manager()
        ..installAll(<Flutter3dPlugin>[
          _Plugin('heat'),
          _Plugin('fire', dependsOn: <String>['heat']),
        ]);
      expect(
        () => plugins.disable('heat'),
        throwsA(
          isA<PluginException>().having(
            (e) => e.message,
            'message',
            contains('"fire"'),
          ),
        ),
      );
      // Off in the right order is fine, and is checked against the pending
      // requests rather than the present.
      plugins
        ..disable('fire')
        ..disable('heat');
      expect(() => plugins.enable('fire'), throwsA(isA<PluginException>()));
      plugins.applyPending(1);
      expect(loop.systems, isEmpty);
    });

    test('a scheduled journal is made at the same steps', () {
      // Mutation: apply scheduled changes after the requests, or not at
      // all. The replay's order of systems differs from the run's.
      final live = manager()
        ..installAll(<Flutter3dPlugin>[_Plugin('a'), _Plugin('b')]);
      live.disable('a');
      live.applyPending(5);
      live.enable('a');
      live.applyPending(9);
      live.reorder(<String>['b', 'a']);
      live.applyPending(9);

      final replay = manager()
        ..installAll(<Flutter3dPlugin>[_Plugin('a'), _Plugin('b')])
        ..schedule(live.journal);
      for (var step = 0; step < 12; step++) {
        replay.applyPending(step);
      }
      expect(replay.order, live.order);
      expect(
        replay.journal.map((c) => c.toJson()),
        live.journal.map((c) => c.toJson()),
      );
    });

    test('changes survive a trip through JSON', () {
      for (final change in <PluginChange>[
        const PluginEnabled(step: 3, plugin: 'a', affectsSimulation: true),
        const PluginDisabled(step: 4, plugin: 'b', affectsSimulation: false),
        const PluginsReordered(
          step: 5,
          order: <String>['b', 'a'],
          affectsSimulation: true,
        ),
        const PluginsSet(
          step: 0,
          order: <String>['a', 'b'],
          enabled: <String>['b'],
          affectsSimulation: true,
        ),
      ]) {
        expect(
          PluginChange.fromJson(change.toJson()).toJson(),
          change.toJson(),
        );
      }
      expect(
        () => PluginChange.fromJson(<String, Object?>{
          'kind': 'teleport',
          'step': 1,
        }),
        throwsFormatException,
      );
    });
  });

  test('a registry the engine does not have is refused by name', () {
    Object? refusal;
    final plugins = manager();
    plugins.installAll(<Flutter3dPlugin>[_AsksForEditor((e) => refusal = e)]);
    expect(refusal, isA<StateError>());
    expect('$refusal', allOf(contains('_MissingSlot'), contains('"asks"')));
  });
}

/// A registry slot no engine in this test fills, as an editor's is in a
/// game.
abstract base class _MissingSlot extends PluginRegistry {}

final class _AsksForEditor extends Flutter3dPlugin {
  _AsksForEditor(this.caught);

  final void Function(Object error) caught;

  @override
  PluginManifest get manifest =>
      const PluginManifest(id: 'asks', apiVersion: PluginApiVersion(1, 0));

  @override
  void install(PluginHost host) {
    expect(host.maybeRegistry<_MissingSlot>(), isNull);
    try {
      host.registry<_MissingSlot>();
    } on StateError catch (error) {
      caught(error);
    }
  }
}
