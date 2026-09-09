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
/// **No check skips itself here any more, and the one that did is worth naming.**
/// `checkCompressedTextureSamples` asks `supportsTextureFormat` about a BC1, an
/// ETC2 and an ASTC block, and `continue`s past each one the device says no to —
/// a decline with nothing drawn behind it. `create` requested none of the three
/// compression families, so all three were `continue`d and that check ran empty.
/// The families are asked for now — the adapter's own set, intersected, because
/// asking for one it lacks rejects the device promise rather than answering with
/// a lesser device — so the check assembles a block of each family this adapter
/// carries and reads the colour back. On a machine with none of the three it
/// declines again, which is the honest outcome there rather than a regression
/// here.
///
/// **Two checks read a capability that is false and then assert a refusal, which
/// is a different thing from declining.** `checkBlendConstant` finds
/// `supportsBlendColor` false — two of the four constant-reading `BlendFactor`
/// values have no spelling in WebGPU at all, and the capability is one answer for
/// all four — and requires that both the setter and a `setBlend` naming the
/// factor throw, rather than painting a plausible picture.
/// `checkWireframeIsDrawnOrRefused` does the same with `supportsWireframe`: this
/// API has no polygon fill mode, so `setPolygonMode(PolygonMode.line)` has to
/// refuse loudly instead of filling the triangle. Those two are questions with
/// answers.
///
/// **The list was longer, and the entry that left it is worth remembering.**
/// Rendering into a cube face and into a level below the base used to sit at the
/// top of it, and the count of checks never moved when it went: the two mip
/// checks were *running* all along and declining themselves from inside, on
/// `supportsRenderToMip`. `checkRenderToCubeFaceAndMip` allocated one level
/// instead of two and asked only about the face; `checkPassViewportCoversTheLevel`
/// returned before it drew anything. So a suite reporting thirty-three of
/// thirty-three was reporting thirty-one questions and two shrugs, and the
/// device's own capability was what chose which. Both ask the whole question
/// now, at the same count, which is the shape a refusal has to be read with
/// care to see.
///
/// **Cube *textures* were never among them and must not become one.** The sky
/// pass samples a cube, `supportsCubeTextures` answers true, and two checks here
/// — the mip chain a cube is handed, and the face a direction points at — are
/// the ones that say so.
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
      // A decline rather than a failure, and the distinction is a CI runner:
      // headless Chrome there carries `navigator.gpu` and returns null from
      // `requestAdapter`, so a browser that looks like it has WebGPU hands out
      // no device. Nothing was asked of the backend on such a machine, and a
      // suite that failed thirty-three times over it was reporting the runner.
      if (device == null) {
        throw const ConformanceDeclined(
          'WebGpuDevice found no adapter in this browser: navigator.gpu is '
          'there and requestAdapter answered null',
        );
      }
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
