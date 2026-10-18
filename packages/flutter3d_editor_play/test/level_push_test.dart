/// `HR3`'s editor half: what a saved level is sent as, and how the game's
/// answer reads in the status strip.
///
///     dart test test/level_push_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

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

  // Mutation: build the patch from the text rather than from the level the
  // game would parse, or send it when it is longer than the document, and
  // one of these fails.
  test('a save after a save goes as a patch, when that is shorter', () {
    final base = jsonEncode(<String, Object?>{
      'version': 1,
      'name': 'yard',
      'brushes': <Object?>[
        for (var i = 0; i < 20; i++)
          <String, Object?>{
            'at': <double>[i * 2.0, 0, 0],
            'size': <double>[1, 1, 1],
          },
      ],
    });
    final moved = base.replaceFirst('[6.0,0.0,0.0]', '[6.5,0.0,0.0]');
    expect(moved, isNot(base));

    final arguments = levelPatchArguments(base, moved)!;
    final patch = LevelPatch.fromJson(
      jsonDecode(arguments['patch']!) as Map<String, Object?>,
    );
    expect(patch.rows.single.at, 3);
    expect(
      (patch.applyTo(Level.fromJson(jsonDecode(base) as Map<String, Object?>))
              as LevelPatched)
          .level
          .digestHex,
      levelApplyArguments(moved)['hash'],
    );

    // A one-line level is shorter whole than as a patch.
    expect(
      levelPatchArguments(_document, _document.replaceFirst('0.02', '0.03')),
      isNull,
    );
    expect(levelPatchArguments('not json', _document), isNull);
  });

  test('a level sent whole after a stale patch says why', () {
    expect(
      describeLevelApplied(<String, Object?>{
        'diff': <String, Object?>{'fog': true},
        'fellBack': 'the patch was made against level 1 and the game has 2',
      }),
      'the game took the new look '
      '(sent whole: the patch was made against level 1 and the game has 2)',
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
