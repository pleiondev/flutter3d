/// Everything this game ships that somebody else made is accounted for.
///
///     flutter test test/credits_test.dart
///
/// **Every model here is CC0**, so this game is not in breach the way the
/// platformer and the racing game once were — but the file exists anyway,
/// for the reason the dungeon's own copy gives: the next model dropped into
/// `assets/models` is one somebody found somewhere, and the check that
/// matters reads **the directory**, not the list beside it. A list that only
/// agrees with itself is the one that goes stale.
library;

import 'dart:io';

import 'package:flutter3d_demo_content/repo_checks.dart'; // creditGaps
import 'package:flutter3d_demo_strategy/src/credits.dart';
import 'package:flutter3d_game_ui/screens.dart' show LicenseRecord;
// creditGaps — test-only, not in the barrel
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every model the game ships is accounted for', () {
    // From the directory, not from a list written beside the other list. The
    // failure this catches is an asset added to the game and to nothing
    // else.
    final gaps = creditGaps(
      credits.models.map((c) => c.file),
      shippedFrom: 'assets/models',
    );

    expect(gaps.shipped, isNotEmpty, reason: 'no models found to check');
    expect(
      gaps.unshipped,
      isEmpty,
      reason: 'credited something the game does not ship',
    );
    expect(
      gaps.uncredited,
      isEmpty,
      reason: 'shipped a model nobody is credited for',
    );
  });

  test('and nothing it ships is untraceable', () {
    expect(
      credits.untraced,
      isEmpty,
      reason: 'this game cannot be released while anything is in this list',
    );
  });

  test('and nothing here owes attribution, because CC0 owes nothing', () {
    expect(
      credits.owed,
      isEmpty,
      reason:
          'a CC0 model has nothing to owe; if this is not empty, check '
          'the licence string rather than the model',
    );
  });

  test('and every entry names a licence somebody can read', () {
    for (final credit in credits.models) {
      expect(
        credit.license,
        isNotNull,
        reason: '${credit.file} has no licence',
      );
      expect(
        credit.licenseUrl,
        isNotNull,
        reason: '${credit.file} names ${credit.license} and no URL',
      );
      expect(credit.line, contains(credit.work));
    }
  });

  test('and every model says it was changed, because it was', () {
    // CC0 asks for nothing, so this is not a duty — it is the record.
    // `tool/prepare_models.py` takes the texture reference out of every one
    // and the clips out of the characters; a credit that said otherwise would
    // describe a file this game does not ship.
    for (final credit in credits.models) {
      expect(credit.modified, isTrue, reason: '${credit.file} was modified');
    }
  });

  test('and the licence table on disk says the same', () {
    // Two records of the same fact, which is one too many — so they are checked
    // against each other. `LICENSES.md` is the long version a person reads; the
    // list above is the half a player sees. Read rather than searched: where a
    // section names an author and a licence, the list has to name the same.
    final record = LicenseRecord.parse(
      File('assets/models/LICENSES.md').readAsStringSync(),
    );
    expect(credits.disagreementsWith(record), isEmpty);
  });
}
