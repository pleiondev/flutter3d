/// The plugin suite, held to plugins whose faults are known: one that does
/// everything right, and one for each way a plugin goes wrong.
///
///     dart test test/plugin_conformance_test.dart
///
/// Each fixture is a plugin of a few lines over a world of two counters, so
/// a failing outcome names a fault the fixture was written to have. Each
/// test was written by breaking what it covers in the suite first; the
/// mutation that would defeat it is named in the test.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// Two counters: one the application steps, one the plugin does — kept
/// outside the loop and put into its snapshots as a part, the way a game's
/// own state is.
final class _World {
  List<int> values = <int>[0, 0];

  /// The counters as one part of a loop's snapshots.
  SnapshotPart get part => SnapshotPart.of(
    id: 'test.world',
    capture: () => List<int>.of(values),
    restore: (data, _) => values = <int>[
      for (final value in data! as List) (value as num).toInt(),
    ],
  );

  PluginHarness harness({
    int steps = 20,
    List<Flutter3dPlugin> Function()? dependencies,
    void Function(EngineLoop loop)? setUp,
  }) => PluginHarness(
    steps: steps,
    dependencies: dependencies,
    setUp: (loop) {
      loop
        ..snapshots.add(part)
        ..addSystem('world.advance', LoopPhase.physics, (_) => values[1]++);
      setUp?.call(loop);
    },
  );
}

final class _Tick extends BusEvent {
  const _Tick(this.name, this.value);

  @override
  final String name;
  final int value;

  @override
  void digestInto(EventDigestSink sink) => sink.add(value);
}

/// Counts in the rules phase and says so: what a plugin should be.
final class _Good extends Flutter3dPlugin {
  _Good(
    this.world, {
    this.backends = const <String>{},
    this.budget = const <String, Object?>{
      'stepMicroseconds': 1000000,
      'eventsPerStep': 4,
    },
    this.eventsPerStep = 1,
  });

  final _World world;
  final String id = 'good';
  final Set<String> backends;
  final Map<String, Object?>? budget;
  final int eventsPerStep;

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: PluginApiVersion.current,
    backends: backends,
    extra: <String, Object?>{'budget': ?budget},
  );

  @override
  void install(PluginHost host) {
    host.events.declare<_Tick>(
      '$id.tick',
      codec: EventCodec<_Tick>.of(
        encode: (tick) => tick.value,
        decode: (data, _) =>
            data is num ? _Tick('$id.tick', data.toInt()) : null,
      ),
    );
    host.loop.addSystem('$id.count', LoopPhase.rules, (context) {
      world.values[0]++;
      for (var i = 0; i < eventsPerStep; i++) {
        context.publish(_Tick('$id.tick', world.values[0]));
      }
    });
  }
}

/// Reads a counter kept outside the world, the way a plugin reads a clock:
/// the same step gives another answer each time it runs.
final class _Clocked extends Flutter3dPlugin {
  _Clocked(this.world);

  final _World world;
  static int _ticks = 0;

  @override
  PluginManifest get manifest =>
      PluginManifest(id: 'clocked', apiVersion: PluginApiVersion.current);

  @override
  void install(PluginHost host) {
    host.loop.addSystem(
      'clocked.read',
      LoopPhase.rules,
      (_) => world.values[0] = _ticks++,
    );
  }
}

/// Says it touches only the view, and adds a step system.
final class _ViewWithStep extends Flutter3dPlugin {
  @override
  PluginManifest get manifest => PluginManifest(
    id: 'liar',
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.view,
  );

  @override
  void install(PluginHost host) {
    host.loop.addSystem('liar.step', LoopPhase.rules, (_) {});
  }
}

/// Where a leaky plugin finds the loop it was not handed.
final class _Root {
  EngineLoop? loop;
}

/// Registers a phase on the application's loop rather than through its
/// host, so nothing takes it back when the plugin is switched off.
final class _Leaky extends Flutter3dPlugin {
  _Leaky(this.root);

  final _Root root;
  bool _leaked = false;

  @override
  PluginManifest get manifest =>
      PluginManifest(id: 'leaky', apiVersion: PluginApiVersion.current);

  @override
  void install(PluginHost host) {
    host.loop.addSystem('leaky.step', LoopPhase.rules, (_) {
      if (_leaked) return;
      _leaked = true;
      root.loop!.addPhase(
        const LoopPhase.step('leaked'),
        after: const <String>['rules'],
        before: const <String>['publish'],
      );
    });
  }
}

/// Brings one substance to the engine's catalogue, through its host.
final class _Substances extends Flutter3dPlugin {
  _Substances(this.material);

  final PhysicalMaterial material;

  @override
  PluginManifest get manifest =>
      PluginManifest(id: 'orchard', apiVersion: PluginApiVersion.current);

  @override
  void install(PluginHost host) =>
      host.registry<MaterialCatalog>().add(material);
}

PhysicalMaterial _jam({String source = 'Orchard lab notes, 2026'}) =>
    PhysicalMaterial(
      id: 'orchard.plumJam',
      name: 'plum jam',
      phase: MaterialPhase.liquid,
      mechanical: MechanicalProperties(density: 1300.0, source: source),
      fluid: FluidProperties(viscosity: 30.0, source: source),
    );

PluginCheckOutcome _only(List<PluginCheckOutcome> outcomes, String check) =>
    outcomes.singleWhere((o) => o.check == check);

void main() {
  test('a plugin that does everything right passes and earns the badge', () {
    // Mutation: build the switch check's baseline without the harness's
    // set-up. The loop with the plugin switched off then has a
    // "world.advance" the baseline lacks, and this fails.
    final world = _World();
    final outcomes = checkPluginConformance(
      () => _Good(world),
      harness: world.harness(),
    );
    for (final outcome in outcomes) {
      expect(outcome.passed, isTrue, reason: '$outcome');
      expect(outcome.declined, isFalse, reason: '$outcome');
    }
    expect(outcomes.map((o) => o.check).toSet(), pluginCheckNames.toSet());
    expect(
      outcomes.where((o) => o.check == 'backends').map((o) => o.backend),
      <String?>[null, 'cpu', 'webgl', 'webgpu', 'impeller'],
      reason: 'a plugin that names no backend is held to all of them',
    );
    expect(earnsBadge(outcomes), isTrue);
  });

  test('a plugin that reads a clock fails determinism, named with its '
      'system', () {
    // Mutation: compare only the world at the end of the run, not the
    // digest after every system. The divergence is still found, but the
    // sentence no longer names "clocked.read" or the plugin.
    final world = _World();
    final outcomes = checkPluginConformance(
      () => _Clocked(world),
      harness: world.harness(),
    );
    final determinism = _only(outcomes, 'determinism');
    expect(determinism.passed, isFalse);
    expect(determinism.says, contains('clocked.read'));
    expect(determinism.says, contains('"clocked"'));
    expect(earnsBadge(outcomes), isFalse);
  });

  test('a view plugin that adds a step system fails at the manifest with '
      'the loop\'s sentence', () {
    // Mutation: swallow the PluginException the loop throws at install.
    // The manifest reads and writes back cleanly, so only installing it
    // shows the lie.
    final outcomes = checkPluginConformance(_ViewWithStep.new);
    final manifest = _only(outcomes, 'manifest');
    expect(manifest.passed, isFalse);
    expect(manifest.says, contains('touches only the view'));
    expect(_only(outcomes, 'switch').passed, isFalse);
  });

  test('a plugin that registers around its host fails the switch', () {
    // Mutation: compare the loops' phases as sets of names without the
    // step phases' systems — or compare against the loop with the plugin
    // on. Either way the phase left behind goes unnoticed.
    final world = _World();
    final root = _Root();
    final outcomes = checkPluginConformance(
      () => _Leaky(root),
      harness: world.harness(setUp: (loop) => root.loop = loop),
    );
    final switched = _only(outcomes, 'switch');
    expect(switched.passed, isFalse);
    expect(switched.says, contains('left behind'));
    expect(switched.says, contains('leaked'));
  });

  test('a plugin that declares a backend passes there and is switched off '
      'elsewhere', () {
    // Mutation: build every backend's loop with no backend at all. The
    // plugin is then on everywhere, and the undeclared outcome fails.
    final world = _World();
    final outcomes = checkPluginConformance(
      () => _Good(world, backends: const <String>{'cpu'}),
      harness: world.harness(),
    );
    final backends = outcomes.where((o) => o.check == 'backends').toList();
    expect(backends.map((o) => o.backend), <String?>['cpu', 'webgl']);
    expect(backends.first.passed, isTrue, reason: '${backends.first}');
    expect(backends.last.passed, isTrue, reason: '${backends.last}');
    expect(backends.last.says, contains('switched off'));
  });

  test('no budget is declined, and a declined check keeps the badge', () {
    // Mutation: report a missing budget as passed. The plugin would then
    // earn the badge without having promised anything.
    final world = _World();
    final outcomes = checkPluginConformance(
      () => _Good(world, budget: null),
      harness: world.harness(),
    );
    final budget = _only(outcomes, 'budget');
    expect(budget.declined, isTrue);
    expect(budget.says, contains('declares no budget'));
    expect(earnsBadge(outcomes), isFalse);
  });

  test('a step publishing more events than the budget allows fails it', () {
    // Mutation: count the events of the last step only. Every step here
    // publishes three, so the last one is enough to catch it — set
    // eventsPerStep to grow with the step and it is not.
    final world = _World();
    final outcomes = checkPluginConformance(
      () => _Good(
        world,
        budget: const <String, Object?>{'eventsPerStep': 2},
        eventsPerStep: 3,
      ),
      harness: world.harness(),
    );
    final budget = _only(outcomes, 'budget');
    expect(budget.passed, isFalse);
    expect(budget.says, contains('published 3 events'));
  });

  test('a malformed budget fails the manifest rather than throwing', () {
    // Mutation: read the budget with casts. A string where a number goes
    // then throws out of the suite instead of failing one check.
    final world = _World();
    final outcomes = checkPluginConformance(
      () => _Good(
        world,
        budget: const <String, Object?>{'stepMicroseconds': 'fast'},
      ),
      harness: world.harness(),
    );
    expect(_only(outcomes, 'manifest').passed, isFalse);
    expect(_only(outcomes, 'manifest').says, contains('stepMicroseconds'));
    expect(_only(outcomes, 'budget').passed, isFalse);
  });

  test('without a world, determinism compares events and is declined', () {
    // Mutation: pass determinism outright when no world is given. A plugin
    // could then earn the badge with nothing ever compared but its events.
    final outcomes = checkPluginConformance(
      () => _Good(_World()),
      harness: const PluginHarness(steps: 20),
    );
    final determinism = _only(outcomes, 'determinism');
    expect(determinism.declined, isTrue);
    expect(determinism.says, contains('world was not compared'));
    expect(earnsBadge(outcomes), isFalse);
  });

  group('as tests', () {
    final world = _World();
    runPluginConformance(() => _Good(world), harness: world.harness());
  });

  test('a plugin that brings a cited substance passes materials, and '
      'takes it away when switched off', () {
    // Mutation: drop the disable-and-look from the check. It still passes
    // here, and a plugin adding to the catalogue behind its host's back
    // would too.
    final outcomes = checkPluginConformance(() => _Substances(_jam()));
    final materials = _only(outcomes, 'materials');
    expect(materials.passed, isTrue, reason: materials.says);
    expect(materials.says, contains('1 physical material'));
  });

  test('a substance with no source fails materials, naming its group', () {
    // Mutation: take the empty-source sentence out of materialProblemsOf.
    // The catalogue accepts an empty string, so nothing else catches it.
    final outcomes = checkPluginConformance(
      () => _Substances(_jam(source: ' ')),
    );
    final materials = _only(outcomes, 'materials');
    expect(materials.passed, isFalse);
    expect(materials.says, contains('names no source'));
    expect(earnsBadge(outcomes), isFalse);
  });

  test('a substance in the wrong unit is refused at install', () {
    // Grams per cubic centimetre: the catalogue refuses it, so the plugin
    // does not install, and both checks that build it say so.
    final outcomes = checkPluginConformance(
      () => _Substances(
        const PhysicalMaterial(
          id: 'orchard.plumJam',
          name: 'plum jam',
          phase: MaterialPhase.liquid,
          mechanical: MechanicalProperties(density: 1.3e-4, source: 'g/cm³'),
          fluid: FluidProperties(viscosity: 30.0, source: 'notes'),
        ),
      ),
    );
    expect(_only(outcomes, 'materials').passed, isFalse);
    expect(_only(outcomes, 'materials').says, contains('not plausible'));
    expect(_only(outcomes, 'manifest').passed, isFalse);
  });
}
