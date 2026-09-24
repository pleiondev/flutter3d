/// Runs every generator that a tracked document names, and nothing else.
///
///     dart run tool/regenerate_levels.dart     (from this package)
///
/// **This walks the documents instead of a list**, because the list was once
/// kept by hand and the hand forgot: two shipped levels went uncovered by the
/// regenerate-and-diff check for as long as the list was the index. Every
/// generated document records the generator that wrote it in `generatedBy`,
/// which makes the repository's own content the index and covers a new level
/// the day somebody commits it.
///
/// A name that resolves to no registered generator is an error rather than a
/// skip (see `generatorFor`), and a generator that writes no document naming
/// it is an error too: either is the drift this exists to catch.
library;

import 'dart:io';

import 'levels/shipped.dart';

void main() {
  final root = repositoryRoot(Directory.current.path);
  final found = trackedDocuments(root);
  if (found.isEmpty) {
    stderr.writeln('no tracked document names a generator');
    exitCode = 1;
    return;
  }
  final source = CheckoutSource(root);
  var wrote = 0;
  for (final MapEntry(key: script, value: generator)
      in shippedGenerators.entries) {
    final documents = found[script];
    if (documents == null) {
      stderr.writeln('$script is registered and no tracked document names it');
      exitCode = 1;
      return;
    }
    final written = generator(source);
    for (final MapEntry(key: path, value: text) in written.entries) {
      File('$root/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }
    wrote += documents.length;
    // Named rather than counted: which generators ran is the whole point, and
    // a list that silently got shorter would hide behind a bare number.
    stdout.writeln(
      '  ${script.padRight(56)} ${documents.length} document(s), '
      '${written.length} file(s)',
    );
  }
  stdout.writeln('${found.length} generators, $wrote documents');
}
