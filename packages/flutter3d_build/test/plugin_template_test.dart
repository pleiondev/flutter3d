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
  group('every plugin kind', () {
    for (final kind in PluginKind.values.where((k) => k.isPlugin)) {
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
        // Mutation: give the tool template `touches: view` again. A tool a
        // game ships without would be counted with what the player sees.
        expect(
          library,
          contains(switch (kind) {
            _ when kind.simulates => 'touches: PluginTouches.simulation',
            PluginKind.tool => 'touches: PluginTouches.tooling',
            _ => 'touches: PluginTouches.view',
          }),
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
    test('are the five decision 20 names and a backend, simulation for genre '
        'and element', () {
      // Mutation: mark the genre a view kind. Its template would install
      // a step phase from a plugin the host holds to the view.
      expect(PluginKind.values.map((PluginKind k) => k.name), <String>[
        'render-step',
        'effect',
        'genre',
        'element',
        'tool',
        'backend',
      ]);
      expect(
        <String>[
          for (final kind in PluginKind.values)
            if (!kind.isPlugin) kind.name,
        ],
        <String>['backend'],
      );
      expect(
        <String>[
          for (final kind in PluginKind.values)
            if (kind.simulates) kind.name,
        ],
        <String>['genre', 'element'],
      );
    });

    test('a kind that simulates keeps its state in the loop\'s snapshots '
        'from its install, not from the conformance test', () {
      // Mutation: register the snapshot part in the conformance test's
      // harness again. An application using the plugin rewinds and rolls
      // back without its state, and the conformance check still passes.
      for (final kind in <PluginKind>[PluginKind.genre, PluginKind.element]) {
        final files = pluginTemplate(name: _name, kind: kind);
        expect(
          files['test/conformance_test.dart'],
          allOf(isNot(contains('setUp')), isNot(contains('SnapshotPart'))),
          reason: '$kind',
        );
      }
      final genre = pluginTemplate(
        name: _name,
        kind: PluginKind.genre,
      )['lib/$_name.dart']!;
      expect(genre, contains('host.registry<SnapshotRegistry>().add('));
      // The element is a field and the subsystem that writes it, which the
      // loop snapshots for it.
      final element = pluginTemplate(
        name: _name,
        kind: PluginKind.element,
      )['lib/$_name.dart']!;
      expect(
        element,
        allOf(
          contains('host.registry<FieldRegistry>().declare(myGlowField)'),
          contains('host.registry<SubsystemRegistry>().register('),
          contains("writer: FieldAccess.simulation(MyGlowDecay.id)"),
          isNot(contains('elements')),
        ),
      );
    });

    test('an unknown kind is refused, naming the six', () {
      // Mutation: fall back to a default kind. `--kind rendr-step` would
      // write an effect without a word.
      expect(
        () => PluginKind.named('rendr-step'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            allOf(contains('render-step'), contains('backend')),
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

  group('a backend', () {
    // The reference the template is written from, outside `packages/`.
    final example = Directory('../../examples/flutter3d_backend_null');

    test('is the null backend example, file for file, under its own name', () {
      // Mutation: edit a line of `examples/flutter3d_backend_null` and not
      // the template, or the other way round. A backend made from the
      // template would no longer be the one conformance holds in CI.
      final files = pluginTemplate(
        name: 'flutter3d_backend_null',
        kind: PluginKind.backend,
      );
      final copied = <String>[
        for (final file in example.listSync(recursive: true).whereType<File>())
          if (file.path.endsWith('.dart'))
            file.path.substring(example.path.length + 1),
      ]..sort();
      expect(
        files.keys.where((path) => path.endsWith('.dart')).toList()..sort(),
        copied,
      );
      for (final path in copied) {
        expect(
          files[path],
          File('${example.path}/$path').readAsStringSync(),
          reason:
              '$path differs from the example; the template is the example '
              'with flutter3d_backend_null as {{name}}, Null as {{stem}}, '
              'null as {{label}} and nullSection as {{lowerStem}}Section',
        );
      }
    });

    test('names its classes and files after the package', () {
      // Mutation: leave a `Null` in a class name. Two backends made from the
      // template would declare the same classes.
      final files = pluginTemplate(name: 'my_vulkan', kind: PluginKind.backend);
      expect(files.keys, <String>{
        'pubspec.yaml',
        'analysis_options.yaml',
        'lib/my_vulkan.dart',
        'lib/src/my_vulkan_device.dart',
        'lib/src/my_vulkan_pass.dart',
        'lib/src/my_vulkan_texels.dart',
        'test/conformance_test.dart',
        'test/my_vulkan_device_test.dart',
        'README.md',
        'CHANGELOG.md',
        '.gitignore',
      });
      expect(
        files['lib/src/my_vulkan_device.dart'],
        allOf(
          contains('final class MyVulkanDevice extends GraphicsDevice'),
          contains("static const String name = 'my_vulkan';"),
          isNot(contains('Null')),
        ),
      );
      expect(files['lib/my_vulkan.dart'], contains('registerMyVulkanBackend'));
      for (final MapEntry(key: path, value: text) in files.entries) {
        expect(text, isNot(contains('{{')), reason: path);
      }
    });

    test('drops the engine prefix and the word backend from its names', () {
      final files = pluginTemplate(
        name: 'flutter3d_metal_backend',
        kind: PluginKind.backend,
      );
      expect(
        files['lib/src/metal_device.dart'],
        contains('final class MetalDevice'),
      );
    });

    test('is published under its own topic and depends on what it names', () {
      // Mutation: write the plugin marker into a backend's pubspec.
      // Discovery would look for a `Flutter3dPlugin` the package does not
      // declare.
      final pubspec = pluginTemplate(
        name: 'my_vulkan',
        kind: PluginKind.backend,
      )['pubspec.yaml']!;
      expect(pubspec, contains('  - flutter3d-backend'));
      expect(pubspec, isNot(contains('flutter3d_plugins:')));
      for (final package in <String>[
        'flutter3d_hardware',
        'flutter3d_shaders',
        'flutter3d_foundation',
        'flutter3d_conformance',
        'flutter3d_core',
      ]) {
        expect(pubspec, contains('  $package: ^1.0.0-rc.1'));
      }
    });
  });
}
