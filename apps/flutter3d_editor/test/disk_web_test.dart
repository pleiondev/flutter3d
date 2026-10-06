/// The page's disk in a real browser: the two things `MemoryDisk` leaves to
/// `disk_web.dart` — session storage and the download — and that the web
/// build picks it at all.
///
///     flutter test --platform chrome test/disk_web_test.dart
///
/// **`@TestOn('browser')`, and named on the command line**: the VM run skips
/// it, and a browser run of the whole directory would compile the tests that
/// reach `dart:io` first and fail before filtering anything.
///
/// Each test names the mutation it was written against.
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_editor/src/disk/disk_web.dart';
import 'package:flutter3d_editor/src/disk/editor_disk.dart';
import 'package:flutter3d_editor/src/disk/memory_disk.dart';
import 'package:flutter3d_editor/src/play/play_launch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  setUp(() => web.window.sessionStorage.clear());

  test('a browser build gets the page\'s disk, and saving downloads', () {
    // Broken by the conditional import naming `dart.library.io`'s side for
    // the web: the build compiles (`dart:io` imports in a browser) and the
    // first save throws `Unsupported operation`.
    expect(editorDisk, isA<MemoryDisk>());
    expect(editorDisk.savesInPlace, isFalse);
  });

  test('a write survives into the next page, by its path', () {
    // Broken by `keep` writing under another key than `read` looks for, or
    // by base64 being skipped: a `.glb` in a template project is not text.
    final bytes = Uint8List.fromList(<int>[0, 159, 146, 150, 255]);
    SessionFiles.keep('/browser/projects/cellar/assets/models/key.glb', bytes);

    final restored = platformDisk();

    expect(
      restored.exists('/browser/projects/cellar/assets/models/key.glb'),
      isTrue,
    );
    expect(
      SessionFiles.read()['/browser/projects/cellar/assets/models/key.glb'],
      bytes,
    );
  });

  test('somebody else\'s session keys are not files', () {
    // Broken by reading every key: a game served from the same origin keeps
    // its own things in the same storage.
    web.window.sessionStorage.setItem(
      'flutter3d/flutter3d_demo_dungeon/settings.json',
      base64.encode(utf8.encode('{}')),
    );
    SessionFiles.keep('/browser/opened/a.json', utf8.encode('{}'));
    expect(SessionFiles.read().keys, <String>['/browser/opened/a.json']);
  });

  test('a download is an anchor that is clicked and taken away', () {
    // Broken by leaving the anchor in the document: a page that saved forty
    // times would carry forty dead links.
    final before = web.document.querySelectorAll('a').length;
    download('level.json', Uint8List.fromList(utf8.encode('{}')));
    expect(web.document.querySelectorAll('a').length, before);
  });

  test('Play in a browser says how to attach rather than starting', () {
    // Broken by the conditional import reaching `FlutterRun` in a browser —
    // which would not compile at all, so the build is the stronger check; this
    // is the sentence.
    expect(kStartsGames, isFalse);
    expect(whyCannotPlay('/browser/opened/a.json'), contains('attach'));
  });
}
