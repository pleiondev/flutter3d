/// `HR3`'s editor half: what a saved level is sent as, and how the game's
/// answer reads in the status strip.
///
///     flutter test test/level_push_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_editor/src/play/level_push.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const String _document = '{"version": 1, "name": "yard", "fogDensity": 0.02}';

void main() {
  test('the hash is the level\'s digest, as the game computes it', () {
    final arguments = levelApplyArguments(_document);

    expect(arguments['document'], _document);
    expect(
      arguments['hash'],
      Level.fromJson(jsonDecode(_document) as Map<String, Object?>).digestHex,
    );
    // Whitespace is not a different level.
    expect(
      levelApplyArguments(
        '{\n  "version": 1,\n  "name": "yard",\n  "fogDensity": 0.02\n}',
      )['hash'],
      arguments['hash'],
    );
  });

  test('the game\'s answer, in a line', () {
    Map<String, Object?> answer({
      List<String> simulation = const <String>[],
      bool fog = false,
      int? swappedAt,
      bool rebuiltInPlace = false,
    }) => <String, Object?>{
      'diff': <String, Object?>{
        'lights': <int>[],
        'lightCountChanged': false,
        'materials': <String>[],
        'fog': fog,
        'music': false,
        'simulation': simulation,
      },
      'swappedAt': ?swappedAt,
      'rebuiltInPlace': rebuiltInPlace,
    };

    expect(
      describeLevelApplied(
        answer(simulation: <String>['brushes'], swappedAt: 120),
      ),
      'the game replayed from step 120 with the new brushes',
    );
    expect(
      describeLevelApplied(
        answer(simulation: <String>['entities'], rebuiltInPlace: true),
      ),
      contains('in place'),
    );
    expect(
      describeLevelApplied(answer(fog: true)),
      'the game took the new look',
    );
    expect(describeLevelApplied(answer()), 'the game already had this level');
  });
}
