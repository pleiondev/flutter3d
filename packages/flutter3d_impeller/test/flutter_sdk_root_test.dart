/// `flutterSdkRootFrom` names the Flutter SDK root under every executable
/// shape this package has actually seen it run under.
///
/// **A real regression, not a hypothetical.** The two markers here used to
/// match forward slashes only, which is every shape `Platform
/// .resolvedExecutable` takes on macOS and Linux — and none of the shapes it
/// takes on Windows, where the path uses backslashes and both `dart` and
/// `flutter_tester` carry a `.exe` suffix. A hook that throws
/// `ShaderBundleBuildException` on every Windows build is not a build that
/// occasionally gets the root wrong; it is one that never gets past this
/// function at all.
library;

import 'package:flutter3d_impeller/src/shader_bundle_build.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a POSIX Flutter-bundled Dart SDK path names its own root', () {
    expect(
      flutterSdkRootFrom('/Users/dev/flutter/bin/cache/dart-sdk/bin/dart'),
      '/Users/dev/flutter',
    );
  });

  test('a POSIX flutter_tester path names the SDK root above the engine', () {
    expect(
      flutterSdkRootFrom(
        '/Users/dev/flutter/bin/cache/artifacts/engine/darwin-x64/'
        'flutter_tester',
      ),
      '/Users/dev/flutter',
    );
  });

  test('a Windows dart.exe path names its own root, backslashes and all', () {
    // Mutation: match only the forward-slash marker. GitHub's own
    // windows-latest runner exposes exactly this shape, and the old code
    // threw on it rather than resolving it.
    expect(
      flutterSdkRootFrom(r'C:\flutter\bin\cache\dart-sdk\bin\dart.exe'),
      r'C:\flutter',
    );
  });

  test(
    'a Windows flutter_tester.exe path names the SDK root above the engine',
    () {
      expect(
        flutterSdkRootFrom(
          r'C:\flutter\bin\cache\artifacts\engine\windows-x64\'
          r'flutter_tester.exe',
        ),
        r'C:\flutter',
      );
    },
  );

  test('anything else is refused by name, not guessed at', () {
    expect(
      () => flutterSdkRootFrom('/usr/bin/dart'),
      throwsA(
        isA<ShaderBundleBuildException>().having(
          (e) => e.toString(),
          'message',
          contains('cannot find the Flutter SDK root'),
        ),
      ),
    );
  });
}
