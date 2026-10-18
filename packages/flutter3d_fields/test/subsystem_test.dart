import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

const SimulationProfile _wet = SimulationProfile(
  'acme.wet',
  isBitExact: true,
  usesDoublePrecision: false,
  allowsAdaptiveSteps: false,
);

void main() {
  group('SubsystemDeclaration', () {
    test('runs in the fields phase and under every profile by default', () {
      const always = SubsystemDeclaration(id: 'acme.diffuse', version: 1);
      expect(always.phase, LoopPhase.fields);
      expect(always.problem, isNull);
      for (final profile in SimulationProfile.values) {
        expect(always.runsUnder(profile), isTrue);
      }
    });

    test('a solver switched on by a profile runs under that one alone', () {
      const added = SubsystemDeclaration(
        id: 'acme.soak',
        version: 2,
        switchedOnBy: <SimulationProfile>[_wet],
      );
      // Mutation: answer true for a null-free list. The default simulation
      // would run a solver a minor added, and its tapes would replay on
      // another simulation.
      expect(added.runsUnder(SimulationProfile.deterministic), isFalse);
      expect(added.runsUnder(SimulationProfile.accurate), isFalse);
      expect(added.runsUnder(_wet), isTrue);
    });

    test('names what is wrong with a declaration', () {
      expect(
        const SubsystemDeclaration(id: 'soak', version: 1).problem,
        contains('"soak"'),
      );
      expect(
        const SubsystemDeclaration(id: 'acme.soak', version: 0).problem,
        contains('starts at 1'),
      );
      expect(
        const SubsystemDeclaration(
          id: 'acme.soak',
          version: 1,
          phase: LoopPhase.render,
        ).problem,
        contains('fixed step'),
      );
      expect(
        const SubsystemDeclaration(
          id: 'acme.soak',
          version: 1,
          readsQuantities: <String>['wetness'],
        ).problem,
        contains('"wetness"'),
      );
      expect(
        const SubsystemDeclaration(
          id: 'acme.soak',
          version: 1,
          readsFields: <String>['acme.water'],
          writesFields: <String>['acme.water'],
        ).problem,
        contains('"acme.water"'),
      );
    });

    test('writes what it declares', () {
      expect(
        const SubsystemDeclaration(
          id: 'acme.soak',
          version: 3,
          after: <String>['acme.rain'],
          readsQuantities: <String>['f3d.temperature'],
          writesQuantities: <String>['f3d.wetness'],
          readsFields: <String>['acme.rain'],
          writesFields: <String>['acme.water'],
          switchedOnBy: <SimulationProfile>[_wet],
        ).toJson(),
        <String, Object?>{
          'id': 'acme.soak',
          'version': 3,
          'phase': 'fields',
          'after': <String>['acme.rain'],
          'readsQuantities': <String>['f3d.temperature'],
          'writesQuantities': <String>['f3d.wetness'],
          'readsFields': <String>['acme.rain'],
          'writesFields': <String>['acme.water'],
          'switchedOnBy': <String>['acme.wet'],
        },
      );
    });
  });

  test('Subsystem.of runs the step it is given', () {
    var ran = 0;
    final subsystem = Subsystem.of(
      const SubsystemDeclaration(id: 'acme.count', version: 1),
      (_) => ran++,
    );
    expect(subsystem.declaration.id, 'acme.count');
    subsystem.step(_Context(subsystem.declaration));
    expect(ran, 1);
  });
}

final class _Context extends SubsystemContext {
  _Context(this.declaration);

  @override
  final SubsystemDeclaration declaration;

  @override
  int get step => 0;

  @override
  double get dt => 1 / 60;

  @override
  bool get isResimulated => false;

  @override
  SimWorld get world => throw UnimplementedError();

  @override
  void publish(BusEvent event) {}

  @override
  HostField field(String id) => throw StateError(id);
}
