/// Checks this repository's demo games run on their own sources and assets:
/// the ones no type can make.
///
///     import 'package:flutter3d_demo_content/repo_checks.dart';
///
///     final it = soundTableIn('lib/src/sounds.dart');
///     expect(it.declared.difference(it.inTheBank), isEmpty);
///
/// **Repository hygiene, not engine API.** These lived in the published
/// packages' `testing.dart` libraries until 1.0 — `soundTableIn` in
/// `flutter3d_audio` — and so were held to semver for the sake of three demo
/// applications' tests. They read files from disk with `dart:io`, run from an
/// application's root, and return what they found rather than asserting, so
/// nothing here needs `flutter_test`.
library;

import 'dart:io';

/// What [path] declares, and what its bank actually holds.
///
/// [path] is a Dart source file with `static const SoundDef` declarations and a
/// `static final SoundBank all = SoundBank(<SoundDef>[…])` beside them, which is
/// the shape all three games use.
///
/// **A `SoundBank` removes the second list and cannot remove this.** A
/// `static const SoundDef` declared beside the bank and left out of it is
/// invisible to every type in Dart, because there is no reflection to ask a
/// class what it holds. The source is the only place that knows. The
/// platformer shipped for months with six of its fourteen sounds declared and
/// not banked, and the game was half mute.
({Set<String> declared, Set<String> inTheBank}) soundTableIn(String path) {
  final source = File(path).readAsStringSync();

  final declared = RegExp(
    r'static const SoundDef ([A-Za-z]+)',
  ).allMatches(source).map((RegExpMatch m) => m.group(1)!).toSet();

  final literal = RegExp(
    r'static final SoundBank all = SoundBank\(<SoundDef>\[(.*?)\]\);',
    dotAll: true,
  ).firstMatch(source);
  if (literal == null) {
    // Loud rather than empty. An empty set makes "the bank holds nothing" and
    // "the pattern stopped matching" the same answer, and only one of them is
    // the game's fault.
    throw StateError(
      'no `static final SoundBank all = SoundBank(<SoundDef>[…]);` in $path. '
      'If the bank has been written a different way, this scan has to learn '
      'the new shape or it will report every sound as missing.',
    );
  }

  final inTheBank = RegExp(
    r'([A-Za-z]+),',
  ).allMatches(literal.group(1)!).map((RegExpMatch m) => m.group(1)!).toSet();

  return (declared: declared, inTheBank: inTheBank);
}

/// The names of the files directly in [directory], or null when it is not
/// there.
List<String>? fileNamesIn(String directory) {
  final dir = Directory(directory);
  if (!dir.existsSync()) return null;
  return <String>[
    for (final entry in dir.listSync().whereType<File>())
      entry.uri.pathSegments.last,
  ];
}

/// What is shipped and uncredited, and what is credited and not shipped.
///
///     final gaps = creditGaps(
///       Credits.models.map((Credit c) => c.file),
///       shippedFrom: 'assets/models',
///     );
///     expect(gaps.uncredited, isEmpty);
///     expect(gaps.unshipped, isEmpty);
///
/// **The check that matters reads the directory, not the list beside it.** A
/// list of authors compared against another list of authors only ever agrees
/// with itself; what goes wrong is a model dropped into `assets/models` and
/// into nothing else, which is exactly how an untraced key once arrived in two
/// games at once.
///
/// [creditedFiles] are the credits' `file`s, in the form `<folder>/<name>`:
/// `models/penguin.glb`. [shippedFrom] is a directory of assets, read as it is
/// on disk. [extension] is what counts as a model there; everything else in
/// the folder — a `LICENSES.md`, a `.blend` nobody ships — is ignored.
///
/// It lived in `flutter3d_game`'s `testing.dart` until 1.0, a published
/// library held to semver for five applications' tests; it takes file names
/// rather than credits so this package needs no game layer.
({Set<String> uncredited, Set<String> unshipped, Set<String> shipped})
creditGaps(
  Iterable<String> creditedFiles, {
  required String shippedFrom,
  String extension = '.glb',
}) {
  final folder = shippedFrom.split('/').last;
  final names = fileNamesIn(shippedFrom);
  if (names == null) {
    // Loud, because an empty set would make "this game ships no models" and
    // "the test ran from the wrong directory" the same answer.
    throw StateError(
      '$shippedFrom is not there — run from the application root, where its '
      'assets are',
    );
  }

  final shipped = names
      .map((String name) => '$folder/$name')
      .where((String name) => name.endsWith(extension))
      .toSet();

  final named = creditedFiles.toSet();
  return (
    uncredited: shipped.difference(named),
    unshipped: named.difference(shipped),
    shipped: shipped,
  );
}
