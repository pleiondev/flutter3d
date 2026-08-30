/// Which directory each platform keeps a game's documents in.
///
///     flutter test test/storage_places_test.dart
///
/// **The table that was wrong.** Everything went under
/// `\$HOME/Library/Application Support`, which is right on macOS — a sandboxed
/// application's `HOME` *is* its container — and is nowhere on Android, where
/// the write went somewhere nothing reads and the failure was swallowed into
/// "no settings saved".
///
/// A pure function, and that is the point: while it was a `late final` reading
/// the real environment no test could reach it, and every platform but the one
/// under the developer's hands was a guess.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter3d_screens/src/storage/storage_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The table itself, as a pure function, because it is the part that was
  // wrong and the part no test could reach while it was a `late final` reading
  // the real environment.
  String? where(
    TargetPlatform platform, {
    Map<String, String> environment = const <String, String>{},
    String temporary = '/tmp',
  }) => applicationDirectory(
    appName: 'game',
    platform: platform,
    environment: environment,
    temporary: temporary,
  );

  test('macOS is inside the sandbox container, which is HOME', () {
    expect(
      where(
        TargetPlatform.macOS,
        environment: <String, String>{
          'HOME': '/Users/x/Library/Containers/g/Data',
        },
      ),
      '/Users/x/Library/Containers/g/Data/Library/Application Support/game',
    );
  });

  test('Android is beside its own files, not in a home that is not its', () {
    // **The bug.** `HOME` on Android is not the application's anything, so the
    // old path wrote where nothing was reading and the failure was swallowed.
    // `TMPDIR` is the application's cache directory, and its parent is the
    // private data directory `files/` sits in.
    expect(
      where(
        TargetPlatform.android,
        environment: <String, String>{'HOME': '/'},
        temporary: '/data/user/0/dev.flutter3d.platformer/cache',
      ),
      '/data/user/0/dev.flutter3d.platformer/files/game',
    );
  });

  test('and iOS is inside its container, found the same way', () {
    expect(
      where(
        TargetPlatform.iOS,
        temporary: '/var/mobile/Containers/Data/Application/ABC/tmp',
      ),
      '/var/mobile/Containers/Data/Application/ABC/'
      'Library/Application Support/game',
    );
  });

  test('Linux honours XDG_CONFIG_HOME, and falls back to .config', () {
    expect(
      where(
        TargetPlatform.linux,
        environment: <String, String>{'XDG_CONFIG_HOME': '/home/x/.cfg'},
      ),
      '/home/x/.cfg/game',
    );
    expect(
      where(
        TargetPlatform.linux,
        environment: <String, String>{'HOME': '/home/x'},
      ),
      '/home/x/.config/game',
    );
  });

  test('Windows uses APPDATA', () {
    expect(
      where(
        TargetPlatform.windows,
        environment: <String, String>{'APPDATA': r'C:\Users\x\AppData\Roaming'},
      ),
      r'C:\Users\x\AppData\Roaming\game',
    );
  });

  test('and a platform with nothing to go on answers nothing', () {
    // Null rather than a guess: a path invented out of an empty environment is
    // a document written somewhere nobody will look for it.
    expect(where(TargetPlatform.macOS), isNull);
    expect(where(TargetPlatform.linux), isNull);
    expect(where(TargetPlatform.fuchsia), isNull);
  });
}
