/// Everything this game ships that somebody else made is accounted for.
///
///     flutter test test/credits_test.dart
///
/// **Both models here are CC0**, so this game is not in breach the way the
/// platformer and the racing game once were — but the file exists anyway,
/// for the reason the dungeon's own copy gives: the next model dropped into
/// `assets/models` is one somebody found somewhere, and the check that
/// matters reads **the directory**, not the list beside it. A list that only
/// agrees with itself is the one that goes stale.
library;

import 'dart:io';

import 'package:flutter3d_demo_strategy/src/credits.dart';
import 'package:flutter3d_game/testing.dart'; // creditGaps
// creditGaps — test-only, not in the barrel
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every model the game ships is accounted for', () {
    // From the directory, not from a list written beside the other list. The
    // failure this catches is an asset added to the game and to nothing
    // else.
    final gaps = creditGaps(Credits.models, shippedFrom: 'assets/models');

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
      Credits.untraced,
      isEmpty,
      reason: 'this game cannot be released while anything is in this list',
    );
  });

  test('and nothing here owes attribution, because CC0 owes nothing', () {
    expect(
      Credits.owed,
      isEmpty,
      reason:
          'a CC0 model has nothing to owe; if this is not empty, check '
          'the licence string rather than the model',
    );
  });

  test('and every entry names a licence somebody can read', () {
    for (final credit in Credits.models) {
      expect(
        credit.licence,
        isNotNull,
        reason: '${credit.file} has no licence',
      );
      expect(
        credit.licenceUrl,
        isNotNull,
        reason: '${credit.file} names ${credit.licence} and no URL',
      );
      expect(credit.line, contains(credit.work));
    }
  });

  test('and both models say they were changed, because they were', () {
    // CC0 asks for nothing, so this is not a duty — it is the record.
    // `tool/prepare_models.py` joins and rescales the worker and embeds the
    // hall's texture; a credit that said otherwise would describe a file
    // this game does not ship.
    for (final credit in Credits.models) {
      expect(credit.modified, isTrue, reason: '${credit.file} was modified');
    }
  });

  test('and the licence table on disk covers the same files', () {
    final table = File('assets/models/LICENSES.md').readAsStringSync();

    for (final credit in Credits.models) {
      final name = credit.file.split('/').last;
      expect(
        table,
        contains(name),
        reason: 'LICENSES.md does not mention $name',
      );
    }
  });
}
