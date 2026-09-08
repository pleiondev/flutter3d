/// This backend, held to what flutter3d_hardware requires.
///
///     flutter test --platform chrome test/conformance_test.dart
///
/// **A test and not a script, which is the WebGL2 backend's answer rather than
/// the Impeller one.** Flutter GPU needs Impeller, and a headless `flutter test`
/// does not enable it, so that backend runs the same list from an application
/// driven by `tool/conformance.sh`. Nothing of the sort is needed here: Chrome
/// has a real WebGPU device inside `flutter test --platform chrome`, so the
/// checks run where every other test in this package runs and fail in the same
/// place.
///
/// **The device is opened with an `await`, which no other backend needs.**
/// `requestAdapter` and `requestDevice` are both promises, so `DeviceFactory`
/// returns a `FutureOr` — see the note on it, and the harness that awaits it.
///
/// ## What this backend declines, and why each is a refusal rather than a gap
///
/// Four of the checks are answered "I cannot be asked this", and the device
/// says so through a capability before the check ever draws:
///
///  1. **A cube to render into, and a mip to render into** —
///     `supportsRenderToMip` is false and `createCubeRenderTarget` answers
///     null. Nothing in this API makes either hard; a probe needs both, and the
///     two arrive together or neither is worth having.
///  2. **A compressed format** — `create` requests none of the three
///     compression families, so `supportsTextureFormat` answers false for every
///     block-compressed layout and a loader leaves such a texture out with a
///     reason. Sampling one on a device that did not ask for the feature is a
///     validation error, not a slow path.
///  3. **A blend constant** — `supportsBlendColor` is false because two of the
///     four constant-reading `BlendFactor` values have no spelling in WebGPU at
///     all. The capability is one answer for all four, so the honest answer
///     loses the two it could have had.
///
/// **Cube *textures* are not among them and must not become one.** The sky pass
/// samples a cube, `supportsCubeTextures` answers true, and two checks here —
/// the mip chain a cube is handed, and the face a direction points at — are the
/// ones that say so.
@TestOn('browser')
library;

import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/engine_shaders.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  runDeviceConformance(
    backend: 'webgpu',
    makeDevice: ({required int width, required int height}) async {
      final device = await WebGpuDevice.create(
        width: width,
        height: height,
        stages: engineShaders,
      );
      if (device == null) fail('no WebGPU device in this browser');
      return device;
    },
    // The same stages the device was built with, as the section a packed bundle
    // would carry. No SDK: the section is WGSL text the browser compiles, so
    // there is no ahead-of-time artefact for a Flutter version to have moved —
    // which is what `ShaderBundle.webgpuSection` says, and why
    // `webgpu_loaded_shaders.dart` versions the document instead.
    ownShaders: () async => (
      id: ShaderBundle.webgpuSection,
      bytes: encodeWebGpuSection(
        vertex: engineShaders.vertex,
        fragment: engineShaders.fragment,
      ),
      sdk: '',
    ),
  );
}
