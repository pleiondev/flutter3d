/// The projects this editor offers back to somebody on their second launch.
///
///     flutter test test/recent_projects_test.dart
///
/// **No plugin and no window.** The open panel is one function in
/// `editor_chooser.dart` and is platform code; everything that can be wrong
/// without it — what the stored document still means, which order the paths go
/// in, how many are kept and which of them have been deleted since — is here,
/// against a map in memory and a disk that is a set of strings. That split is
/// the whole reason a file dialogue was allowed into this repository at all.
library;

import 'dart:convert';

import 'package:flutter3d_editor/src/recent_projects.dart';
import 'package:flutter3d_screens/flutter3d_screens.dart' show Storage;
import 'package:flutter_test/flutter_test.dart';

/// A disk with exactly these files on it — the same shape `documents_test.dart`
/// uses, because it is the same question asked of the same seam.
bool Function(String) _disk(Set<String> files) => files.contains;

/// Everything is there, for the tests that are not about anything going away.
bool _anywhere(String _) => true;

/// Documents in a map, which is what [Storage] is an interface for.
final class _Documents implements Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

void main() {
  const crypt = '/repo/apps/flutter3d_demo_dungeon/assets/levels/crypt.json';
  const mine = '/games/deep_mine/assets/levels/first.json';
  const attic = '/games/attic/assets/levels/first.json';

  test('a first launch offers nothing, rather than failing to find a file', () {
    final projects = RecentProjects(storage: _Documents());

    expect(projects.read(exists: _anywhere), isEmpty);
  });

  test('the document opened last is the one offered first', () {
    // The whole point of the list: the project somebody was in when they shut
    // the editor is the one they want when they open it.
    final projects = RecentProjects(storage: _Documents());

    projects.remember(crypt, exists: _anywhere);
    projects.remember(mine, exists: _anywhere);

    expect(projects.read(exists: _anywhere), <String>[mine, crypt]);
  });

  test('and opening one again moves it instead of adding a second', () {
    // A list where the project worked in every day appears eight times is a
    // list with room for nothing else — and the eight it fills are eight the
    // oldest entries were pushed out of.
    //
    // **Asserted on what is written, not only on what comes back.** Reading
    // puts the paths through a set, so a version of this that stored the same
    // project twice read back looking correct and quietly spent the list on
    // one project. The mutation that dropped the `!=` here survived the
    // read-back and dies against this line.
    final storage = _Documents();
    final projects = RecentProjects(storage: storage);

    projects.remember(crypt, exists: _anywhere);
    projects.remember(mine, exists: _anywhere);

    expect(projects.remember(crypt, exists: _anywhere), <String>[crypt, mine]);
    expect(jsonDecode(storage.documents['recent.json']!), <String, Object?>{
      'recent': <String>[crypt, mine],
    });
    expect(projects.read(exists: _anywhere), <String>[crypt, mine]);
  });

  test('it keeps eight and forgets the ninth', () {
    final projects = RecentProjects(storage: _Documents());
    for (var n = 0; n < 12; n++) {
      projects.remember(
        '/games/g$n/assets/levels/first.json',
        exists: _anywhere,
      );
    }

    final offered = projects.read(exists: _anywhere);

    expect(offered.length, RecentProjects.keep);
    expect(offered.first, '/games/g11/assets/levels/first.json');
    expect(offered, isNot(contains('/games/g3/assets/levels/first.json')));
  });

  test('a project that is no longer on the disk is not offered', () {
    // Moved, renamed or deleted since: a row that fails when it is clicked is
    // worse than a row that is not there.
    final storage = _Documents();
    final projects = RecentProjects(storage: storage);
    projects.remember(crypt, exists: _anywhere);
    projects.remember(mine, exists: _anywhere);

    final offered = RecentProjects(
      storage: storage,
    ).read(exists: _disk(<String>{crypt}));

    expect(offered, <String>[crypt]);
  });

  test('and the next thing written down does not carry it back', () {
    // The disk decides on every read, so a list saved after a project went
    // missing is a list without it — the forgetting is not a separate chore
    // somebody has to remember to run.
    final storage = _Documents();
    RecentProjects(storage: storage).remember(crypt, exists: _anywhere);
    RecentProjects(storage: storage).remember(mine, exists: _anywhere);

    final written = RecentProjects(
      storage: storage,
    ).remember(attic, exists: _disk(<String>{attic, mine}));

    expect(written, <String>[attic, mine]);
    expect(storage.documents['recent.json'], isNot(contains(crypt)));
  });

  test('a document that will not parse is a first launch, not a crash', () {
    // Half a write on a platform where the rename did not apply, or a hand
    // edit that lost a brace. An empty list is right; refusing to start is not.
    final storage = _Documents()..documents['recent.json'] = '{"recent": [';

    expect(RecentProjects(storage: storage).read(exists: _anywhere), isEmpty);
  });

  test('and neither is one that parses into something that is not a list', () {
    final storage = _Documents()..documents['recent.json'] = '{"recent": 3}';

    expect(RecentProjects(storage: storage).read(exists: _anywhere), isEmpty);
  });

  test('what it writes is a document somebody could read', () {
    // Indented and named, because this sits beside `settings.json` in a
    // directory people do open.
    final storage = _Documents();
    RecentProjects(storage: storage).remember(crypt, exists: _anywhere);

    final text = storage.documents['recent.json']!;

    expect(jsonDecode(text), <String, Object?>{
      'recent': <String>[crypt],
    });
    expect(text, contains('\n'), reason: 'it wrote one long line');
  });

  test('and clearing it forgets every project', () {
    final storage = _Documents();
    final projects = RecentProjects(storage: storage)
      ..remember(crypt, exists: _anywhere)
      ..clear();

    expect(projects.read(exists: _anywhere), isEmpty);
    expect(storage.documents, isEmpty);
  });
}
