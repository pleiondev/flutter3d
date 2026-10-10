/// Plugin discovery over a package config written for the test: which
/// dependencies are plugins, and `lib/plugins.g.dart` written from them.
///
///     dart test test/plugin_discovery_test.dart
///
/// The fixture is a small workspace in a temporary directory: an
/// application, a plugin it depends on through another package, a plugin it
/// depends on only as a dev dependency, and a plugin it does not depend on
/// at all — the case a pub workspace makes ordinary, since one package
/// config lists every package of the workspace.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:test/test.dart';

void _package(Directory root, String name, String pubspec) {
  File('${root.path}/packages/$name/pubspec.yaml')
    ..createSync(recursive: true)
    ..writeAsStringSync('name: $name\n$pubspec');
}

Directory _workspace({bool graph = false}) {
  final root = Directory.systemTemp.createTempSync('f3d_plugins_');
  addTearDown(() => root.deleteSync(recursive: true));
  _package(root, 'app', '''
dependencies:
  effects: any
  helpers: any
dev_dependencies:
  devtool: any
''');
  _package(root, 'helpers', '''
dependencies:
  trails: any
''');
  // `trails` keeps the marker of before 1.0, which is read until 2.0.
  _package(root, 'trails', '''
flutter3d:
  plugin: trails.dart#TrailsPlugin
''');
  _package(root, 'effects', '''
flutter3d_plugins:
  plugin:
    - package:effects/bloom.dart#BloomPlugin
    - package:effects/bloom.dart#GlowPlugin
''');
  _package(root, 'devtool', '''
flutter3d_plugins:
  plugin: devtool.dart#DevPlugin
''');
  _package(root, 'elsewhere', '''
flutter3d_plugins:
  plugin: elsewhere.dart#ElsewherePlugin
''');
  final names = <String>[
    'app',
    'helpers',
    'trails',
    'effects',
    'devtool',
    'elsewhere',
  ];
  File('${root.path}/.dart_tool/package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          for (final name in names)
            <String, Object?>{
              'name': name,
              'rootUri': '../packages/$name',
              'packageUri': 'lib/',
            },
        ],
      }),
    );
  if (graph) {
    File('${root.path}/.dart_tool/package_graph.json').writeAsStringSync(
      jsonEncode(<String, Object?>{
        'packages': <Object?>[
          <String, Object?>{
            'name': 'app',
            'dependencies': <String>['effects', 'helpers'],
            'devDependencies': <String>['devtool'],
          },
          <String, Object?>{
            'name': 'helpers',
            'dependencies': <String>['trails'],
          },
          for (final name in <String>[
            'trails',
            'effects',
            'devtool',
            'elsewhere',
          ])
            <String, Object?>{'name': name, 'dependencies': <String>[]},
        ],
      }),
    );
  }
  return Directory('${root.path}/packages/app');
}

void main() {
  for (final graph in <bool>[false, true]) {
    test('finds the plugins the app depends on '
        '(${graph ? 'package graph' : 'pubspecs'})', () {
      // Mutation: walk every package in the config. "elsewhere" — a plugin
      // another application of the workspace uses — and the dev
      // dependency's plugin would be installed in this one.
      final discovery = discoverPlugins(_workspace(graph: graph));
      expect(discovery.plugins.map((p) => '$p'), <String>[
        'package:effects/bloom.dart#BloomPlugin',
        'package:effects/bloom.dart#GlowPlugin',
        'package:trails/trails.dart#TrailsPlugin',
      ]);
      expect(
        discovery.readFiles.where((f) => f.endsWith('package_graph.json')),
        graph ? hasLength(1) : isEmpty,
      );
    });
  }

  test('the marker of before 1.0 is still read, and warned about', () {
    // Mutation: read only `flutter3d_plugins:`. TrailsPlugin, still marked
    // `flutter3d: plugin:`, is no longer installed, and nothing says why.
    final discovery = discoverPlugins(_workspace());
    expect(
      discovery.plugins.map((p) => '$p'),
      contains('package:trails/trails.dart#TrailsPlugin'),
    );
    expect(discovery.warnings, hasLength(1));
    expect(
      discovery.warnings.single,
      allOf(contains('trails'), contains('flutter3d_plugins:')),
    );
  });

  test('the new key wins over the old one in the same pubspec', () {
    final app = _workspace();
    _package(app.parent.parent, 'trails', '''
flutter3d_plugins:
  plugin: trails.dart#NewTrails
flutter3d:
  plugin: trails.dart#OldTrails
''');
    final discovery = discoverPlugins(app);
    expect(
      discovery.plugins.map((p) => p.className),
      allOf(contains('NewTrails'), isNot(contains('OldTrails'))),
    );
    expect(discovery.warnings, isEmpty);
  });

  test('writes plugins.g.dart, and leaves it alone when nothing changed', () {
    final app = _workspace();
    final first = writeDiscoveredPlugins(app);
    expect(first.written, isTrue);
    final text = File('${app.path}/lib/plugins.g.dart').readAsStringSync();
    expect(text, contains("import 'package:effects/bloom.dart' as p0;"));
    expect(text, contains("import 'package:trails/trails.dart' as p1;"));
    expect(text, contains('List<Flutter3dPlugin> get installedPlugins'));
    expect(text, contains('p0.GlowPlugin(),'));
    expect(text, contains('p1.TrailsPlugin(),'));
    expect(writeDiscoveredPlugins(app).written, isFalse);
  });

  test('an app with no plugin dependency gets no file from a build', () {
    final app = _workspace();
    File('${app.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    expect(writeDiscoveredPlugins(app).written, isFalse);
    expect(File('${app.path}/lib/plugins.g.dart').existsSync(), isFalse);
    // The command asks for one anyway.
    expect(writeDiscoveredPlugins(app, always: true).written, isTrue);
  });

  test('a marker that is not <import>#<Class> names the package', () {
    final app = _workspace();
    _package(app.parent.parent, 'trails', '''
flutter3d_plugins:
  plugin: TrailsPlugin
''');
    expect(
      () => discoverPlugins(app),
      throwsA(
        isA<PluginDiscoveryException>().having(
          (e) => e.message,
          'message',
          allOf(contains('trails'), contains('<import>#<Class>')),
        ),
      ),
    );
  });

  test('a package of several libraries marks each one, in the same order '
      'a list would', () {
    // Mutation: read a map's keys as classes, or its values as one string.
    // The map form would name `light.dart` as a class, and the order
    // `plugins.g.dart` installs in would change with the form.
    final app = _workspace();
    _package(app.parent.parent, 'effects', '''
flutter3d_plugins:
  plugin:
    bloom.dart: [BloomPlugin, GlowPlugin]
    package:effects/fog.dart: FogPlugin
''');
    expect(discoverPlugins(app).plugins.map((p) => '$p'), <String>[
      'package:effects/bloom.dart#BloomPlugin',
      'package:effects/bloom.dart#GlowPlugin',
      'package:effects/fog.dart#FogPlugin',
      'package:trails/trails.dart#TrailsPlugin',
    ]);
    expect(
      markerEntries('effects', <String, Object?>{
        'a.dart': 'A',
        'b.dart': <Object?>['B', 'C'],
      }),
      <String>['a.dart#A', 'b.dart#B', 'b.dart#C'],
    );
    expect(
      () => markerEntries('effects', <String, Object?>{'a.dart': 3}),
      throwsA(isA<PluginDiscoveryException>()),
    );
  });

  /// The fixture's application with [selection] under its own
  /// `flutter3d_plugins:` key, and `effects` marking two libraries.
  Directory selecting(String selection) {
    final app = _workspace();
    _package(app.parent.parent, 'effects', '''
flutter3d_plugins:
  plugin:
    bloom.dart: [BloomPlugin, GlowPlugin]
    fog.dart: FogPlugin
''');
    _package(app.parent.parent, 'app', '''
dependencies:
  effects: any
  helpers: any
flutter3d_plugins:
$selection
''');
    return app;
  }

  test("the app's exclude leaves out a library, and plugins.g.dart says "
      'so', () {
    // Mutation: ignore the app's own key. FogPlugin is installed and
    // generated although the application asked for it not to be.
    final app = selecting('  exclude: [effects/fog.dart]');
    final discovery = discoverPlugins(app);
    expect(discovery.plugins.map((p) => '$p'), <String>[
      'package:effects/bloom.dart#BloomPlugin',
      'package:effects/bloom.dart#GlowPlugin',
      'package:trails/trails.dart#TrailsPlugin',
    ]);
    expect(discovery.excluded.map((p) => '$p'), <String>[
      'package:effects/fog.dart#FogPlugin',
    ]);
    writeDiscoveredPlugins(app);
    final text = File('${app.path}/lib/plugins.g.dart').readAsStringSync();
    expect(text, isNot(contains('FogPlugin')));
    expect(text, isNot(contains('package:effects/fog.dart')));
  });

  test('exclude takes one class, and include narrows to a package', () {
    // Mutation: match a class selector by library alone. GlowPlugin's
    // sibling BloomPlugin would go with it.
    final app = selecting('''
  include: [package:effects]
  exclude:
    - effects/bloom.dart#GlowPlugin
''');
    final discovery = discoverPlugins(app);
    expect(discovery.plugins.map((p) => p.className), <String>[
      'BloomPlugin',
      'FogPlugin',
    ]);
    expect(
      discovery.excluded.map((p) => p.className),
      unorderedEquals(<String>['GlowPlugin', 'TrailsPlugin']),
    );
  });

  test('an entry that matches nothing is warned about, not ignored', () {
    // Mutation: drop the warning. A misspelt exclusion leaves the plugin
    // installed and nothing says why.
    final discovery = discoverPlugins(
      selecting('  exclude: [effects/fogg.dart, nobody]'),
    );
    expect(discovery.excluded, isEmpty);
    final mine = discovery.warnings.where((w) => w.contains('exclude'));
    expect(mine, hasLength(2));
    expect(mine.first, contains('effects/fogg.dart'));
    expect(mine.last, contains('nobody'));
  });

  test('a selector that is none of the three forms names the pubspec', () {
    expect(
      () => discoverPlugins(selecting('  exclude: [effects/fog]')),
      throwsA(
        isA<PluginDiscoveryException>().having(
          (e) => e.message,
          'message',
          allOf(contains('pubspec.yaml'), contains('effects/fog')),
        ),
      ),
    );
    expect(
      () => PluginSelector.parse('effects#Fog'),
      throwsA(isA<PluginDiscoveryException>()),
    );
    expect(
      '${PluginSelector.parse('package:effects/fog.dart#FogPlugin')}',
      'effects/fog.dart#FogPlugin',
    );
  });

  test("a marker may not import another package's library", () {
    final app = _workspace();
    _package(app.parent.parent, 'trails', '''
flutter3d_plugins:
  plugin: package:effects/bloom.dart#BloomPlugin
''');
    expect(
      () => discoverPlugins(app),
      throwsA(isA<PluginDiscoveryException>()),
    );
  });
}
