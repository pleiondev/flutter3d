import 'dart:io';

import 'package:flutter3d_build/src/migrate/fix_data.dart';
import 'package:flutter3d_build/src/migrate/guide.dart';
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:flutter3d_build/src/migrate/project.dart';
import 'package:flutter3d_build/src/migrate/table.dart';
import 'package:test/test.dart';

const String _table = '''
format: 1
from: 0.1.0
to: 1.0.0
date: 2026-10-08
guide: https://example.dev/migrating/
packages:
  constraint: ^1.0.0
  versions:
    pad_input: ^0.5.0
  renamed:
    flutter3d_old: flutter3d_new
  removed:
    flutter3d_gone: Use flutter3d_core.
entries:
  - id: core-Ab
    package: flutter3d_core
    symbol: Ab
    kind: rename
    to: Cd
  - id: core-ef
    package: flutter3d_core
    symbol: ef
    kind: moved
    to: package:flutter3d_core/more.dart
  - id: core-Gh-k
    package: flutter3d_core
    symbol: Gh.k
    kind: rewrite
    template: '{target}.features.has(Feature.k)'
    imports: [package:flutter3d_core/flutter3d_core.dart]
  - id: core-Mn
    package: flutter3d_core
    symbol: Mn
    kind: manual
    guidance: >-
      `Mn` has a new case, `Op`: a `switch` over a `Mn` needs one.
  - id: build-moved-library
    kind: import
    from: package:flutter3d_build/src/old.dart
    to: package:flutter3d_particles/flutter3d_particles.dart
''';

void main() {
  final table = MigrationTable.parse(_table);

  group('the table', () {
    test('reads its packages and its entries', () {
      expect(table.from, '0.1.0');
      expect(table.constraintFor('flutter3d_core'), '^1.0.0');
      expect(table.constraintFor('pad_input'), '^0.5.0');
      expect(table.renamedPackages, <String, String>{
        'flutter3d_old': 'flutter3d_new',
      });
      expect(table.entries.map((MigrationEntry e) => e.kind), <String>[
        'rename',
        'moved',
        'rewrite',
        'manual',
        'import',
      ]);
      expect(table.entries[2].member, 'k');
      expect(table.entries[2].imports, <String>[
        'package:flutter3d_core/flutter3d_core.dart',
      ]);
      expect(
        table.linkFor(table.entries[0]),
        'https://example.dev/migrating/#core-Ab',
      );
    });

    test('owns the engine, its own-line packages, and nothing else', () {
      expect(table.owns('flutter3d'), isTrue);
      expect(table.owns('flutter3d_sim'), isTrue);
      expect(table.owns('flame_flutter3d'), isTrue);
      expect(table.owns('pad_input'), isTrue);
      expect(table.owns('flame'), isFalse);
      expect(table.owns('vector_math'), isFalse);
    });

    test('the shipped table parses, with one id per entry', () {
      final file = File('lib/migrations/0.8_to_1.0.yaml');
      final shipped = MigrationTable.parse(file.readAsStringSync());
      expect(shipped.from, '0.8.5');
      expect(shipped.entries, isNotEmpty);
      final ids = shipped.entries.map((MigrationEntry e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final e in shipped.entries) {
        expect(e.text, isNot(contains('TODO')), reason: e.id);
      }
    });
  });

  group('the pubspec', () {
    test('renames the plugin key and leaves what is under it', () {
      // Decision D. Mutation: rename every `flutter3d:` key — the dependency
      // on `flutter3d` becomes a dependency on a package that does not
      // exist.
      const pubspec = '''
name: my_plugins
dependencies:
  flutter3d: ^0.8.3
flutter3d:
  plugin:
    lib/my_plugins.dart: [GlowPlugin, FogPlugin]
''';
      final notes = <String>[];
      final moved = migratePubspec(pubspec, table, notes: notes);
      expect(moved, '''
name: my_plugins
dependencies:
  flutter3d: ^1.0.0
flutter3d_plugins:
  plugin:
    lib/my_plugins.dart: [GlowPlugin, FogPlugin]
''');
      expect(notes.single, contains('`flutter3d_plugins:` in 1.0'));
      // Run again, as `migrate` does after `dart fix`: nothing more moves.
      final again = <String>[];
      expect(migratePubspec(moved, table, notes: again), moved);
      expect(again, isEmpty);
    });

    test('leaves both plugin keys when a pubspec has both, and says so', () {
      // Mutation: rename anyway — the pubspec names `flutter3d_plugins:`
      // twice, which no YAML reader accepts.
      const pubspec = '''
name: app
flutter3d:
  plugin: lib/a.dart#A
flutter3d_plugins:
  exclude: [flutter3d_post]
''';
      final notes = <String>[];
      expect(migratePubspec(pubspec, table, notes: notes), pubspec);
      expect(notes.single, contains('both'));
    });

    test('moves version, map and bare constraints, and renames', () {
      const pubspec = '''
name: game
dependencies:
  flutter3d: ^0.8.3
  flutter3d_old: ^0.8.0
  flutter3d_sim:
    version: ^0.8.1
  pad_input:
  flame: ^1.38.2
dev_dependencies:
  flutter3d_cpu: ^0.8.0
''';
      final notes = <String>[];
      final moved = migratePubspec(pubspec, table, notes: notes);
      expect(moved, contains('flutter3d: ^1.0.0\n'));
      expect(moved, contains('flutter3d_new: ^1.0.0\n'));
      expect(moved, contains('    version: ^1.0.0\n'));
      expect(moved, contains('pad_input: ^0.5.0\n'));
      expect(moved, contains('flame: ^1.38.2\n'));
      expect(moved, contains('flutter3d_cpu: ^1.0.0\n'));
      expect(notes, isEmpty);
    });

    test('leaves a path dependency and says so; names a removed package', () {
      const pubspec = '''
name: game
dependencies:
  flutter3d:
    path: ../flutter3d
  flutter3d_gone: ^0.8.0
''';
      final notes = <String>[];
      final moved = migratePubspec(pubspec, table, notes: notes);
      expect(moved, pubspec);
      expect(notes, hasLength(2));
      expect(notes.first, contains('path'));
      expect(notes.last, contains('Use flutter3d_core.'));
    });

    test('two packages merged into one leave one entry for it', () {
      // Mutation: rename every key. The pubspec would name
      // `flutter3d_game_ui` twice, which no YAML reader accepts.
      // Mutation: end a removed entry where its value's span ends. A block
      // value (`path: ../touch`) runs to the next key, and `flame` goes too.
      final merged = MigrationTable.parse(
        _table.replaceFirst(
          '    flutter3d_old: flutter3d_new\n',
          '    flutter3d_old: flutter3d_new\n'
              '    flutter3d_addon_hud: flutter3d_game_ui\n'
              '    flutter3d_addon_touch: flutter3d_game_ui\n'
              '    flutter3d_addon_ghost: flutter3d_game_kit\n',
        ),
      );
      const pubspec = '''
name: game
dependencies:
  flutter3d_addon_hud: ^0.9.0
  flutter3d_addon_touch:
    path: ../touch
  flame: ^1.38.2
  flutter3d_game_kit: ^1.0.0-rc.1
  flutter3d_addon_ghost: ^0.9.0
dev_dependencies:
  flutter3d_addon_touch: ^0.9.0
''';
      final notes = <String>[];
      final moved = migratePubspec(pubspec, merged, notes: notes);
      expect(moved, '''
name: game
dependencies:
  flutter3d_game_ui: ^1.0.0
  flame: ^1.38.2
  flutter3d_game_kit: ^1.0.0
dev_dependencies:
''');
      expect(notes, hasLength(3));
      expect(notes.first, contains('`flutter3d_addon_touch` is part of'));
    });

    test('adds dependencies under their section', () {
      const pubspec = 'name: game\ndependencies:\n  flame: ^1.0.0\n';
      final added = addDependencies(pubspec, <String, String>{
        'flutter3d_core': '^1.0.0',
      });
      expect(
        added,
        'name: game\ndependencies:\n  flutter3d_core: ^1.0.0\n  flame: ^1.0.0\n',
      );
      expect(
        addDependencies('name: game\n', <String, String>{
          'flutter3d_cpu': '^1.0.0',
        }, section: 'dev_dependencies'),
        'name: game\n\ndev_dependencies:\n  flutter3d_cpu: ^1.0.0\n',
      );
    });
  });

  group('imports', () {
    test('moves whole URIs and renamed packages, nothing else', () {
      const source = '''
import 'package:flutter3d_build/src/old.dart';
import "package:flutter3d_old/flutter3d_old.dart" show A;
export 'package:flutter3d_old/src/b.dart';
import 'package:flame/flame.dart';
// import 'package:flutter3d_old/c.dart' — a comment, which stays.
''';
      final moved = migrateDirectives(
        source,
        uris: <String, String>{
          'package:flutter3d_build/src/old.dart':
              'package:flutter3d_particles/flutter3d_particles.dart',
        },
        packages: table.renamedPackages,
      );
      expect(
        moved,
        contains(
          "import 'package:flutter3d_particles/flutter3d_particles.dart';",
        ),
      );
      expect(
        moved,
        contains('import "package:flutter3d_new/flutter3d_old.dart" show A;'),
      );
      expect(moved, contains("export 'package:flutter3d_new/src/b.dart';"));
      expect(moved, contains("import 'package:flame/flame.dart';"));
      expect(moved, contains("// import 'package:flutter3d_old/c.dart'"));
      expect(
        referencedPackages(moved),
        containsAll(<String>['flutter3d_particles', 'flutter3d_new', 'flame']),
      );
    });

    test('a library merged into another package, and its src/ with it', () {
      // Mutation: try the package rename before the directory. `src/x.dart`
      // would land in the merged package's own `src/`, beside the files of
      // every other library it absorbed.
      const source = '''
import 'package:flutter3d_addon_hud/flutter3d_addon_hud.dart';
import 'package:flutter3d_addon_hud/src/mini_map.dart';
''';
      final moved = migrateDirectives(
        source,
        uris: <String, String>{
          'package:flutter3d_addon_hud/flutter3d_addon_hud.dart':
              'package:flutter3d_game_ui/hud.dart',
          'package:flutter3d_addon_hud/src/':
              'package:flutter3d_game_ui/src/hud/',
        },
        packages: <String, String>{'flutter3d_addon_hud': 'flutter3d_game_ui'},
      );
      expect(moved, '''
import 'package:flutter3d_game_ui/hud.dart';
import 'package:flutter3d_game_ui/src/hud/mini_map.dart';
''');
    });

    test('every URI of a conditional import moves, not just the first', () {
      // Mutation: match only the URI after `import`. The `if (dart.library…)`
      // ones keep naming a package the pubspec no longer has, and
      // `referencedPackages` never sees the one behind a relative stub.
      const source = '''
import 'package:flutter3d_old/stub.dart'
    if (dart.library.io) 'package:flutter3d_old/io.dart'
    if (dart.library.js_interop) "package:flutter3d_old/web.dart";
export 'src/stub.dart' if (dart.library.io) 'package:flutter3d_build/src/old.dart';
''';
      final moved = migrateDirectives(
        source,
        uris: <String, String>{
          'package:flutter3d_build/src/old.dart':
              'package:flutter3d_particles/flutter3d_particles.dart',
        },
        packages: table.renamedPackages,
      );
      expect(moved, '''
import 'package:flutter3d_new/stub.dart'
    if (dart.library.io) 'package:flutter3d_new/io.dart'
    if (dart.library.js_interop) "package:flutter3d_new/web.dart";
export 'src/stub.dart' if (dart.library.io) 'package:flutter3d_particles/flutter3d_particles.dart';
''');
      expect(referencedPackages(moved), <String>{
        'flutter3d_new',
        'flutter3d_particles',
      });
    });
  });

  group('fix data', () {
    const released = '''
library package:flutter3d/flutter3d.dart

final class Ab
  void f()

int ef(int x)

export package:flutter3d_core/flutter3d_core.dart (whole library)
  Gh
''';
    const now = '''
library package:flutter3d/flutter3d.dart

final class Cd
  void f()

library package:flutter3d_core/more.dart

int ef(int x)
''';

    test('a rename and a move, with the kinds the snapshot gives them', () {
      final out = generateFixData(
        <MigrationTable>[
          MigrationTable.parse(
            _table
                .replaceAll(
                  'package: flutter3d_core\n    symbol: Ab',
                  'package: flutter3d\n    symbol: Ab',
                )
                .replaceAll(
                  'package: flutter3d_core\n    symbol: ef',
                  'package: flutter3d\n    symbol: ef',
                ),
          ),
        ],
        released: <String, Map<String, String>>{
          '0.1.0': <String, String>{'flutter3d': released},
        },
        current: <String, String>{'flutter3d': now},
        stamp: 'abc',
      );
      expect(out.problems, isEmpty);
      final rename = out.files['flutter3d']!;
      expect(rename, contains("class: 'Ab'"));
      expect(rename, contains("newName: 'Cd'"));
      expect(rename, contains('table-stamp: abc'));
      final moved = out.files['flutter3d_core']!;
      expect(moved, contains("function: 'ef'"));
      expect(moved, contains("uris: ['package:flutter3d_core/more.dart']"));
    });

    test('kinds of declarations and members', () {
      expect(topLevelKind('abstract base mixin class A'), 'class');
      expect(topLevelKind('mixin M on A'), 'mixin');
      expect(topLevelKind('enum E'), 'enum');
      expect(topLevelKind('typedef T = int'), 'typedef');
      expect(topLevelKind('(double, double) jitter(int a, int b)'), 'function');
      expect(topLevelKind('final Vector4 kNeutral'), 'variable');
      expect(memberKind('static const T agxFull = T._(1)', 'T'), (
        'field',
        'agxFull',
      ));
      expect(memberKind('T.named({int x = 1})', 'T'), ('constructor', 'named'));
      expect(memberKind('bool get b', 'T'), ('getter', 'b'));
      expect(memberKind('void f<X>(X x)', 'T'), ('method', 'f'));
    });
  });

  group('the plugin table and the guide', () {
    test('a sealed type\'s new case reports the switches over it', () {
      final manual = table.entries[3];
      expect(inferMatch(manual), (match: 'switches', switchOver: 'Mn'));
      final source = generateLintsTable(<MigrationTable>[table], stamp: 's');
      expect(source, contains("switchOver: 'Mn'"));
      expect(source, contains('kind: MigrationKind.rewrite'));
      expect(source, isNot(contains("id: 'core-Ab'")));
    });

    test('the first sentence ends outside code', () {
      expect(firstSentence('Use `a.b`. Then c.'), 'Use `a.b`.');
    });

    test('the guide is spliced between its markers', () {
      final page = 'Before\n$guideStart\nold\n$guideEnd\nAfter\n';
      final table0 = generateGuideTable(<MigrationTable>[table]);
      final spliced = spliceGuide(page, table0)!;
      expect(spliced, startsWith('Before\n$guideStart'));
      expect(spliced, endsWith('$guideEnd\nAfter\n'));
      expect(spliced, contains('<a id="core-Ab"></a>'));
      expect(spliced, isNot(contains('old\n')));
      expect(spliceGuide('no markers', table0), isNull);
    });
  });

  group('the command line', () {
    Future<ProcessResult> migrate(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      <String>['bin/migrate.dart', ...args],
    );

    test('--help is an answer, on stdout, exiting 0', () async {
      // Mutation: answer --help as the usage error it shares a branch with
      // (stderr, exit 2), which is what `flutter3d migrate --help` did.
      for (final help in <String>['--help', '-h']) {
        final run = await migrate(<String>[help]);
        expect(run.exitCode, 0, reason: help);
        expect('${run.stdout}', contains('--dry-run'), reason: help);
        expect('${run.stderr}', isEmpty, reason: help);
      }
      final wrong = await migrate(const <String>[]);
      expect(wrong.exitCode, 2);
      expect('${wrong.stderr}', contains('--dry-run'));
    });
  });
}
