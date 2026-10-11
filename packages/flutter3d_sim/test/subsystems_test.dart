/// The loop's fields and subsystems: a solver registered with what it reads
/// and writes, run where its profile says, and the version composed from
/// the ones that run.
///
///     dart test test/subsystems_test.dart
library;

import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// The profile a minor would add to switch the soak on.
const SimulationProfile _wet = SimulationProfile(
  'acme.wet',
  isBitExact: true,
  usesDoublePrecision: false,
  allowsAdaptiveSteps: false,
);

FieldDeclaration _water({
  String id = 'acme.water',
  FieldAccess writer = const FieldAccess.simulation('acme.soak'),
  List<FieldAccess> readers = const <FieldAccess>[
    FieldAccess.frame('acme.ripples'),
  ],
  FieldResidence residence = FieldResidence.host,
}) => FieldDeclaration(
  id: id,
  quantity: 'f3d.wetness',
  unit: Unit.one,
  grid: const FieldGrid(3, 1, 2),
  residence: residence,
  writer: writer,
  readers: readers,
);

/// A solver that adds a tenth to the first cell of its field every step.
Subsystem _soak({
  String id = 'acme.soak',
  List<SimulationProfile>? switchedOnBy,
  List<String> writes = const <String>['acme.water'],
  List<String> reads = const <String>[],
  void Function(SubsystemContext context)? also,
}) => Subsystem.of(
  SubsystemDeclaration(
    id: id,
    version: 2,
    writesFields: writes,
    readsFields: reads,
    writesQuantities: const <String>['f3d.wetness'],
    switchedOnBy: switchedOnBy,
  ),
  (SubsystemContext context) {
    if (writes.isNotEmpty) {
      final water = context.field(writes.first);
      water.setValueAt(0, 0, 0, water.valueAt(0, 0, 0) + 0.1);
    }
    also?.call(context);
  },
);

/// The application's own state: a count every step adds one to, so the
/// world's digest moves step by step.
final class _Count {
  _Count(this.value);

  int value;

  static final ComponentCodec<_Count> codec = InPlaceCodec<_Count>.of(
    id: 'test.count',
    encode: (count) => count.value,
    restore: (count, data, _) => count.value = data! as int,
  );
}

EngineLoop _loop({
  SimulationProfile profile = SimulationProfile.deterministic,
  List<Flutter3dPlugin> plugins = const <Flutter3dPlugin>[],
}) {
  final loop = EngineLoop(
    input: InputState(),
    profile: profile,
    plugins: plugins,
  );
  loop.world.components.register<_Count>(_Count.codec);
  final counted = loop.world.spawn();
  loop.world.set(counted, _Count(0));
  loop.addSystem('test.count', LoopPhase.rules, (LoopContext context) {
    context.world.get<_Count>(counted)!.value += 1;
  });
  return loop;
}

List<int> _digests(EngineLoop loop, {int steps = 30}) => <int>[
  for (var i = 0; i < steps; i++) (loop..runSteps(1)).digest(),
];

final class _Acme extends Flutter3dPlugin {
  _Acme({this.touches = PluginTouches.simulation, this.subsystem});

  final PluginTouches touches;
  final Subsystem? subsystem;

  @override
  PluginManifest get manifest => PluginManifest(
    id: 'acme',
    apiVersion: PluginApiVersion.current,
    touches: touches,
  );

  @override
  void install(PluginHost host) {
    host.registry<FieldRegistry>().declare(_water());
    host.registry<SubsystemRegistry>().register(subsystem ?? _soak());
  }
}

void main() {
  group('the default simulation', () {
    test('is the same with a solver registered and not switched on', () {
      final plain = _loop();
      final registered = _loop();
      registered.fields.declare(_water());
      registered.subsystems.register(
        _soak(switchedOnBy: const <SimulationProfile>[_wet]),
      );

      // Mutation: add a registered subsystem's system whatever its
      // profiles. The soak would run in the default simulation.
      expect(registered.subsystems.declared, hasLength(1));
      expect(registered.subsystems.running, isEmpty);
      expect(registered.systemsIn(LoopPhase.fields), isEmpty);
      // Mutation: compose the version from every subsystem registered.
      expect(registered.simulationVersion, SimulationVersion.engineOnly);
      expect(registered.simulationVersion.toJson(), <String, Object?>{
        'engine': 1,
      });

      // Mutation: snapshot a host field when it is declared rather than
      // when its writer runs. Its zeros would join the state, and every
      // digest of the default simulation would move from step 1. The
      // registries are on every loop, so this is also the digest of a loop
      // from before there were registries, which the racing tape in
      // `examples/outside_plugin` holds to a recorded table.
      final digests = _digests(plain);
      expect(digests.toSet(), hasLength(30));
      expect(_digests(registered), digests);
      expect(registered.snapshots.parts, plain.snapshots.parts);
      expect(
        registered.fields.hostField('acme.water')!.values,
        everyElement(0),
      );
    });
  });

  group('a solver switched on by its profile', () {
    test('runs in its phase, and the version names it', () {
      final loop = _loop(profile: _wet);
      loop.fields.declare(_water());
      loop.subsystems.register(
        _soak(switchedOnBy: const <SimulationProfile>[_wet]),
      );
      expect(loop.systemsIn(LoopPhase.fields), <String>['acme.soak']);
      expect(loop.subsystems.versions, <String, int>{'acme.soak': 2});
      expect(loop.simulationVersion.subsystems, <String, int>{'acme.soak': 2});
      expect(
        loop.simulationVersion.refusalOn(
          SimulationVersion.engineOnly.withProfile(_wet),
        ),
        contains('acme.soak'),
      );
      loop.runSteps(3);
      expect(
        loop.fields.hostField('acme.water')!.valueAt(0, 0, 0),
        closeTo(0.3, 1e-6),
      );
    });

    test('its field is in the snapshots: a rollback puts it back', () {
      final loop = _loop()..fields.declare(_water());
      loop.subsystems.register(_soak());
      loop.runSteps(2);
      final saved = loop.capture();
      final digest = loop.digest();
      loop.runSteps(5);
      expect(loop.digest(), isNot(digest));
      // Mutation: leave the field out of the snapshots. The count goes back
      // and the water does not, and the digest says the two disagree.
      loop.restore(saved);
      expect(
        loop.fields.hostField('acme.water')!.valueAt(0, 0, 0),
        closeTo(0.2, 1e-6),
      );
      expect(loop.digest(), digest);
    });

    test('the view reads the copy the last step published', () {
      final loop = _loop()..fields.declare(_water());
      loop.subsystems.register(_soak());
      final published = loop.fields.published('acme.water')!;
      expect(published.valueAt(0, 0, 0), 0);
      expect(published.isWritable, isFalse);
      loop.runSteps(1);
      // Mutation: hand the view the simulation's own values. A frame read
      // between two steps of a catch-up would see half of one.
      expect(
        identical(
          published.values,
          loop.fields.hostField('acme.water')!.values,
        ),
        isFalse,
      );
      expect(
        loop.fields.published('acme.water')!.valueAt(0, 0, 0),
        closeTo(0.1, 1e-6),
      );
      // A field nobody outside the step reads is not copied.
      loop.fields.declare(
        _water(
          id: 'acme.puddles',
          writer: const FieldAccess.simulation('acme.pool'),
          readers: const <FieldAccess>[],
        ),
      );
      expect(loop.fields.published('acme.puddles'), isNull);
    });
  });

  group('a subsystem is held to what it declares', () {
    test('it is handed only its fields, read-only where it reads', () {
      final loop = _loop()
        ..fields.declare(_water())
        ..fields.declare(
          _water(
            id: 'acme.rain',
            writer: const FieldAccess.frame('acme.clouds'),
          ),
        );
      Object? readRefused;
      Object? undeclared;
      loop.subsystems
        ..register(_soak())
        ..register(
          _soak(
            id: 'acme.drip',
            writes: const <String>[],
            reads: const <String>['acme.water'],
            also: (SubsystemContext context) {
              try {
                context.field('acme.water').setValueAt(0, 0, 0, 9);
              } on Object catch (error) {
                readRefused = error;
              }
              try {
                context.field('acme.rain');
              } on Object catch (error) {
                undeclared = error;
              }
            },
          ),
        );
      loop.runSteps(1);
      // Mutation: hand a reader the writable values. The drip would write
      // a field whose writer is the soak, and no checker would know.
      expect(readRefused, isA<UnsupportedError>());
      expect(
        undeclared,
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('declared neither'),
        ),
      );
    });

    test('a field it names must be declared, in host memory, and its own '
        'to write', () {
      final loop = _loop()
        ..fields.declare(_water())
        ..fields.declare(
          _water(
            id: 'acme.glow',
            writer: const FieldAccess.frame('acme.lamps'),
            residence: FieldResidence.texture3D,
          ),
        );
      Matcher refused(String words) => throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => '${e.message}',
          'message',
          contains(words),
        ),
      );
      expect(
        () =>
            loop.subsystems.register(_soak(writes: const <String>['acme.mud'])),
        refused('nobody declared'),
      );
      expect(
        () => loop.subsystems.register(
          _soak(writes: const <String>[], reads: const <String>['acme.glow']),
        ),
        refused('held in texture3D'),
      );
      expect(
        () => loop.subsystems.register(_soak(id: 'acme.other')),
        refused('whose writer is simulation "acme.soak"'),
      );
      loop.subsystems.register(_soak());
      expect(
        () => loop.subsystems.register(_soak()),
        refused('already registered'),
      );
      expect(() => loop.fields.declare(_water()), refused('already declared'));
    });
  });

  group('a plugin', () {
    test('declares and registers under its own id, and takes both back '
        'when switched off', () {
      final loop = _loop(plugins: <Flutter3dPlugin>[_Acme()]);
      expect(loop.systemsIn(LoopPhase.fields), <String>['acme.soak']);
      expect(loop.fields.declared.single.id, 'acme.water');
      loop.runSteps(2);
      loop.plugins.disable('acme');
      loop.runSteps(1);
      // Mutation: track neither registration with the plugin's scope.
      expect(loop.systemsIn(LoopPhase.fields), isEmpty);
      expect(loop.fields.declared, isEmpty);
      expect(loop.subsystems.declared, isEmpty);
      expect(loop.simulationVersion.subsystems, isEmpty);
    });

    test('is refused a name outside its namespace', () {
      expect(
        () => _loop(
          plugins: <Flutter3dPlugin>[_Acme(subsystem: _soak(id: 'other.soak'))],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            contains('"acme.<name>"'),
          ),
        ),
      );
    });

    test('that touches only the view is refused a subsystem', () {
      expect(
        () => _loop(
          plugins: <Flutter3dPlugin>[_Acme(touches: PluginTouches.view)],
        ),
        throwsA(isA<PluginException>()),
      );
    });
  });
}
