import 'dart:io';

import 'package:api_snapshot/api_snapshot.dart';
import 'package:test/test.dart';

import '../../structure/api.dart';

/// A throwaway repository: a workspace pubspec and the packages given, each a
/// map of path under the package to source.
Directory _repository(Map<String, Map<String, String>> packages) {
  final root = Directory.systemTemp.createTempSync('api_snapshot');
  addTearDown(() => root.deleteSync(recursive: true));
  File(
    '${root.path}/pubspec.yaml',
  ).writeAsStringSync('name: flutter3d_workspace\n');
  for (final package in packages.entries) {
    final dir = '${root.path}/packages/${package.key}';
    Directory(dir).createSync(recursive: true);
    File('$dir/pubspec.yaml').writeAsStringSync('name: ${package.key}\n');
    for (final file in package.value.entries) {
      File('$dir/${file.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(file.value);
    }
  }
  return root;
}

String _snapshot(Map<String, Map<String, String>> packages, String of) {
  final root = _repository(packages);
  return ApiSnapshotter(repositoryPackages(root)).snapshot(of);
}

void main() {
  test('every published package commits the snapshot its source makes', () {
    // Mutation: add a member to any public type, or rename a parameter, and
    // this fails naming the package — the same check the structure rule
    // runs, here so `dart test` in tool/api says it too.
    final root = repositoryRootFrom(Directory.current);
    final packages = repositoryPackages(root);
    final snapshotter = ApiSnapshotter(packages);
    final stale = <String>[
      for (final name in packages.keys)
        if (isPublished(packages[name]!))
          if (File(
                '${packages[name]!.path}/${snapshotPathOf(name)}',
              ).existsSync()
              ? File(
                      '${packages[name]!.path}/${snapshotPathOf(name)}',
                    ).readAsStringSync() !=
                    snapshotter.snapshot(name)
              : true)
            name,
    ];
    expect(stale, isEmpty, reason: 'run `dart run api_snapshot --update`');
  });

  test('a reformat or a reworded doc comment does not move the snapshot', () {
    // Mutation: drop the whitespace normalisation, or keep comments, and a
    // doc-only edit would demand a version decision nobody needs to make.
    String of(String body) => _snapshot(<String, Map<String, String>>{
      'p': <String, String>{
        'lib/p.dart': "export 'src/a.dart';\n",
        'lib/src/a.dart': body,
      },
    }, 'p');

    final before = of(
      '/// One.\nabstract interface class A {\n  void f(int x, {int y = 1});\n}\n',
    );
    expect(
      of(
        '/// Two, reworded.\nabstract interface class A {\n'
        '  // a note\n  void f(\n    int x, {\n    int y = 1,\n  });\n}\n',
      ),
      before,
    );
    expect(
      of('abstract interface class A {\n  void f(int x, {int y = 2});\n}\n'),
      isNot(before),
    );
  });

  test('modifiers, annotations and bodiless members are written down', () {
    // Mutation: drop the metadata, or the `abstract ` marker, and the
    // classifier can no longer tell a deprecation, a @protected member or a
    // new obligation on a subclass from nothing at all.
    final text = _snapshot(<String, Map<String, String>>{
      'p': <String, String>{
        'lib/p.dart':
            "import 'package:meta/meta.dart';\n"
            'abstract base class Base {\n'
            '  void hook();\n'
            '  @protected\n'
            '  void helper() {}\n'
            "  @Deprecated('Use hook. Deprecated in 1.0.0, removed in 2.0.0.')\n"
            '  void old() {}\n'
            '  @override\n'
            '  String toString() => "";\n'
            '}\n'
            'sealed class Shape {}\n'
            'final class _Hidden {}\n',
      },
    }, 'p');
    expect(text, contains('abstract base class Base\n'));
    expect(text, contains('  abstract void hook()\n'));
    expect(text, contains('  @protected void helper()\n'));
    expect(
      text,
      contains(
        "  @Deprecated('Use hook. Deprecated in 1.0.0, removed in 2.0.0.') "
        'void old()\n',
      ),
    );
    expect(text, contains('  String toString()\n'));
    expect(text, contains('sealed class Shape\n'));
    expect(text, isNot(contains('_Hidden')));
  });

  test('a whole-package re-export names its origin and every name', () {
    // Mutation: list only the package's own declarations, and `flutter3d`
    // dropping the core's re-export — every name a caller had — would leave
    // its snapshot unchanged.
    final text = _snapshot(<String, Map<String, String>>{
      'outer': <String, String>{
        'lib/outer.dart':
            "export 'package:inner/inner.dart';\n"
            "export 'package:vector_math/vector_math_64.dart' show Vector3;\n"
            'final class Own {}\n',
      },
      'inner': <String, String>{
        'lib/inner.dart':
            "export 'package:deepest/deepest.dart' show Deep;\n"
            'final class Inner {}\n',
      },
      'deepest': <String, String>{
        'lib/deepest.dart': 'final class Deep {}\nfinal class Hidden {}\n',
      },
    }, 'outer');
    expect(text, contains('final class Own\n'));
    expect(
      text,
      contains(
        'export package:inner/inner.dart (whole library)\n'
        '  Deep from deepest\n'
        '  Inner\n',
      ),
    );
    expect(text, isNot(contains('Hidden')));
    expect(
      text,
      contains(
        'export package:vector_math/vector_math_64.dart show Vector3 '
        '(outside this repository)\n',
      ),
    );
  });

  test('a library and its classifier agree on what moved', () {
    // Mutation: key a member by its whole line instead of its name, and a
    // renamed parameter reads as one member gone and one new, which happens
    // to be the right bump for the wrong reason; this pins the reason.
    String of(String body) => _snapshot(<String, Map<String, String>>{
      'p': <String, String>{'lib/p.dart': body},
    }, 'p');
    final changes = classifyApi(
      of('final class A {\n  void f(int x) {}\n}\n'),
      of('final class A {\n  void f(int y) {}\n}\n'),
    );
    expect(changes.single.bump, Bump.major);
    expect(changes.single.what, startsWith('A.f changed'));
  });
}
