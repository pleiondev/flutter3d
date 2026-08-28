/// Everything this game ships that somebody else made is named on a screen.
///
///     flutter test test/credits_test.dart
///
/// **This game was in breach, and there was nothing that could have said so.**
/// The car is CC BY 4.0, and `assets/models/LICENSES.md` spells out what that
/// means: *"Attribution is a condition of the licence, so it is written here,
/// and it must appear wherever the game does — a credits screen, a store page,
/// a README."* There was no credits screen, nothing in the application and
/// nothing on the page, so every run of it was a breach for as long as it ran.
///
/// The platformer needed this file for the same reason and got it first. The
/// check that matters reads **the directory**, not the list beside it: a list
/// that only agrees with itself is the one that goes stale.
library;

import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart'; // Credit, from flutter3d_ui
import 'package:flutter3d_demo_racing/src/credits.dart';
import 'package:flutter3d_ui/testing.dart'; // creditGaps — test-only, not in the barrel
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every model the game ships is accounted for', () {
    // From the directory, not from a list written beside the other list. The
    // failure this catches is an asset added to the game and to nothing else.
    //
    // The comparison is `flutter3d_ui`'s: it was these twelve lines in three
    // applications, down to the wording of the failures.
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

  test('and what is owed is owed, which is the point here', () {
    // **Not empty, unlike the other two games.** Both of those ended up with
    // everything CC0 or generated; this one ships a CC BY model, so the screen
    // is a condition of shipping rather than a courtesy.
    expect(
      Credits.owed,
      isNotEmpty,
      reason: 'nothing here needs attribution, so this file is a formality',
    );
    for (final credit in Credits.owed) {
      expect(credit.author, isNotNull);
      expect(
        credit.licenceUrl,
        isNotNull,
        reason: '${credit.file} names ${credit.licence} and no URL',
      );
      expect(
        credit.line,
        contains(credit.author!),
        reason: 'the line a player reads does not name the author',
      );
    }
  });

  test('and the car says it was changed, because it was', () {
    // CC BY asks that modifications be stated. `tool/prepare_models.py` resizes
    // its maps, drops two extensions and turns its root half a turn, and a
    // credit that said otherwise would describe a file this game does not ship.
    final car = Credits.models.firstWhere((Credit c) => c.file.contains('car'));

    expect(car.modified, isTrue);
    expect(car.line, contains('modified'));
  });

  test('and the licence table on disk covers the same files', () {
    // Two records of the same fact, which is one too many — so they are checked
    // against each other. `LICENSES.md` is the long version a person reads; the
    // list above is the half a player sees.
    final table = File('assets/models/LICENSES.md').readAsStringSync();

    for (final credit in Credits.models) {
      expect(
        table,
        contains(credit.file.split('/').last),
        reason: 'LICENSES.md does not mention ${credit.file}',
      );
    }
  });
}
