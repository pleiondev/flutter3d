/// `flutter3d create plugin`'s templates: the files each kind gets, the names
/// written into them, and a pubspec marker discovery reads back.
///
///     dart test test/plugin_template_test.dart
///
/// What this cannot check without building is whether the generated Dart
/// compiles; that was checked by generating every kind and analysing it
/// against the real packages when the templates were written. What it holds
/// is everything around the code that a later edit could break silently.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:test/test.dart';

const String _name = 'my_glow';

/// Writes [files] as a package beside an application depending on it, with
/// a package config naming both, and runs discovery from the application.
PluginDiscovery _discover(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('f3d_template_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final MapEntry(key: path, value: text) in files.entries) {
    File('${root.path}/packages/$_name/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }
  File('${root.path}/packages/app/pubspec.yaml')
    ..createSync(recursive: true)
    ..writeAsStringSync('name: app\ndependencies:\n  $_name: any\n');
  File('${root.path}/.dart_tool/package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          for (final name in <String>['app', _name])
            <String, Object?>{
              'name': name,
              'rootUri': '../packages/$name',
              'packageUri': 'lib/',
            },
        ],
      }),
    );
  return discoverPlugins(Directory('${root.path}/packages/app'));
}

void main() {
  group('every kind', () {
    for (final kind in PluginKind.values) {
      test('$kind writes the package\'s eight files', () {
        // Mutation: drop the conformance test from the map. A plugin made
        // from the template would have no way to earn the badge.
        expect(pluginTemplate(name: _name, kind: kind).keys.toSet(), <String>{
          'pubspec.yaml',
          'analysis_options.yaml',
          'lib/$_name.dart',
          'test/${_name}_test.dart',
          'test/conformance_test.dart',
          'README.md',
          'CHANGELOG.md',
          '.gitignore',
        });
      });

      test('$kind leaves no placeholder unfilled', () {
        // Mutation: misspell a placeholder (`{{clas}}`). The fill leaves it
        // as written, and the generated file does not compile.
        for (final MapEntry(key: path, value: text) in pluginTemplate(
          name: _name,
          kind: kind,
        ).entries) {
          expect(text, isNot(contains('{{')), reason: path);
        }
      });

      test('$kind\'s marker is read back by discovery', () {
        // Mutation: write the marker as `flutter3d_plugin:` or name the
        // class without `Plugin`. Discovery finds nothing, or a class the
        // library does not declare.
        final files = pluginTemplate(name: _name, kind: kind);
        final found = _discover(files).plugins.single;
        expect(found.import, 'package:$_name/$_name.dart');
        expect(found.className, 'MyGlowPlugin');
        expect(
          files['lib/$_name.dart'],
          contains('final class MyGlowPlugin extends Flutter3dPlugin'),
        );
      });

      test('$kind says what it touches', () {
        // Mutation: give the element template `touches: view`. The host
        // refuses it the step system its install adds.
        final library = pluginTemplate(
          name: _name,
          kind: kind,
        )['lib/$_name.dart']!;
        expect(
          library,
          contains(
            kind.simulates
                ? 'touches: PluginTouches.simulation'
                : 'touches: PluginTouches.view',
          ),
        );
        expect(library, contains("id: '$_name'"));
        expect(library, contains("'budget'"));
      });

      test('$kind carries the lints plugin only where it steps', () {
        // Mutation: add the `plugins:` block to every kind. A view plugin
        // would be held to rules about a step it never runs in.
        final options = pluginTemplate(
          name: _name,
          kind: kind,
        )['analysis_options.yaml']!;
        expect(options.contains('flutter3d_lints'), kind.simulates);
      });

      test('$kind is published under the catalogue\'s topic', () {
        // Mutation: drop the topic. The catalogue, read from pub.dev by
        // topic, never lists the package.
        expect(
          pluginTemplate(name: _name, kind: kind)['pubspec.yaml'],
          contains('  - flutter3d-plugin'),
        );
      });
    }
  });

  group('kinds', () {
    test(
      'are the five decision 20 names, simulation for genre and element',
      () {
        // Mutation: mark the genre a view kind. Its template would install
        // a step phase from a plugin the host holds to the view.
        expect(PluginKind.values.map((PluginKind k) => k.name), <String>[
          'render-step',
          'effect',
          'genre',
          'element',
          'tool',
        ]);
        expect(
          <String>[
            for (final kind in PluginKind.values)
              if (kind.simulates) kind.name,
          ],
          <String>['genre', 'element'],
        );
      },
    );

    test('an unknown kind is refused, naming the five', () {
      // Mutation: fall back to a default kind. `--kind rendr-step` would
      // write an effect without a word.
      expect(
        () => PluginKind.named('rendr-step'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            allOf(contains('render-step'), contains('tool')),
          ),
        ),
      );
      expect(PluginKind.named('element'), same(PluginKind.element));
    });

    test('a typed name becomes a package name, and its class follows', () {
      // Mutation: use the typed name as it is. `My Glow` is not a package
      // pub accepts, and the class would not be an identifier.
      final files = pluginTemplate(name: 'My Glow', kind: PluginKind.effect);
      expect(files.keys, contains('lib/my_glow.dart'));
      expect(files['pubspec.yaml'], startsWith('name: my_glow\n'));
      expect(files['lib/my_glow.dart'], contains('class MyGlowPlugin'));
    });
  });
}
