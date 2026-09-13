/// The model files this application offers back to somebody on their second
/// launch — `ui-15`'s own "недавние" half of the start screen.
///
///     flutter test test/recent_projects_test.dart
///
/// **No plugin and no window.** The open panel is the start screen's own job;
/// everything that can be wrong without it — what a stored path still means,
/// which order the paths go in, how many are kept and which of them have been
/// deleted since — is here, against a map in memory and a disk that is a set
/// of strings. That split mirrors `apps/flutter3d_editor`'s own
/// `recent_projects_test.dart`, the sibling this file's own class was ported
/// from.
library;

import 'dart:convert';

import 'package:flutter3d_modeler/src/recent_projects.dart';
import 'package:flutter3d_session/flutter3d_session.dart' show Storage;
import 'package:flutter_test/flutter_test.dart';

/// A disk with exactly these files on it — the same shape
/// `apps/flutter3d_editor`'s own test uses, because it is the same question
/// asked of the same seam.
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
  const teapot = '/models/teapot.glb';
  const vase = '/models/vase.f3d';
  const bolt = '/models/props/bolt.stl';

  test('a first launch offers nothing, rather than failing to find a file', () {
    final recent = RecentModels(storage: _Documents());

    expect(recent.read(exists: _anywhere), isEmpty);
  });

  test('the model opened last is the one offered first', () {
    final recent = RecentModels(storage: _Documents());

    recent.remember(teapot, exists: _anywhere);
    recent.remember(vase, exists: _anywhere);

    expect(recent.read(exists: _anywhere), <String>[vase, teapot]);
  });

  test('and opening one again moves it instead of adding a second', () {
    // A list where the model worked on every day appears eight times is a
    // list with room for nothing else — and the eight it fills are eight the
    // oldest entries were pushed out of.
    //
    // **Asserted on what is written, not only on what comes back.** Reading
    // puts the paths through a set, so a version of this that stored the same
    // model twice read back looking correct and quietly spent the list on one
    // model. The mutation that dropped the `!=` here survived the read-back
    // and dies against this line.
    final storage = _Documents();
    final recent = RecentModels(storage: storage);

    recent.remember(teapot, exists: _anywhere);
    recent.remember(vase, exists: _anywhere);

    expect(recent.remember(teapot, exists: _anywhere), <String>[teapot, vase]);
    expect(jsonDecode(storage.documents['recent.json']!), <String, Object?>{
      'recent': <String>[teapot, vase],
    });
    expect(recent.read(exists: _anywhere), <String>[teapot, vase]);
  });

  test('it keeps eight and forgets the ninth', () {
    final recent = RecentModels(storage: _Documents());
    for (var n = 0; n < 12; n++) {
      recent.remember('/models/generated/m$n.glb', exists: _anywhere);
    }

    final offered = recent.read(exists: _anywhere);

    expect(offered.length, RecentModels.keep);
    expect(offered.first, '/models/generated/m11.glb');
    expect(offered, isNot(contains('/models/generated/m3.glb')));
  });

  test('a model that is no longer on the disk is not offered', () {
    // Moved, renamed or deleted since: a row that fails when it is clicked is
    // worse than a row that is not there.
    final storage = _Documents();
    final recent = RecentModels(storage: storage);
    recent.remember(teapot, exists: _anywhere);
    recent.remember(vase, exists: _anywhere);

    final offered = RecentModels(
      storage: storage,
    ).read(exists: _disk(<String>{teapot}));

    expect(offered, <String>[teapot]);
  });

  test('and the next thing written down does not carry it back', () {
    // The disk decides on every read, so a list saved after a model went
    // missing is a list without it — the forgetting is not a separate chore
    // somebody has to remember to run.
    final storage = _Documents();
    RecentModels(storage: storage).remember(teapot, exists: _anywhere);
    RecentModels(storage: storage).remember(vase, exists: _anywhere);

    final written = RecentModels(
      storage: storage,
    ).remember(bolt, exists: _disk(<String>{bolt, vase}));

    expect(written, <String>[bolt, vase]);
    expect(storage.documents['recent.json'], isNot(contains(teapot)));
  });

  test('a document that will not parse is a first launch, not a crash', () {
    // Half a write on a platform where the rename did not apply, or a hand
    // edit that lost a brace. An empty list is right; refusing to start is
    // not — `ui-15`'s own "битый JSON — пустой список".
    final storage = _Documents()..documents['recent.json'] = '{"recent": [';

    expect(RecentModels(storage: storage).read(exists: _anywhere), isEmpty);
  });

  test('and neither is one that parses into something that is not a list', () {
    final storage = _Documents()..documents['recent.json'] = '{"recent": 3}';

    expect(RecentModels(storage: storage).read(exists: _anywhere), isEmpty);
  });

  test('what it writes is a document somebody could read', () {
    // Indented and named, because this sits beside this application's own
    // settings in a directory people do open.
    final storage = _Documents();
    RecentModels(storage: storage).remember(teapot, exists: _anywhere);

    final text = storage.documents['recent.json']!;

    expect(jsonDecode(text), <String, Object?>{
      'recent': <String>[teapot],
    });
    expect(text, contains('\n'), reason: 'it wrote one long line');
  });

  test('and clearing it forgets every model', () {
    final storage = _Documents();
    final recent = RecentModels(storage: storage)
      ..remember(teapot, exists: _anywhere)
      ..clear();

    expect(recent.read(exists: _anywhere), isEmpty);
    expect(storage.documents, isEmpty);
  });
}
