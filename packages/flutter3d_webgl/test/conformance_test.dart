/// This backend, held to what flutter3d_hardware requires.
///
///     flutter test --platform chrome test/conformance_test.dart
///
/// Chrome only: there is no WebGL on the Dart VM. Three of these checks
/// describe behaviour this backend got wrong — the clear's extent, the row
/// order, and the buffer's declared use — each of which produced a
/// correct-looking frame with the wrong content.
@TestOn('browser')
library;

import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/compile.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  runDeviceConformance(
    backend: 'webgl',
    makeDevice: ({required int width, required int height}) {
      final device = WebGlDevice.open(
        width: width,
        height: height,
        sources: webGlEngineShaders,
      );
      return device;
    },
    // The same sources the device was built with, as the section a packed
    // bundle would carry. No SDK: the section is text the browser compiles.
    ownShaders: () async => (
      id: ShaderBundle.webglSection,
      bytes: encodeWebGlSection(
        vertex: webGlEngineShaders.vertex,
        fragment: webGlEngineShaders.fragment,
      ),
      sdk: '',
    ),
  );
}
