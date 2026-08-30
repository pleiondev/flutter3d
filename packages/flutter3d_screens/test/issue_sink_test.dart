/// What these documents say when they cannot read themselves.
///
///     flutter test test/issue_sink_test.dart
///
/// **A save that would not parse became a new game, silently.** The package
/// printed a line and handed back null — and null is also what a player who
/// has never played gets, so the two are indistinguishable to the one person
/// who needed to know.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_screens/flutter3d_screens.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Storage implements Storage {
  _Storage([this.documents = const <String, String>{}]);

  final Map<String, String> documents;

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) => true;

  @override
  void remove(String name) {}
}

void main() {
  test('a save that is not JSON at all is reported, not swallowed', () {
    final log = IssueLog();
    final saves = SaveFile(
      appName: 'test',
      storage: _Storage(<String, String>{'save.json': '{ half a doc'}),
      onIssue: log.add,
    );

    expect(saves.read(), isNull);
    expect(log.issues, hasLength(1));
    expect(log.summary, contains('save'));
  });

  test('and a document that parses but is not a save is reported too', () {
    // **These said nothing at all**, which is worse than the `catch`: a file
    // from a build that named its keys differently went back as "no save"
    // without a word anywhere.
    for (final text in <String>['[]', '{}', '{"level": 3, "run": {}}']) {
      final log = IssueLog();
      final saves = SaveFile(
        appName: 'test',
        storage: _Storage(<String, String>{'save.json': text}),
        onIssue: log.add,
      );

      expect(saves.read(), isNull, reason: '$text was read as a save');
      expect(log.isNotEmpty, isTrue, reason: '$text was refused in silence');
    }
  });

  test('and a save that reads says nothing', () {
    final log = IssueLog();
    final saves = SaveFile(
      appName: 'test',
      storage: _Storage(<String, String>{
        'save.json': '{"level": "a.json", "run": {"version": 1}}',
      }),
      onIssue: log.add,
    );

    expect(saves.read()?.level, 'a.json');
    expect(log.isEmpty, isTrue, reason: 'it complained about a good save');
  });

  test(
    'settings that will not parse are reported, and still start the game',
    () {
      // Never throwing is the right behaviour and always was — what was missing
      // is that the application is the only thing here with a screen.
      final log = IssueLog();
      final settings = SettingsFile(
        appName: 'test',
        storage: _Storage(<String, String>{'settings.json': 'not json'}),
        onIssue: log.add,
      );

      expect(
        settings.read().volumeOf('sfx'),
        1.0,
        reason: 'it did not fall back to defaults',
      );
      expect(log.isNotEmpty, isTrue);
    },
  );

  test('and the default is what the code did before: print and carry on', () {
    // A caller that has not thought about this yet loses nothing.
    final saves = SaveFile(
      appName: 'test',
      storage: _Storage(<String, String>{'save.json': 'rubbish'}),
    );

    expect(saves.read, returnsNormally);
  });
}
