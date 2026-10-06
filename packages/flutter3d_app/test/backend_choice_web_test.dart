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
/// thing that is new — which browser backend an ordinary web build draws
/// through. WebGPU since 0.9.0, WebGL2 where a build passes
/// `FLUTTER3D_WEBGPU=false`; run it both ways:
///
///     flutter test --platform chrome test/backend_choice_web_test.dart
///     flutter test --platform chrome --dart-define=FLUTTER3D_WEBGPU=false \
///         test/backend_choice_web_test.dart
///
/// A decision with nothing holding it is a default that moves.
@TestOn('browser')
library;

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart' show WebGpuDevice;
import 'package:flutter_test/flutter_test.dart';

const bool _webGpuAsked = bool.fromEnvironment(
  'FLUTTER3D_WEBGPU',
  defaultValue: true,
);

void main() {
  test('a web build opens WebGPU first, and WebGL2 when told not to', () async {
    // Named rather than merely counted as a `GraphicsDevice`, because *which*
    // one is the whole assertion. Chrome under `flutter test` hands out a real
    // WebGPU adapter, so with nothing asked the device that arrives is
    // WebGPU's; with the probe compiled out, WebGL2's. The fallback wired the
    // wrong way round, or the default moved back, fails one run or the other.
    final device = await openDevice(width: 32, height: 24);

    expect(device, _webGpuAsked ? isA<WebGpuDevice>() : isA<WebGlDevice>());
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
