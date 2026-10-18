/// `scanSimulationCode`: what fires and what stays quiet, on units parsed
/// without a resolver — the fallback every rule has to get right before the
/// resolver makes it stronger.
///
///     dart test test/simulation_scan_test.dart
///
/// The cases mirror `proveDetectorsWork` in `tool/structure/detectors.dart`,
/// which asks the same questions of this repository by text. Each test names
/// the mutation that would defeat it.
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter3d_lints/flutter3d_lints.dart';
import 'package:test/test.dart';

/// The rules [source] breaks, one entry per finding, in source order.
List<String> _rules(String source) => <String>[
  for (final finding in scanSimulationCode(
    parseString(content: source, throwIfDiagnostics: false).unit,
  ))
    finding.rule,
];

void main() {
  group('the clock', () {
    test('DateTime.now() and a Stopwatch fire', () {
      // Mutation: drop the `now` branch of the unresolved invocation and the
      // first call is never found.
      expect(_rules('void f() { final t = DateTime.now(); }'), <String>[
        SimulationRules.clock,
      ]);
      expect(_rules('void f() { final w = Stopwatch()..start(); }'), <String>[
        SimulationRules.clock,
      ]);
      expect(_rules('void f() { final w = new Stopwatch(); }'), <String>[
        SimulationRules.clock,
      ]);
    });

    test('a comment and a string that name the clock stay quiet', () {
      // Mutation: scan the source text instead of the tree and both fire —
      // prose explaining the rule must not break it, and a message quoting
      // the call is a sentence about it rather than a call.
      expect(
        _rules('// DateTime.now() would be wrong here.\nvoid f() {}'),
        isEmpty,
      );
      expect(_rules("const s = 'never call DateTime.now()';"), isEmpty);
    });

    test('a DateTime that is not now stays quiet', () {
      // Mutation: match every DateTime constructor and a date written down
      // in a level fires.
      expect(_rules('void f() { final d = DateTime(2026, 10, 8); }'), isEmpty);
    });
  });

  group('dice', () {
    test('an unseeded Random and a secure one fire', () {
      // Mutation: drop the `noArguments` test and the seeded case below
      // fires too; drop the `secure` branch and the second is missed.
      expect(_rules('void f() { final r = Random(); }'), <String>[
        SimulationRules.seededRandom,
      ]);
      expect(_rules('void f() { final r = math.Random(); }'), <String>[
        SimulationRules.seededRandom,
      ]);
      expect(_rules('void f() { final r = Random.secure(); }'), <String>[
        SimulationRules.seededRandom,
      ]);
    });

    test('a seeded Random and GameRandom stay quiet', () {
      // Mutation: flag every `Random` and the seeded generator — the fix —
      // is reported as the fault.
      expect(_rules('void f() { final r = Random(7); }'), isEmpty);
      expect(_rules('void f() { final r = GameRandom(1); }'), isEmpty);
    });
  });

  group('the machine\'s arithmetic', () {
    test('a transcendental under a dart:math prefix fires, whatever the '
        'prefix', () {
      // Mutation: read only the literal prefix `math` and the second unit,
      // which imports it as `m`, passes.
      expect(
        _rules("import 'dart:math' as math;\nfinal x = math.sin(1.0);"),
        <String>[SimulationRules.portableMath],
      );
      expect(
        _rules("import 'dart:math' as m;\nfinal x = m.atan2(1.0, 2.0);"),
        <String>[SimulationRules.portableMath],
      );
      expect(_rules('final x = math.pow(2.0, 0.5);'), <String>[
        SimulationRules.portableMath,
      ]);
    });

    test('a bare call under an unprefixed import fires twice: the call and '
        'the import', () {
      // Mutation: forget `_bareMath` and the call hides behind the import,
      // which is exactly why the structure rule refuses the import.
      expect(_rules("import 'dart:math';\nfinal x = exp(1.0);"), <String>[
        SimulationRules.prefixedMath,
        SimulationRules.portableMath,
      ]);
    });

    test('sqrt and Portable stay quiet', () {
      // Mutation: put `sqrt` in `machineArithmetic` and the one function
      // IEEE 754 pins is reported; match on the name alone and Portable's
      // own `sin`, the fix, is reported as the fault.
      expect(
        _rules("import 'dart:math' as math;\nfinal x = math.sqrt(2.0);"),
        isEmpty,
      );
      expect(_rules('final x = Portable.sin(1.0);'), isEmpty);
    });

    test('an import with a show list stays quiet', () {
      // Mutation: drop the combinator test and `show max`, which lets no
      // transcendental in by name, is refused like the bare import.
      expect(
        _rules("import 'dart:math' show max;\nfinal x = max(1, 2);"),
        isEmpty,
      );
    });
  });

  test('every finding names one of the four rules', () {
    // Mutation: report a rule under a name `SimulationRules.all` does not
    // list and the plugin registers nothing that can show it.
    final rules = _rules(
      "import 'dart:math';\n"
      'void f() { DateTime.now(); Random(); sin(1.0); }',
    );
    expect(rules, hasLength(4));
    expect(SimulationRules.all.toSet().containsAll(rules), isTrue);
  });
}
