/// Everything this game ships that somebody else made is named on a screen.
///
///     flutter test test/credits_test.dart
///
/// **This game was in breach, and there was nothing that could have said so.**
/// The car is CC BY 4.0, and `assets_src/models/LICENSES.md` spells out what that
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

import 'package:flutter3d_demo_content/repo_checks.dart'; // creditGaps
import 'package:flutter3d_demo_racing/src/credits.dart';
// creditGaps — test-only, not in the barrel
import 'package:flutter3d_game_ui/flutter3d_game_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every model the game ships is accounted for', () {
    // From the directory, not from a list written beside the other list. The
    // failure this catches is an asset added to the game and to nothing else.
    //
    // The comparison is `flutter3d_game`'s: it was these twelve lines in three
    // applications, down to the wording of the failures.
    final gaps = creditGaps(
      credits.models.map((c) => c.file),
      shippedFrom: 'assets_src/models',
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

  test('and what is owed is nothing, now that the car is CC0', () {
    // The car was CC BY until 0.9.0, and the credits screen was a condition
    // of shipping it. Everything here is CC0 now; a model that comes in
    // under a licence that asks for its author makes this fail, and the
    // screens below have to name them again.
    expect(
      credits.owed,
      isEmpty,
      reason:
          'a model asks to be credited: the title card and the ending '
          'must name its author',
    );
    for (final credit in credits.owed) {
      expect(credit.author, isNotNull);
      expect(
        credit.licenseUrl,
        isNotNull,
        reason: '${credit.file} names ${credit.license} and no URL',
      );
      expect(
        credit.line,
        contains(credit.author!),
        reason: 'the line a player reads does not name the author',
      );
    }
  });

  test('and the car says it was changed, because it was', () {
    // CC0 asks for nothing, but `tool/prepare_models.py` embeds its atlas,
    // gives its paint a material of its own and scales it to the wheel base,
    // and a credit that said otherwise would describe a file this game does
    // not ship.
    final car = credits.models.firstWhere((Credit c) => c.file.contains('car'));

    expect(car.modified, isTrue);
    expect(car.line, contains('modified'));
  });

  test('and the licence table on disk says the same', () {
    // Two records of the same fact, which is one too many — so they are checked
    // against each other. `LICENSES.md` is the long version a person reads; the
    // list above is the half a player sees. Read rather than searched: where a
    // section names an author and a licence, the list has to name the same.
    final record = LicenseRecord.parse(
      File('assets_src/models/LICENSES.md').readAsStringSync(),
    );
    expect(credits.disagreementsWith(record), isEmpty);
  });
}
