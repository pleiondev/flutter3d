/// The choice this package exists to make, asked of it.
///
///     flutter test test/backend_choice_test.dart
///
/// **This package had no tests at all**, and `tool/ci.sh` skips a package with
/// none — so the file that decides which graphics API a build draws through was
/// touched by `flutter analyze` and by nothing else. Its failure mode is the
/// expensive kind: the wrong backend, on the wrong platform, at run time, on a
/// machine nobody has.
///
/// What can honestly be asserted here is the *shape* rather than the picture. A
/// VM test is the native half by construction, so the web half cannot be
/// exercised from the same run — what it can say is that the native half
/// resolves, hands back a real device, and answers the two questions an
/// application asks of it before it has drawn anything.
///
/// The web half is covered from the other side: `flutter3d_webgl`'s own suite
/// runs `--platform chrome`, and `tool/ci.sh` builds every game for the web
/// with `--wasm`, which is what would catch a conditional export that named a
/// file the browser cannot compile.
@TestOn('vm')
library;

import 'package:flutter3d_backend/flutter3d_backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the native half resolves and opens something that draws', () async {
    // On a headless `flutter test` this is the software rasteriser: Flutter GPU
    // needs Impeller, which a test runner does not enable, so `openDevice`'s
    // `try`/`catch` takes its second arm. That is the arm worth having a test
    // for — it is the one a player meets when a driver refuses Impeller, and
    // the one whose absence is a window that draws nothing.
    final device = await openDevice(width: 32, height: 24);

    expect(device, isA<GraphicsDevice>());
    expect(
      device.shaders,
      isNotNull,
      reason: 'a device with no shader library cannot draw a frame',
    );
    device.dispose();
  });

  test('and says whether it draws at a size the caller chose', () {
    // `kFixedResolution` is a compile-time constant, and the native file's own
    // doc admits the runtime software fallback invalidates it: a fallback frame
    // is drawn at a fixed size and this constant cannot know. Asserted as it
    // is rather than as it should be, so that the day it becomes a property of
    // the device instead, this test is what says the meaning changed.
    expect(kFixedResolution, isFalse);
  });
}
