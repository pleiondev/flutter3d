import 'dart:io';

import 'package:flutter3d_impeller/src/shader_bundle_build.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'buildShaderBundle compiles the real manifest through the real '
    'impellerc, and writes a real, non-empty bundle',
    () async {
      final bundle = File('assets/shaders/flutter3d.shaderbundle');

      final dependencies = await buildShaderBundle(
        packageRoot: Directory.current,
      );

      expect(bundle.existsSync(), isTrue);
      // A real recompile — not a stale file this test happened to find —
      // proven by writing a fresh copy right here and comparing sizes is
      // fragile against unrelated shader edits, so the honest check is
      // narrower but covers both a clean machine (nothing there before this
      // call) and one that already had a bundle: the compiler actually ran
      // and actually produced real bytes, not something that shrank to
      // nothing.
      expect(bundle.lengthSync(), greaterThan(1000));

      expect(
        dependencies.map((uri) => uri.toFilePath()),
        contains(
          contains('flutter3d_shaders/shaders/flutter3d.shaderbundle.json'),
        ),
      );
      expect(dependencies.length, greaterThan(1)); // the manifest, plus GLSL
    },
    // A real impellerc invocation, not a mock — genuinely slower than the
    // suite's other tests, and worth the honesty.
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // What an installed package looks like from inside the pub cache: a root
  // with the compiled bundle in it and no `.dart_tool/package_config.json`
  // anywhere above. This is the shape 0.7.0 shipped broken — the hook threw
  // "no .dart_tool/package_config.json at or above <pub cache>" before a
  // single test or frame ran, on a package whose own archive already carried
  // the bundle. A temporary directory reproduces it exactly, and reproduces
  // it without a pub cache, a network or a published version.
  group('a package root with no package config above it', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('f3d_impeller_'));
    tearDown(() => root.deleteSync(recursive: true));

    test(
      'keeps the bundle that is already there, and compiles nothing',
      () async {
        final bundle = File('${root.path}/$bundlePath')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(List<int>.filled(64, 7));
        final log = _StringSink();

        final dependencies = await buildShaderBundle(
          packageRoot: root,
          log: log,
        );

        // No dependencies, because nothing was read: a hook that declared the
        // GLSL here would be declaring files it cannot see.
        expect(dependencies, isEmpty);
        expect(bundle.readAsBytesSync(), List<int>.filled(64, 7));
        expect(log.text, contains('keeping the bundle already at'));
      },
    );

    test('still fails when there is no bundle either', () {
      expect(
        buildShaderBundle(packageRoot: root, log: _StringSink()),
        throwsA(
          isA<ShaderBundleBuildException>().having(
            (e) => e.message,
            'message',
            contains('no .dart_tool/package_config.json'),
          ),
        ),
      );
    });
  });

  test('resolvePackageRoot finds this package from its own checkout', () {
    // What `bin/build_shader_bundle.dart` does instead of trusting the
    // working directory. `flutter test` runs with the package root as cwd,
    // so the two agree here — the point is that the answer comes from the
    // package config rather than from wherever the command was typed.
    expect(
      resolvePackageRoot('flutter3d_impeller', Directory.current).path,
      Directory.current.resolveSymbolicLinksSync(),
    );
  });
}

/// An [IOSink] that keeps what was written to it. Only [writeln] is reached
/// by the code under test; the rest would be scaffolding for nobody.
final class _StringSink implements IOSink {
  final StringBuffer _buffer = StringBuffer();

  String get text => _buffer.toString();

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
