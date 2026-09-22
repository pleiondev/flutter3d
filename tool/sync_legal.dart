/// Copies `legal/*.md` into the Modeller's own assets — `rel-21d`.
///
/// **Why a copy at all.** Flutter bundles assets from inside the package that
/// declares them; `../../legal/` is not inside `apps/flutter3d_modeler`, and a
/// symlink is a different thing on each of the four platforms this application
/// ships on. So the documents are copied, and the copy is checked:
/// `apps/flutter3d_modeler/test/legal_documents_test.dart` reads both and
/// fails when they differ, which turns "somebody edited the policy and forgot
/// the app" from a thing nobody notices into a red test.
///
/// **`legal/` stays the source of truth.** Edit the document there, run this,
/// and commit both — the same shape `rel-13`'s own template export already
/// has, and for the same reason: a generated file that can be edited in place
/// is a generated file that will be.
///
///     dart run tool/sync_legal.dart            # write the copies
///     dart run tool/sync_legal.dart --check    # say whether they are current
library;

import 'dart:io';

/// Where the documents live, and where the application reads them from.
const String _from = 'legal';
const String _to = 'apps/flutter3d_modeler/assets/legal';

void main(List<String> arguments) {
  final bool checkOnly = arguments.contains('--check');
  final source = Directory(_from);
  if (!source.existsSync()) {
    stderr.writeln('no $_from/ here — run this from the repository root');
    exit(2);
  }

  final List<File> documents =
      source
          .listSync()
          .whereType<File>()
          .where((File it) => it.path.endsWith('.md'))
          // `README.md` is about the documents rather than one of them: it
          // carries the open items and the store answers, which are notes to
          // whoever publishes and not a text anybody is shown in the app.
          .where((File it) => !it.path.endsWith('README.md'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));

  final target = Directory(_to);
  if (!checkOnly) target.createSync(recursive: true);

  final stale = <String>[];
  for (final File document in documents) {
    final String name = document.uri.pathSegments.last;
    final copy = File('$_to/$name');
    final String wanted = document.readAsStringSync();
    final bool current = copy.existsSync() && copy.readAsStringSync() == wanted;
    if (current) continue;
    stale.add(name);
    if (!checkOnly) copy.writeAsStringSync(wanted);
  }

  // A document deleted from `legal/` has to stop being bundled, or the
  // application goes on showing a policy that has been withdrawn.
  final wanted = <String>{
    for (final File document in documents) document.uri.pathSegments.last,
  };
  if (target.existsSync()) {
    for (final FileSystemEntity each in target.listSync()) {
      final String name = each.uri.pathSegments.last;
      if (each is! File || !name.endsWith('.md') || wanted.contains(name)) {
        continue;
      }
      stale.add('$name (no longer in $_from/)');
      if (!checkOnly) each.deleteSync();
    }
  }

  if (checkOnly) {
    if (stale.isEmpty) {
      stdout.writeln('${documents.length} documents, all current');
      return;
    }
    stderr.writeln(
      '${stale.length} out of date: ${stale.join(', ')}\n'
      'run `dart run tool/sync_legal.dart`',
    );
    exit(1);
  }
  stdout.writeln(
    stale.isEmpty
        ? '${documents.length} documents, nothing to do'
        : 'wrote ${stale.length} of ${documents.length}: ${stale.join(', ')}',
  );
}
