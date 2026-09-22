/// How far the showcase has got, counted from its files.
///
/// **What is expected comes from the same list the workers write against.**
/// `apps/flutter3d_showcase/coverage.md` names every page of every set, so the
/// number a set is measured against is not typed in here and cannot drift from
/// the list. A page counts when it has both its file and its guide, since a
/// page without a guide is half of what was asked for.
library;

import 'dart:io';

import 'model.dart';

const String _appDir = 'apps/flutter3d_showcase';

/// The sets, in the order the work is planned, with a name for the row.
const List<({String id, String title})> _setNames =
    <({String id, String title})>[
      (id: 'a', title: 'shading'),
      (id: 'b', title: 'environment and shadows'),
      (id: 'c', title: 'post-processing'),
      (id: 'd', title: 'scene and geometry'),
      (id: 'e', title: 'animation'),
      (id: 'f', title: 'views, input and backends'),
      (id: 'g', title: 'formats'),
      (id: 'h', title: 'physics and particles'),
      (id: 'i', title: 'simulation, audio, XR and widgets'),
    ];

/// Reads the app's files under [root]; the absent snapshot when there is no
/// app there yet.
ShowcaseSnapshot readShowcase(Directory root) {
  final app = Directory('${root.path}/$_appDir');
  final coverage = File('${app.path}/coverage.md');
  if (!app.existsSync() || !coverage.existsSync()) {
    return const ShowcaseSnapshot.absent();
  }
  final text = coverage.readAsStringSync();
  final sections = _sections(text);

  final sets = <ShowcaseSet>[];
  for (final name in _setNames) {
    final section = sections[name.id];
    if (section == null) continue;
    final categories = section.categories;
    sets.add(
      ShowcaseSet(
        id: name.id,
        title: name.title,
        categories: categories,
        expected: section.rows,
        pages: <int>[
          for (final category in categories) _pagesIn(app, category),
        ].fold(0, (int sum, int n) => sum + n),
        catalogRows: <int>[
          for (final category in categories) _catalogRowsIn(app, category),
        ].fold(0, (int sum, int n) => sum + n),
      ),
    );
  }
  return ShowcaseSnapshot(
    sets: sets,
    live: null,
    coverageFilled: _auditFilled(text),
  );
}

/// The audit at the end of `coverage.md` starts as a paragraph that says it is
/// still to be written; once that sentence is gone it has been.
bool _auditFilled(String text) {
  final at = text.indexOf('## The 0.7.0 audit');
  if (at < 0) return false;
  return !text.substring(at).contains('To be filled in');
}

typedef _Section = ({int rows, List<String> categories});

/// `## Set X: name (`lib/pages/a/`, `lib/pages/b/`)`: the table rows under it
/// and the categories its heading names.
Map<String, _Section> _sections(String coverage) {
  final out = <String, _Section>{};
  final heading = RegExp(r'^## Set ([A-I]): .*$', multiLine: true);
  final matches = heading.allMatches(coverage).toList();
  for (var i = 0; i < matches.length; i++) {
    final end = i + 1 < matches.length
        ? matches[i + 1].start
        : _nextSection(coverage, matches[i].end);
    final body = coverage.substring(matches[i].end, end);
    final categories = <String>[
      for (final m in RegExp(
        r'lib/pages/([a-z_]+)/',
      ).allMatches(matches[i].group(0)!))
        m.group(1)!,
    ];
    // A table row whose first cell is a page id; the header row's first cell
    // is the word "id".
    final rows = RegExp(
      r'^\| ([a-z0-9]+(?:-[a-z0-9]+)*) \|',
      multiLine: true,
    ).allMatches(body).where((m) => m.group(1) != 'id').length;
    out[matches[i].group(1)!.toLowerCase()] = (
      rows: rows,
      categories: categories,
    );
  }
  return out;
}

/// Where the last set's table ends: at the next `## ` heading that is not a set.
int _nextSection(String text, int from) {
  final next = RegExp(
    r'^## ',
    multiLine: true,
  ).firstMatch(text.substring(from));
  return next == null ? text.length : from + next.start;
}

/// Pages of [category] that have both a `.dart` and a `.md`.
int _pagesIn(Directory app, String category) {
  final dir = Directory('${app.path}/lib/pages/$category');
  if (!dir.existsSync()) return 0;
  final names = <String>{
    for (final file in dir.listSync().whereType<File>())
      file.uri.pathSegments.last,
  };
  return <String>[
    for (final name in names)
      if (name.endsWith('.md') &&
          names.contains('${name.substring(0, name.length - 3)}.dart'))
        name,
  ].length;
}

int _catalogRowsIn(Directory app, String category) {
  final file = File('${app.path}/lib/catalog/$category.dart');
  if (!file.existsSync()) return 0;
  return RegExp(
    r"^\s+id: '",
    multiLine: true,
  ).allMatches(file.readAsStringSync()).length;
}

/// Whether the published showcase answers. [fetch] returns the body, or null
/// when the host said anything but success: a page behind a login is "not
/// asked", never "down".
Future<bool?> readShowcaseLive(
  Future<String?> Function(Uri) fetch, {
  required String origin,
}) async {
  try {
    final body = await fetch(Uri.parse('$origin/showcase/'));
    if (body == null) return null;
    return body.contains('flutter3d Showcase');
  } on Object {
    return null;
  }
}
