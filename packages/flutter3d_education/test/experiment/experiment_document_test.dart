import 'dart:io';

import 'package:flutter3d_education/experiment.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show ProbeBody;
import 'package:test/test.dart';

String _fixture(String name) =>
    File('test/fixtures/v1/$name.f3d.experiment').readAsStringSync();

Map<String, Object?> _minimal({
  Map<String, Object?> step = const <String, Object?>{'name': 'one'},
}) => <String, Object?>{
  'format': 'f3d.experiment',
  'version': 1,
  'name': 'x',
  'level': 'x.level.json',
  'parameters': <Object?>[
    <String, Object?>{
      'id': 'length',
      'value': <String, Object?>{'value': 1.0, 'unit': 'm'},
    },
  ],
  'probes': <Object?>[
    <String, Object?>{
      'id': 'angle',
      'quantity': 'f3d.angle',
      'unit': 'rad',
      'on': 'bob',
    },
  ],
  'scenario': <String, Object?>{
    'steps': <Object?>[step],
  },
};

void main() {
  group('the pendulum fixture', () {
    late ExperimentDocument pendulum;

    setUp(() => pendulum = ExperimentDocument.parse(_fixture('pendulum')));

    test('reads as the pendulum written in version 1', () {
      expect(pendulum.name, 'pendulum');
      expect(pendulum.level, 'pendulum.level.json');
      expect(pendulum.profile, 'deterministic');
      expect(pendulum.substances.map((s) => s.id), <String>[
        'f3d.steel',
        'f3d.air',
      ]);
      expect(
        pendulum.parameter('length')!.value,
        const Quantity(1, Unit.meter),
      );
      expect(pendulum.parameter('length')!.max!.value, 2.0);
      expect(pendulum.probes.map((p) => p.id), <String>['angle', 'period']);
      expect(pendulum.probe('period')!.on, 'bob');
      expect(pendulum.probe('period')!.probe.unit, Unit.second);
      expect(pendulum.probe('angle')!.probe.region, isA<ProbeBody>());
      expect(pendulum.steps.map((s) => s.name), <String>['release', 'shorten']);
      expect(pendulum.unknowns.single.parameter, 'length');
      expect(pendulum.unknowns.single.prior, <String, Object?>{
        'kind': 'uniform',
      });
      expect(pendulum.observations, isEmpty);
    });

    test('expects the series period at 0.1 rad, and half of it at a '
        'quarter of the length', () {
      final release = pendulum.step('release')!.expect.single;
      final shorten = pendulum.step('shorten')!.expect.single;
      expect(release.agrees(const Quantity(2.0077, Unit.second)), isTrue);
      expect(release.agrees(const Quantity(2.0064, Unit.second)), isFalse);
      expect(
        shorten.value.value * 2,
        closeTo(release.value.value, 1e-6),
        reason: 'T grows as the square root of the length',
      );
      expect(pendulum.step('shorten')!.set['length']!.value, 0.25);
      expect(pendulum.step('shorten')!.run, const Quantity(10, Unit.second));
    });

    test('asks one question, with two attempts', () {
      final check = pendulum.step('shorten')!.check!;
      expect(check.attempts, 2);
      expect(check.accepts('  Halved '), isTrue);
      expect(check.accepts('doubled'), isFalse);
      expect(pendulum.step('release')!.check, isNull);
    });

    test('names only substances the built-in catalog holds', () {
      expect(
        pendulum.substancesMissingFrom(MaterialCatalog.builtIn()),
        isEmpty,
      );
      expect(
        pendulum
            .substancesMissingFrom(MaterialCatalog())
            .map((substance) => substance.id),
        <String>['f3d.steel', 'f3d.air'],
      );
    });

    test('writes back the same bytes', () {
      expect('${pendulum.encode()}\n', _fixture('pendulum'));
    });
  });

  test('the chemistry bench reads and writes back the same bytes', () {
    final bench = ExperimentDocument.parse(_fixture('bench'));
    expect(bench.substances.map((s) => s.id), <String>[
      'f3d.water',
      'f3d.borosilicateGlass',
    ]);
    expect(bench.substancesMissingFrom(MaterialCatalog.builtIn()), isEmpty);
    expect(bench.step('look')!.run, isNull);
    final temperature = bench.step('pour')!.expect[1];
    expect(
      temperature.agrees(const Quantity(293.4, Unit.kelvin)),
      isTrue,
      reason: '20 °C ± 0.5 K holds 293.4 K',
    );
    expect(temperature.agrees(const Quantity(294, Unit.kelvin)), isFalse);
    expect('${bench.encode()}\n', _fixture('bench'));
  });

  group('refuses', () {
    test('a step setting a parameter the document does not declare', () {
      expect(
        () => ExperimentDocument.fromJson(
          _minimal(
            step: <String, Object?>{
              'name': 'one',
              'set': <String, Object?>{'lenght': '1 m'},
            },
          ),
        ),
        throwsA(
          isA<DocumentFormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"lenght"'), contains('step "one"')),
          ),
        ),
      );
    });

    test('a reading of a probe the document does not have', () {
      expect(
        () => ExperimentDocument.fromJson(
          _minimal(
            step: <String, Object?>{
              'name': 'one',
              'expect': <Object?>[
                <String, Object?>{
                  'probe': 'speed',
                  'value': '1 m/s',
                  'tolerance': '0.1 m/s',
                },
              ],
            },
          ),
        ),
        throwsA(
          isA<DocumentFormatException>().having(
            (e) => e.message,
            'message',
            contains('"speed"'),
          ),
        ),
      );
    });

    test('a tolerance in another dimension than the value', () {
      expect(
        () => ExperimentDocument.fromJson(
          _minimal(
            step: <String, Object?>{
              'name': 'one',
              'expect': <Object?>[
                <String, Object?>{
                  'probe': 'angle',
                  'value': '0.1 rad',
                  'tolerance': '1 s',
                },
              ],
            },
          ),
        ),
        throwsA(isA<DocumentFormatException>()),
      );
    });

    test('two steps of one name, and a run that is not a time', () {
      final twice = _minimal()
        ..['scenario'] = <String, Object?>{
          'steps': <Object?>[
            <String, Object?>{'name': 'one'},
            <String, Object?>{'name': 'one'},
          ],
        };
      expect(
        () => ExperimentDocument.fromJson(twice),
        throwsA(isA<DocumentFormatException>()),
      );
      expect(
        () => ExperimentDocument.fromJson(
          _minimal(step: <String, Object?>{'name': 'one', 'run': '3 m'}),
        ),
        throwsA(isA<DocumentFormatException>()),
      );
    });

    test('a version from the future, and another format', () {
      expect(
        () => ExperimentDocument.fromJson(_minimal()..['version'] = 2),
        throwsA(isA<DocumentFormatException>()),
      );
      expect(
        () => ExperimentDocument.fromJson(
          _minimal()..['format'] = 'f3d.pipeline',
        ),
        throwsA(isA<DocumentFormatException>()),
      );
    });
  });

  test('reads quantities written by hand as text', () {
    final document = ExperimentDocument.fromJson(
      _minimal(
        step: <String, Object?>{
          'name': 'one',
          'set': <String, Object?>{'length': '50 cm'},
          'run': '2 s',
        },
      ),
    );
    expect(document.step('one')!.set['length']!.valueIn(Unit.meter), 0.5);
  });

  test('keeps a key it does not know through a read and a write', () {
    final document = ExperimentDocument.fromJson(
      _minimal()..['later'] = <String, Object?>{'kept': true},
    );
    expect(document.toJson()['later'], <String, Object?>{'kept': true});
  });
}
