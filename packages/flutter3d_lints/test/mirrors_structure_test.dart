/// The lints and `tool/structure.dart` ask the same questions.
///
///     dart test test/mirrors_structure_test.dart
///
/// The structure scan holds this repository's packages to rules 7 and 34 by
/// text, before `pub get`; this package holds a plugin author's code to the
/// same rules through the analyzer. Two lists of one rule drift the day one
/// of them is edited, so this reads the structure tool's source and compares.
/// Run from the package directory, which is where `dart test` runs.
library;

import 'dart:io';

import 'package:flutter3d_lints/flutter3d_lints.dart';
import 'package:test/test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('the transcendentals are the structure rule\'s', () {
    // Mutation: add `sinh` to `_machineArithmetic` in tool/structure/rules.dart
    // and this fails until `machineArithmetic` has it too.
    final rules = _read('../../tool/structure/rules.dart');
    final pattern = RegExp(
      r'_machineArithmetic = RegExp\(\s*r.\\bmath\\\.\(([a-z0-9|]+)\)',
    ).firstMatch(rules);
    expect(pattern, isNotNull, reason: 'rules.dart no longer has the regex');
    expect(pattern!.group(1)!.split('|').toSet(), machineArithmetic);
  });

  test('the clock and the dice are the structure detector\'s', () {
    // Mutation: add a fourth entry to `kStepMustNotReachFor` in
    // tool/structure/detectors.dart and this fails until a rule here reports
    // it; remove one and it fails too.
    final detectors = _read('../../tool/structure/detectors.dart');
    final start = detectors.indexOf('kStepMustNotReachFor =');
    expect(start, isNonNegative, reason: 'detectors.dart lost the table');
    final table = detectors.substring(start, detectors.indexOf('};', start));
    final patterns = <String>[
      for (final m in RegExp(r"RegExp\(r'([^']+)'\)").allMatches(table))
        m.group(1)!,
    ];
    expect(patterns, <String>[
      r'\bRandom\(\s*\)',
      r'\bDateTime\.now\(\)',
      r'\bStopwatch\(',
    ]);
  });

  test('the unprefixed import the structure rule refuses is a rule here', () {
    // Mutation: drop `step_prefixes_dart_math` from `SimulationRules.all` and
    // the one refusal the structure rule makes outright has no mirror.
    final rules = _read('../../tool/structure/rules.dart');
    expect(rules, contains('source.contains("import \'dart:math\';")'));
    expect(SimulationRules.all, contains(SimulationRules.prefixedMath));
  });
}
