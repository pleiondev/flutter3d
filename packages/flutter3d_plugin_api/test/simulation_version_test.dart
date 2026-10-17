import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

void main() {
  group('SimulationVersion.subsystems', () {
    test('the default simulation names none and writes as it did', () {
      // Mutation: write `subsystems: {}` always. Every run file and hello of
      // the default simulation would change by a key, and a 1.0 reader
      // would see a simulation it never wrote.
      expect(SimulationVersion.engineOnly.subsystems, isEmpty);
      expect(SimulationVersion.engineOnly.toJson(), <String, Object?>{
        'engine': 1,
      });
      expect(
        const SimulationVersion(
          genre: 'racing',
        ).withSubsystems(const <String, int>{}),
        const SimulationVersion(genre: 'racing'),
      );
    });

    test('a running subsystem is part of the simulation and of its words', () {
      final soaked = SimulationVersion.engineOnly.withSubsystems(
        const <String, int>{'acme.soak': 2, 'acme.dry': 1},
      );
      expect(soaked, isNot(SimulationVersion.engineOnly));
      expect(soaked.hashCode, isNot(SimulationVersion.engineOnly.hashCode));
      expect(soaked.describe(), 'engine 1, acme.dry 1, acme.soak 2');
      expect(soaked.toJson(), <String, Object?>{
        'engine': 1,
        'subsystems': <String, Object?>{'acme.dry': 1, 'acme.soak': 2},
      });
      expect(SimulationVersion.fromJson(soaked.toJson()), soaked);
      // Kept through the other withers.
      expect(
        soaked.withPlugins(const <String, int>{'acme': 1}).subsystems,
        soaked.subsystems,
      );
      expect(
        soaked.withProfile(SimulationProfile.accurate).subsystems,
        soaked.subsystems,
      );
      expect(soaked.withGenre('racing', 1).subsystems, soaked.subsystems);
    });

    test('a run recorded with a subsystem is refused without it, and the '
        'other way round', () {
      final on = SimulationVersion.engineOnly.withSubsystems(
        const <String, int>{'acme.soak': 2},
      );
      // Mutation: compare plugins alone. A run recorded with a solver on
      // would replay into a simulation that has it off.
      expect(
        on.refusalOn(SimulationVersion.engineOnly),
        allOf(contains('acme.soak'), contains('not running here')),
      );
      expect(
        SimulationVersion.engineOnly.refusalOn(on),
        allOf(contains('acme.soak'), contains('was not')),
      );
      expect(
        on.refusalOn(
          SimulationVersion.engineOnly.withSubsystems(const <String, int>{
            'acme.soak': 3,
          }),
        ),
        contains('acme.soak 2'),
      );
      expect(on.refusalOn(on), isNull);
    });

    test('a number that is not one is refused', () {
      expect(
        () => SimulationVersion.fromJson(<String, Object?>{
          'engine': 1,
          'subsystems': <String, Object?>{'acme.soak': 0},
        }),
        throwsA(isA<PluginFormatException>()),
      );
      expect(
        () => SimulationVersion.fromJson(<String, Object?>{
          'engine': 1,
          'subsystems': 3,
        }),
        throwsA(isA<PluginFormatException>()),
      );
    });
  });

  group('what a newer build wrote', () {
    // A minor that adds a dimension of the simulation's identity writes a
    // key this build does not know.
    final newer = <String, Object?>{
      'engine': 1,
      'genre': 'racing',
      'genreVersion': 2,
      'weather': <String, Object?>{'model': 'storms', 'version': 3},
    };

    test('is kept, and written back as it was read', () {
      // Mutation: read only the known keys. A relay or a tool that reads a
      // hello and writes it again strips the newer dimension.
      final read = SimulationVersion.fromJson(newer);
      expect(read.extra, <String, Object?>{
        'weather': <String, Object?>{'model': 'storms', 'version': 3},
      });
      expect(read.toJson(), newer);
      expect(
        read.withPlugins(const <String, int>{'acme': 1}).extra,
        read.extra,
      );
      expect(read.withProfile(SimulationProfile.accurate).extra, read.extra);
      expect(read.withSubsystems(const <String, int>{}).extra, read.extra);
      expect(read.withGenre('shooter', 1).extra, read.extra);
    });

    test('is another simulation, refused rather than replayed', () {
      // Mutation: leave `extra` out of `==` and `refusalOn`. A 1.0 client
      // reads the newer simulation as its own and replays or matches across
      // two different ones.
      final read = SimulationVersion.fromJson(newer);
      const running = SimulationVersion(genre: 'racing', genreVersion: 2);
      expect(read, isNot(running));
      expect(
        read.refusalOn(running),
        allOf(contains('weather'), contains('update flutter3d')),
      );
      expect(SimulationVersion.fromJson(newer), read);
      expect(SimulationVersion.fromJson(newer).hashCode, read.hashCode);
      expect(read.refusalOn(SimulationVersion.fromJson(newer)), isNull);
      // Two values of the newer key are two simulations too.
      final other = SimulationVersion.fromJson(<String, Object?>{
        ...newer,
        'weather': <String, Object?>{'model': 'storms', 'version': 4},
      });
      expect(other, isNot(read));
      expect(read.refusalOn(other), contains('weather'));
    });
  });
}
