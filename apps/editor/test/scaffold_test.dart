/// A new project, laid out in memory.
///
///     flutter test test/scaffold_test.dart
///
/// **The part that can go wrong permanently.** Everything else an editor does
/// is one nudge that undo puts back; this writes a directory somebody will
/// spend a week in. So it is a function from a template to bytes, with no disk
/// and no window in it — the same split `editing.dart` makes.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:editor/src/editing.dart';
import 'package:editor/src/looks.dart';
import 'package:editor/src/scaffold.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shipped shooter template, read off the disk the way every other test
/// here reads data.
({Template template, Map<String, Uint8List> sources}) _shooter() {
  const where = 'assets/templates/shooter';
  final template = Template.parse(
    'shooter',
    File('$where/index.json').readAsStringSync(),
  );
  return (
    template: template,
    sources: <String, Uint8List>{
      for (final name in template.files.keys)
        name: File('$where/$name').readAsBytesSync(),
    },
  );
}

Map<String, Uint8List> _project({String name = 'My Game'}) {
  final it = _shooter();
  return scaffold(
    template: it.template,
    project: name,
    sources: it.sources,
    packagesAt: '/somewhere/flutter3d/packages',
  );
}

String _text(Map<String, Uint8List> project, String path) =>
    utf8.decode(project[path]!);

void main() {
  test('a project has the four things a project is', () {
    final project = _project();

    expect(project.keys, containsAll(<String>[
      'assets/editor.json',
      'assets/levels/first.json',
      'pubspec.yaml',
      'README.md',
    ]));
    expect(project.keys.where((String it) => it.endsWith('.glb')), isNotEmpty);
  });

  test('and its layout is the one the editor already knows how to open', () {
    // Not a choice: `Documents.assetRootFor` climbs until a directory has an
    // `assets` in it, and `assets/models/…` in `editor.json` is resolved from
    // there. Deviating breaks the editor's own path resolution.
    final project = _project();

    final looks = Looks.parse(_text(project, 'assets/editor.json'));
    final model = looks.modelFor(EntityDef(type: 'monster'))!;

    expect(project.keys, contains(model));
  });

  group('the first level', () {
    test('can be saved, which the template\'s own copy cannot', () {
      // **`generatedBy` is what stops an editor writing over a file a script
      // owns**, and the template's level is generated and says so honestly. Copy
      // it unchanged and the new project's very first save is refused, with a
      // message about a Python file its author has never heard of.
      final project = _project();

      final editing = Editing.parse(
        _text(project, 'assets/levels/first.json'),
        path: '/my_game/assets/levels/first.json',
      );

      expect(editing.generatedBy, isNull);
      expect(editing.mayOverwrite, isTrue);
    });

    test('and the template it came from is still written on it', () {
      // So the palette can be rebuilt even if `assets/editor.json` is lost.
      final json = jsonDecode(_text(_project(), 'assets/levels/first.json'))
          as Map<String, Object?>;

      expect(json['editor'], <String, Object?>{'template': 'shooter'});
    });

    test('and it is still a level the game would load', () {
      // Taking a key off a document is one line away from taking a level apart.
      final level = Level.fromJson(
        jsonDecode(_text(_project(), 'assets/levels/first.json'))
            as Map<String, Object?>,
      );

      final issues = LevelValidator(
        registry: sampleRegistry(),
        rules: sampleRules(),
      ).validate(level);

      expect(issues, isEmpty);
    });

    test('and saving it changes nothing, because it is already written that '
        'way', () {
      final text = _text(_project(), 'assets/levels/first.json');

      expect(Editing.parse(text, path: 'x').write(), text);
    });
  });

  group('the pubspec', () {
    test('is the project\'s name, not the template\'s', () {
      expect(_text(_project(name: 'Deep Mine'), 'pubspec.yaml'),
          contains('name: deep_mine'));
    });

    test('and never says it is part of a workspace', () {
      // **Every pubspec in this repository says `resolution: workspace`**, which
      // makes it the easiest line in the world to copy — and outside a workspace
      // root it is a pub error about a file the author did not write.
      expect(_text(_project(), 'pubspec.yaml'),
          isNot(contains('resolution: workspace')));
    });

    test('and points at the checkout it was made from', () {
      // None of these packages are published, so a path is the only thing that
      // can be written — and it is true on one machine, which the README says.
      final pubspec = _text(_project(), 'pubspec.yaml');

      expect(pubspec, contains('path: /somewhere/flutter3d/packages/flutter3d'));
      expect(pubspec, contains('flutter3d_session:'));
    });

    test('and does not ship the file only the editor reads', () {
      // `assets/editor.json` is for the editor. A player downloading it is a
      // player downloading the editor's opinion of their game.
      expect(_text(_project(), 'pubspec.yaml'),
          isNot(contains('assets/editor.json')));
    });
  });

  group('the name', () {
    test('becomes something pub will accept', () {
      expect(packageName('My Game'), 'my_game');
      expect(packageName('  Deep-Mine!! '), 'deep_mine');
      expect(packageName('2nd try'), 'game_2nd_try');
      expect(packageName(''), 'my_game');
    });
  });

  test('and a template that lists a file nobody shipped says so', () {
    // The failure a missing `assets:` line produces, caught where it can be
    // explained rather than where it throws.
    final it = _shooter();
    final missing = Map<String, Uint8List>.of(it.sources)
      ..remove(it.template.files.keys.first);

    expect(
      () => scaffold(
        template: it.template,
        project: 'x',
        sources: missing,
        packagesAt: '/p',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
