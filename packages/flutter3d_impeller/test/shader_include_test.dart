// What has to stay true for an extension package to build shaders of its own.
//
// An extension's material writes `#include <lib/color.glsl>` and asks impellerc
// to resolve it out of `<flutter3d>/shaders`. Two things can quietly break that,
// and neither shows up until somebody outside this repository tries to build:
//
//   * flutter3d stops shipping the headers, and the include resolves to nothing;
//   * the include root stops being findable, because it was written down as a
//     relative path that is only true for a path dependency.
//
// The first half of this file guards the shipping. The second half tests the
// resolver that replaces the written-down path, including against the exact
// shape of rootUri that the pub cache produces.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/package_root.dart';

/// `flutter test` runs with the package root as the working directory.
/// The package the GLSL lives in, which is no longer this one.
///
/// The sources moved to `flutter3d_shaders` when a second backend appeared and
/// they stopped belonging to either. The checks below are still run from here
/// because this is where the compiled bundle is built, and a header that fails
/// to ship breaks *this* package's build — but every path they take is over
/// there now.
///
/// Found by these tests failing after the move, which they did because the move
/// was verified with `flutter analyze` and not with `flutter test`. Analysis
/// does not open a directory.
Directory get _package =>
    Directory('${Directory.current.parent.path}/flutter3d_shaders');

void main() {
  group('shipped shader headers', () {
    test('every <lib/…> include has a file behind it', () {
      final includes = RegExp(r'#include\s+<([^>]+)>');
      final missing = <String>[];

      for (final entity in Directory(
        '${_package.path}/shaders',
      ).listSync(recursive: true).whereType<File>()) {
        if (!const {
          '.frag',
          '.vert',
          '.glsl',
        }.any((extension) => entity.path.endsWith(extension))) {
          continue;
        }
        for (final match in includes.allMatches(entity.readAsStringSync())) {
          final header = match.group(1)!;
          // Anything not under lib/ comes from the engine's own shader_lib,
          // which this package neither ships nor controls.
          if (!header.startsWith('lib/')) continue;
          if (!File('${_package.path}/shaders/$header').existsSync()) {
            missing.add('$header (from ${entity.path})');
          }
        }
      }

      expect(missing, isEmpty);
    });

    test('the headers are files pub will publish, not ignored ones', () {
      // The publish set for a git checkout is `git ls-files --cached --others
      // --exclude-standard`. Asking git directly is the only way to catch an
      // exclusion added in .gitignore or a .pubignore, which is exactly how
      // these files would silently stop reaching consumers.
      final result = Process.runSync('git', [
        'ls-files',
        '--cached',
        '--others',
        '--exclude-standard',
        'shaders',
      ], workingDirectory: _package.path);
      expect(result.exitCode, 0, reason: result.stderr.toString());

      final published = (result.stdout as String).split('\n').toSet();
      final headers = Directory('${_package.path}/shaders/lib')
          .listSync()
          .whereType<File>()
          .map((file) => 'shaders/lib/${file.uri.pathSegments.last}');

      expect(headers, isNotEmpty);
      for (final header in headers) {
        expect(
          published,
          contains(header),
          reason:
              '$header would not be in the published archive, so an '
              'extension installed from pub could not include it.',
        );
      }
    });

    test('no .pubignore hides the shaders directory', () {
      // A .pubignore, if one is ever added, replaces .gitignore for publishing
      // entirely — so the git check above would keep passing while the archive
      // lost the headers.
      expect(File('${_package.path}/.pubignore').existsSync(), isFalse);
    });
  });

  group('bundle entry point names', () {
    // impellerc derives the Metal symbol from the shader's file basename, not
    // from the key in the bundle spec. Two fragment shaders called `tint.frag`
    // in different subdirectories both compile to `tint_fragment_main`, and
    // impellerc does not warn — verified by hand against 3.44.6. The bundle then
    // holds two entries that name one function.
    test('no two shaders of one stage share a basename', () {
      final spec =
          jsonDecode(
                File(
                  '${_package.path}/shaders/flutter3d.shaderbundle.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;

      final seen = <String, String>{};
      spec.forEach((key, value) {
        final entry = value! as Map<String, Object?>;
        final stage = entry['type']! as String;
        final basename = (entry['file']! as String).split('/').last;
        final symbol = '$stage:$basename';

        expect(
          seen,
          isNot(contains(symbol)),
          reason:
              'bundle keys "$key" and "${seen[symbol]}" both compile to the '
              'same entry point, because their files share the basename '
              '"$basename".',
        );
        seen[symbol] = key;
      });
    });
  });

  group('package_root', () {
    test('climbs to the workspace package config', () {
      // flutter3d has no .dart_tool of its own: under a pub workspace there is
      // one config, at the repository root.
      final config = findPackageConfig(_package.path);
      expect(config, isNotNull);
      expect(
        File('${_package.path}/.dart_tool/package_config.json').existsSync(),
        isFalse,
      );
    });

    test('resolves this package to a directory that has the headers', () {
      // `flutter3d_shaders`. The headers were this package's while it was the
      // only backend; they belong to neither now, and both compile them. An
      // extension writing shaders includes them through that package name,
      // which is also how the build script resolves its include root.
      final config = findPackageConfig(_package.path)!;
      final root = packageRoot(config, 'flutter3d_shaders');
      expect(File('$root/shaders/lib/color.glsl').existsSync(), isTrue);
    });

    test('resolves an absolute pub-cache rootUri, percent-encoding and all', () {
      // The shape pub writes for a hosted dependency. The escaped space is the
      // reason this is a URI resolution and not a string concatenation.
      final temporary = Directory.systemTemp.createTempSync('package_root');
      addTearDown(() => temporary.deleteSync(recursive: true));

      final cache = Directory('${temporary.path}/pub cache/flutter3d-0.1.0')
        ..createSync(recursive: true);
      final dartTool = Directory('${temporary.path}/.dart_tool')..createSync();
      final config = File('${dartTool.path}/package_config.json')
        ..writeAsStringSync(
          jsonEncode({
            'configVersion': 2,
            'packages': [
              {
                'name': 'flutter3d',
                'rootUri':
                    'file://${Uri.encodeFull(temporary.path)}'
                    '/pub%20cache/flutter3d-0.1.0',
                'packageUri': 'lib/',
              },
            ],
          }),
        );

      expect(packageRoot(config, 'flutter3d'), cache.path);
    });

    test('resolves a relative rootUri against .dart_tool, not the root', () {
      // Workspace and path dependencies arrive as `../packages/foo`. Resolving
      // that against the repository root instead of against `.dart_tool/` puts
      // the answer one directory too high, which is the kind of bug that still
      // finds a plausible-looking directory.
      final temporary = Directory.systemTemp.createTempSync('package_root');
      addTearDown(() => temporary.deleteSync(recursive: true));

      final target = Directory('${temporary.path}/packages/foo')
        ..createSync(recursive: true);
      final dartTool = Directory('${temporary.path}/.dart_tool')..createSync();
      final config = File('${dartTool.path}/package_config.json')
        ..writeAsStringSync(
          jsonEncode({
            'configVersion': 2,
            'packages': [
              {
                'name': 'foo',
                'rootUri': '../packages/foo',
                'packageUri': 'lib/',
              },
            ],
          }),
        );

      // Compared unresolved: packageRoot does URI resolution and nothing else,
      // so it hands back the path pub recorded rather than one with symlinks
      // chased. On macOS that is the difference between /var and /private/var.
      expect(packageRoot(config, 'foo'), target.path);
    });

    test('an unresolved package is an error, not an empty path', () {
      final config = findPackageConfig(_package.path)!;
      expect(
        () => packageRoot(config, 'no_such_package'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
