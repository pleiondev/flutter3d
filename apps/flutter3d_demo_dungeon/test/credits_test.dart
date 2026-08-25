/// Everything this game ships that somebody else made is named on a screen.
///
///     flutter test test/credits_test.dart
///
/// **The platformer needed this file because it was in breach**: two of its
/// models are CC BY, whose text asks that attribution travel with the work, and
/// the game named nobody anywhere.
///
/// This game is not in breach — everything in it is CC0 or generated here — and
/// the file exists anyway, for the same reason the licence table does. The next
/// model dropped into `assets/models` is one somebody found somewhere, and the
/// check that matters reads **the directory**, not the list beside it. A list
/// that only agrees with itself is the one that goes stale.
library;

import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart'; // Credit, from flutter3d_ui
import 'package:flutter3d_demo_dungeon/src/credits.dart';
import 'package:flutter3d_ui/testing.dart'; // creditGaps — test-only, not in the barrel
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every model the game ships is accounted for', () {
    // **From the directory, not from a list written beside the other list.**
    // The failure this catches is an asset added to the game and to nothing
    // else, which is exactly how an untraced key once arrived in two games.
    //
    // The comparison is `flutter3d_ui`'s: it was these twelve lines in three
    // applications, down to the wording of the failures.
    final gaps = creditGaps(Credits.models, shippedFrom: 'assets/models');

    expect(gaps.shipped, isNotEmpty, reason: 'no models found to check');
    expect(gaps.unshipped, isEmpty,
        reason: 'credited something the game does not ship');
    expect(gaps.uncredited, isEmpty,
        reason: 'shipped a model nobody is credited for');
  });

  test('and nothing it ships is untraceable', () {
    expect(Credits.untraced, isEmpty,
        reason: 'this game cannot be released while anything is in this list');
  });

  test('and every entry names a licence somebody can read', () {
    // A licence with no URL is a licence a player is told the name of and
    // cannot look up, which is most of the way to not saying it.
    for (final credit in Credits.models) {
      expect(credit.licence, isNotNull, reason: '${credit.file} has no licence');
      expect(credit.licenceUrl, isNotNull,
          reason: '${credit.file} names ${credit.licence} and no URL');
      expect(credit.line, contains(credit.work));
    }
  });

  test('and the monsters say they were changed, because they were', () {
    // CC0 asks for nothing, so this is not a duty — it is the record. All three
    // are rescaled and have their clip names rewritten by
    // `tool/prepare_monsters.py`, and a credit that said otherwise would be
    // describing a file this game does not ship.
    final monsters = Credits.models
        .where((Credit c) => c.file.contains('monster_'))
        .toList();

    expect(monsters, hasLength(3));
    for (final credit in monsters) {
      expect(credit.modified, isTrue, reason: '${credit.file} was modified');
    }
  });

  test('and the licence table on disk covers the same files', () {
    // Two records of the same fact, which is one too many — so they are checked
    // against each other. `LICENSES.md` is the long version a person reads; the
    // list above is the half a player sees.
    final table = File('assets/models/LICENSES.md').readAsStringSync();

    for (final credit in Credits.models) {
      final name = credit.file.split('/').last;
      expect(table, contains(name),
          reason: 'LICENSES.md does not mention $name');
    }
  });
}
