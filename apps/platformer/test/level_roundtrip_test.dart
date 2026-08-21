/// Every level document in the repository, read and written back.
///
///     flutter test test/level_roundtrip_test.dart
///
/// **There is no writer today.** `Level.toJson()` is called nowhere outside
/// tests, and the test that looks like it proves a round trip
/// (`packages/flutter3d_game_shooter/test/level_test.dart`) starts from a `Level`
/// built in Dart: it proves the writer is a fixed point of itself and says
/// nothing about a document on disk.
///
/// That distinction stops being academic the moment anything writes a level —
/// an editor, a migration, a tool. So this reads the real files and asks the
/// only question that matters: **does the document survive?**
///
/// ## Why this file lives in an application and walks its siblings
///
/// The documents live under `apps/*/assets/`, and `flutter3d_game` must not
/// reach into `apps/` — the dependency runs the other way. There is no
/// repository-level `test/` directory either: `tool/ci.sh` walks `packages/*/`
/// and `apps/*/` and nothing else. So a repository-wide invariant has to be
/// hosted by *some* app, and this one is chosen because it owns two of the five
/// documents and already reads them from disk.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// A level document, and where it was found.
final class _Document {
  _Document(this.path, this.source, {this.nestedUnder});

  final String path;

  /// The decoded map that `Level.fromJson` is given.
  final Map<String, Object?> source;

  /// The key the level sat under, for a document that merely contains one.
  final String? nestedUnder;

  String get what =>
      nestedUnder == null ? path : '$path (under "$nestedUnder")';
}

/// Every JSON file under `apps/*/assets/` that is a level or holds one.
///
/// Found rather than listed: a sixth document added tomorrow is covered without
/// anybody remembering to add it here, which is the only kind of coverage that
/// survives contact with a repository.
List<_Document> _documents() {
  final found = <_Document>[];
  // The test runs with the app's own directory as the working directory, so
  // the other applications are siblings.
  for (final app in Directory('..').listSync().whereType<Directory>()) {
    final assets = Directory('${app.path}/assets');
    if (!assets.existsSync()) continue;

    for (final file in assets.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(file.readAsStringSync());
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, Object?>) continue;

      if (decoded['brushes'] is List) {
        found.add(_Document(file.path, decoded));
        continue;
      }
      // A document that merely *contains* a level: the racing track holds its
      // circuit beside it, and both have to come back.
      final nested = decoded['level'];
      if (nested is Map<String, Object?> && nested['brushes'] is List) {
        found.add(_Document(file.path, nested, nestedUnder: 'level'));
      }
    }
  }
  found.sort((_Document a, _Document b) => a.path.compareTo(b.path));
  return found;
}

void main() {
  final documents = _documents();

  test('there are level documents to check at all', () {
    // Otherwise everything below passes by having nothing to say.
    expect(documents, hasLength(greaterThanOrEqualTo(4)),
        reason: 'found only ${documents.map((_Document d) => d.path)}');
  });

  for (final document in documents) {
    test('${document.what} survives being read and written back', () {
      final written = Level.fromJson(document.source).toJson();

      // Compared as encoded text rather than as maps, and that is the whole
      // point: it catches a key that moved, a key that appeared, a key that
      // vanished, and an integer that became a double — every one of which is a
      // silent change when two decoded maps are compared for equality.
      expect(
        const JsonEncoder.withIndent(' ').convert(written),
        const JsonEncoder.withIndent(' ').convert(document.source),
      );
    });
  }
}
