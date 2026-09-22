/// Copies the modeller's own screenshots into the tutorial's assets and the
/// documentation site's.
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

/// Where the documentation site's own Modeler section serves them from —
/// `rel-08`.
///
/// **A third directory, and the alternative was a third copy nobody
/// maintained.** `site/content/modeler/` needs pictures of the editor, and
/// the pictures of the editor are already taken twice a day by the tour's
/// goldens. Copying a handful by hand would have meant a set that drifted
/// the first time a panel moved — the exact failure `--check` exists to
/// catch for the tutorial. So the site's copies are published by the same
/// command and held by the same check, and the only thing this file knows
/// extra is which of the tour's pictures the docs pages actually show.
const String _siteAssets = 'site/assets/modeler';

/// The tour pictures the documentation site's pages carry.
///
/// A named list rather than all of them: the tutorial's own page shows every
/// mode because that is its subject, and the docs section shows the five that
/// carry its argument. A picture added here without a page that shows it is a
/// file the site serves and nothing links to.
const List<String> _siteShots = <String>[
  'object-mode.png',
  'mesh-mode.png',
  'animation-weights.png',
  'scene-mode.png',
  'render-mode.png',
];

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
  // The flat pictures beside the case directories are the reference tour of
  // every mode, and they are published under `modes/` — `00-every-mode.md`
  // is the page that shows them. They used to stay in the goldens on the
  // reasoning that they belong to no one page; once there was a page whose
  // whole job is "here is every mode", that reasoning stopped applying.
  for (final FileSystemEntity picture in from.listSync()) {
    if (picture is! File || !picture.path.endsWith('.png')) continue;
    final String name = picture.uri.pathSegments.last;
    final File target = File('$_assets/modes/$name');
    final bool same =
        target.existsSync() &&
        _sameBytes(picture.readAsBytesSync(), target.readAsBytesSync());
    if (same) continue;
    if (checkOnly) {
      stale.add('modes/$name');
      continue;
    }
    target.parent.createSync(recursive: true);
    picture.copySync(target.path);
    published.add('modes/$name');
  }

  for (final String name in _siteShots) {
    final File picture = File('$_goldens/$name');
    if (!picture.existsSync()) {
      stderr.writeln('$name is on the docs list and not in the goldens');
      exitCode = 1;
      continue;
    }
    final File target = File('$_siteAssets/$name');
    final bool same =
        target.existsSync() &&
        _sameBytes(picture.readAsBytesSync(), target.readAsBytesSync());
    if (same) continue;
    if (checkOnly) {
      stale.add('site/$name');
      continue;
    }
    target.parent.createSync(recursive: true);
    picture.copySync(target.path);
    published.add('site/$name');
  }

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
