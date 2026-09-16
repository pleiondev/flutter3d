/// Copies the modeller's own screenshots into the tutorial's assets.
///
///     dart run tool/publish_modeler_screenshots.dart
///     dart run tool/publish_modeler_screenshots.dart --check
///
/// **Two directories rather than one, on purpose.** The pictures are goldens
/// first: `apps/flutter3d_modeler/test/goldens/screens/` is where they are
/// compared against what the editor draws today, and a run of
/// `tutorial_screenshots_test.dart` is what says whether a panel has moved.
/// The site serves from `cloud/server/web/assets/learn/modeler/`, which is a
/// different thing with a different lifetime — a page's own picture should
/// not change because somebody re-ran a test, it should change because
/// somebody published it.
///
/// So this is the step in between, and it is one command. `--check` answers
/// whether the two agree without writing anything, which is what a CI step
/// would ask.
library;

import 'dart:io';

/// Where the goldens are written.
const String _goldens = 'apps/flutter3d_modeler/test/goldens/screens';

/// Where the site serves them from.
const String _assets = 'cloud/server/web/assets/learn/modeler';

void main(List<String> arguments) {
  final bool checkOnly = arguments.contains('--check');
  final Directory from = Directory(_goldens);
  if (!from.existsSync()) {
    stderr.writeln(
      'No screenshots at $_goldens. Take them first:\n'
      '  (cd apps/flutter3d_modeler && flutter test '
      'test/tutorial_screenshots_test.dart '
      'test/tutorial_case_screenshots_test.dart --update-goldens)',
    );
    exitCode = 1;
    return;
  }

  final published = <String>[];
  final stale = <String>[];
  // Only the ones filed under a case directory: the flat pictures beside
  // them are the reference tour of every mode, which belongs to the goldens
  // and not to any one page.
  for (final FileSystemEntity entity in from.listSync()) {
    if (entity is! Directory) continue;
    final String caseName = entity.uri.pathSegments
        .where((String it) => it.isNotEmpty)
        .last;
    for (final FileSystemEntity picture in entity.listSync()) {
      if (picture is! File || !picture.path.endsWith('.png')) continue;
      final String name = picture.uri.pathSegments.last;
      final File target = File('$_assets/$caseName/$name');
      final bool same =
          target.existsSync() &&
          _sameBytes(picture.readAsBytesSync(), target.readAsBytesSync());
      if (same) continue;
      if (checkOnly) {
        stale.add('$caseName/$name');
        continue;
      }
      target.parent.createSync(recursive: true);
      picture.copySync(target.path);
      published.add('$caseName/$name');
    }
  }

  if (checkOnly) {
    if (stale.isEmpty) {
      stdout.writeln('the tutorial\'s pictures are the ones the editor draws');
      return;
    }
    stderr.writeln(
      'these pictures differ from what the editor draws now:\n'
      '  ${stale.join('\n  ')}\n'
      'Publish them: dart run tool/publish_modeler_screenshots.dart',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln(
    published.isEmpty
        ? 'nothing to publish; every picture is already current'
        : 'published ${published.length}:\n  ${published.join('\n  ')}',
  );
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
