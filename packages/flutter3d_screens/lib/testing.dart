/// Comparing what a game credits against what it actually ships.
///
///     import 'package:flutter3d_screens/testing.dart';
///
///     final gaps = creditGaps(Credits.models, shippedFrom: 'assets/models');
///     expect(gaps.uncredited, isEmpty);
///     expect(gaps.unshipped, isEmpty);
///
/// **The check that matters reads the directory, not the list beside it.** A
/// list of authors compared against another list of authors only ever agrees
/// with itself; what goes wrong is a model dropped into `assets/models` and into
/// nothing else, which is exactly how an untraced key once arrived in two games
/// at once. The platformer needed the check because it was in breach: two of its
/// models are CC BY, whose text asks that attribution travel with the work, and
/// the game named nobody anywhere.
///
/// ## Why it is here
///
/// [Credit] and the screen that shows it are already this package's; only the
/// list is a game's own. The comparison was not — it was the same twelve lines
/// in three applications' `credits_test.dart`, down to the wording of the
/// failure messages.
///
/// It returns the two sets rather than asserting on them, so that this package
/// does not take `flutter_test` as a real dependency to save three callers two
/// lines each.
library;

import 'dart:io';

import 'src/credits.dart';

/// What is shipped and uncredited, and what is credited and not shipped.
///
/// [shippedFrom] is a directory of assets, read as it is on disk. [extension]
/// is what counts as a model there; everything else in the folder — a
/// `LICENSES.md`, a `.blend` nobody ships — is ignored.
///
/// Paths are compared as `<folder>/<name>`, which is the form a [Credit.file]
/// takes: `models/penguin.glb`.
({Set<String> uncredited, Set<String> unshipped, Set<String> shipped})
creditGaps(
  List<Credit> credited, {
  required String shippedFrom,
  String extension = '.glb',
}) {
  final folder = shippedFrom.split('/').last;
  final directory = Directory(shippedFrom);
  if (!directory.existsSync()) {
    // Loud, because an empty set would make "this game ships no models" and
    // "the test ran from the wrong directory" the same answer.
    throw StateError(
      '$shippedFrom is not there — run from the application root, where its '
      'assets are',
    );
  }

  final shipped = directory
      .listSync()
      .whereType<File>()
      .map((File f) => '$folder/${f.uri.pathSegments.last}')
      .where((String name) => name.endsWith(extension))
      .toSet();

  final named = credited.map((Credit c) => c.file).toSet();
  return (
    uncredited: shipped.difference(named),
    unshipped: named.difference(shipped),
    shipped: shipped,
  );
}
