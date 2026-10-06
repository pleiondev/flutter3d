/// Play's two answers: a desktop starts the project, a browser says how to
/// attach. Both halves are plain Dart, so both run on the VM — the browser's
/// half imported by name, as `play_launch.dart` would in a web build.
///
/// Each test names the mutation it was written against.
library;

import 'dart:io';

import 'package:flutter3d_editor/src/play/play_launch.dart';
import 'package:flutter3d_editor/src/play/play_launch_web.dart' as web;
import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('play_launch_'));
  tearDown(() => temp.deleteSync(recursive: true));

  String levelInProject(String name) {
    final root = Directory('${temp.path}/$name')..createSync();
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: $name');
    return '${root.path}/assets/levels/first.json';
  }

  test('a desktop plays a level that is inside a project', () {
    expect(kStartsGames, isTrue);
    expect(whyCannotPlay(levelInProject('cellar')), isNull);
    expect(whyCannotPlay('${temp.path}/loose.json'), contains('not inside'));
  });

  test('the same project is the same run, another project a new one', () {
    // Broken by building a new `FlutterRun` every time: a second press of
    // Play would start a second game over the first.
    final level = levelInProject('cellar');
    final first = gameFor(level, null);
    expect(gameFor(level, first), same(first));
    expect(gameFor(levelInProject('attic'), first), isNot(same(first)));
  });

  test('a run started here has a device to pick; an attached one has not', () {
    final run = gameFor(levelInProject('cellar'), null);
    expect(devicePickerFor(run), isNotNull);
    expect(devicePickerFor(AttachedRun('ws://127.0.0.1:8181/ws')), isNull);
  });

  test('a browser starts nothing, and says what to do instead', () {
    // Broken by the web half answering null: `_play` would then reach
    // `gameFor`, which throws.
    expect(web.kStartsGames, isFalse);
    final why = web.whyCannotPlay(levelInProject('cellar'));
    expect(why, allOf(contains('browser'), contains('attach')));
    expect(() => web.gameFor('x', null), throwsUnsupportedError);
    expect(web.devicePickerFor(AttachedRun('ws://127.0.0.1:8181/ws')), isNull);
  });
}
