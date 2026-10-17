/// Everything this game ships that somebody else made is accounted for.
///
///     flutter test test/credits_test.dart
///
/// The check that matters reads **the directory**, not the list beside it:
/// the failure it catches is a model added to `assets/models` and to nothing
/// else. The three craft here are CC0, so nothing is owed, and they ship
/// unchanged, since the game recolours them at runtime.
library;

import 'dart:io';

import 'package:flutter3d_demo_arcade/src/credits.dart';
import 'package:flutter3d_demo_content/repo_checks.dart'; // creditGaps
import 'package:flutter3d_game_ui/screens.dart' show LicenseRecord;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every model the game ships is accounted for', () {
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

  test('and nothing it ships is untraceable or owed', () {
    expect(credits.untraced, isEmpty);
    expect(credits.owed, isEmpty, reason: 'a CC0 model owes nothing');
  });

  test('and every entry names a licence somebody can read', () {
    for (final credit in credits.models) {
      expect(credit.license, isNotNull, reason: '${credit.file} has none');
      expect(credit.licenseUrl, isNotNull, reason: '${credit.file} no URL');
      expect(credit.line, contains(credit.work));
    }
  });

  test('and the licence table on disk says the same', () {
    // Read, not searched: each file's section names its author and licence,
    // and the list above has to state the same ones.
    final record = LicenseRecord.parse(
      File('assets/models/LICENSES.md').readAsStringSync(),
    );
    expect(credits.disagreementsWith(record), isEmpty);
  });
}
