/// The same two questions, asked of the browser half.
///
///     flutter test --platform chrome test/backend_choice_web_test.dart
///
/// **The web half could not be asked from the VM run, and said so.** Its
/// companion file explains that a VM test *is* the native half by construction,
/// and left the browser side to be covered "from the other side" — by
/// `flutter3d_webgl`'s own suite and by the games' web builds. That covered the
/// backend; it did not cover the choice. Nothing anywhere ran the four lines in
/// `backend_web.dart` that decide which browser backend a build opens, and the
/// day a second browser backend arrived those four lines stopped being obvious.
///
/// So: a browser run, over the same shape the VM test asserts, plus the one
/// thing that is new — that an ordinary web build still draws through WebGL2.
/// That is a decision rather than an accident, and a decision with nothing
/// holding it is a default that moves.
@TestOn('browser')
library;

import 'package:flutter3d_backend/flutter3d_backend.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a web build with nothing asked of it opens WebGL2', () async {
    // Named rather than merely counted as a `GraphicsDevice`, because *which*
    // one is the whole assertion. `FLUTTER3D_WEBGPU` is off unless a build
    // passes it, and this is what says so: with the probe on, or with the
    // fallback wired the wrong way round, the device that arrives here is a
    // `WebGpuDevice` on a machine that has WebGPU and an exception on one that
    // does not — and both of those are a failure rather than a different
    // picture.
    final device = await openDevice(width: 32, height: 24);

    expect(device, isA<WebGlDevice>());
    expect(
      device.shaders,
      isNotNull,
      reason: 'a device with no shader library cannot draw a frame',
    );
    device.dispose();
  });

  test('and says it draws at a size the caller chose', () {
    // The opposite of the native half's answer, and for a reason that is a
    // property of the backend rather than a preference: a WebGL canvas resets
    // its drawing buffer when it is resized, so the frame is drawn at one size
    // and stretched to the layout by CSS.
    expect(kFixedResolution, isTrue);
  });
}
