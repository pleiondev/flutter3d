import 'dart:io';

import 'package:release_dashboard/release_dashboard.dart';
import 'package:test/test.dart';

void main() {
  group('caretCovers', () {
    test('before 1.0 the minor number is the breaking one', () {
      expect(caretCovers('^0.7.0', '0.7.0'), isTrue);
      expect(caretCovers('^0.7.0', '0.7.9'), isTrue);
      expect(caretCovers('^0.6.0', '0.7.0'), isFalse);
      expect(caretCovers('^0.7.0', '0.8.0'), isFalse);
    });

    test('a version below the floor is not admitted', () {
      expect(caretCovers('^0.7.2', '0.7.1'), isFalse);
    });

    test('from 1.0 the major number is the breaking one', () {
      expect(caretCovers('^1.2.0', '1.9.0'), isTrue);
      expect(caretCovers('^1.2.0', '2.0.0'), isFalse);
    });

    test('what is not a caret is not judged', () {
      expect(caretCovers('any', '0.7.0'), isNull);
      expect(caretCovers('>=0.7.0 <0.8.0', '0.7.0'), isNull);
    });
  });

  group('scanPackages', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('shelf_'));
    tearDown(() => root.deleteSync(recursive: true));

    void package(
      String name, {
      required String version,
      String? changelog,
      String deps = '',
    }) {
      Directory('${root.path}/packages/$name').createSync(recursive: true);
      File('${root.path}/packages/$name/pubspec.yaml').writeAsStringSync(
        'name: $name\nversion: $version\n'
        '${deps.isEmpty ? '' : 'dependencies:\n$deps'}',
      );
      if (changelog != null) {
        File(
          '${root.path}/packages/$name/CHANGELOG.md',
        ).writeAsStringSync('# Changelog\n\n## $changelog\n\nText.\n');
      }
    }

    test('a package that agrees with the shelf has no problems', () async {
      package('a', version: '0.7.0', changelog: '0.7.0');
      final snapshot = await scanPackages(
        root,
        release: '0.7.0',
        ownLine: const <String>{},
      );
      expect(snapshot.rows.single.problems, isEmpty);
    });

    test('names each reason a package would not publish', () async {
      package('a', version: '0.6.0', changelog: '0.5.0');
      package('b', version: '0.7.0', changelog: '0.7.0', deps: '  a: ^0.7.0\n');
      final snapshot = await scanPackages(
        root,
        release: '0.7.0',
        ownLine: const <String>{},
      );
      final a = snapshot.rows.firstWhere((r) => r.name == 'a');
      final b = snapshot.rows.firstWhere((r) => r.name == 'b');
      expect(a.problems, contains('is 0.6.0, and the shelf is 0.7.0'));
      expect(a.problems.any((p) => p.contains('starts at "0.5.0"')), isTrue);
      expect(
        b.problems.single,
        'asks a ^0.7.0, which does not admit its 0.6.0',
      );
    });

    test('a package on its own line is not held to the shelf number', () async {
      package('own', version: '0.4.1', changelog: '0.4.1');
      final snapshot = await scanPackages(
        root,
        release: '0.7.0',
        ownLine: const <String>{'own'},
      );
      expect(snapshot.rows.single.problems, isEmpty);
      expect(snapshot.shelf, isEmpty);
    });

    test('a directory with no pubspec is a ghost, not a package', () async {
      Directory(
        '${root.path}/packages/left_over/build',
      ).createSync(recursive: true);
      final snapshot = await scanPackages(
        root,
        release: '0.7.0',
        ownLine: const <String>{},
      );
      expect(snapshot.rows, isEmpty);
      expect(snapshot.ghostDirectories, <String>['left_over']);
    });
  });
}
