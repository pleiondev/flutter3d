/// The triangle, in a browser.
///
/// **Two things are being checked and they are worth telling apart.** That the
/// whole web half compiles at all — a `dart:js_interop` declaration that names a
/// method wrongly is a compile error, and a descriptor member the API refuses is
/// a `TypeError` from inside the browser, so this file is what makes both look.
/// And, where the browser running it has WebGPU, which winding WebGPU calls
/// front-facing — which is the one convention on the suspect list that no amount
/// of reading settles.
///
/// **A browser with no `navigator.gpu` reports rather than fails.** A headless
/// runner may have none, and a spike that found no GPU has established nothing
/// about the contract — saying so is the honest outcome, and failing would be a
/// red line about the machine rather than about the code.
@TestOn('browser')
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webgpu_spike/webgpu_spike_web.dart';

void main() {
  test('one triangle through the contract', () async {
    final result = await drawSpikeTriangle(cull: CullMode.none);
    if (!result.ran) {
      markTestSkipped('no WebGPU here: ${result.why}');
      return;
    }
    expect(
      result.centre,
      spikeTriangleColour,
      reason: 'the centre came back ${result.centre} rather than the triangle',
    );
    // The corner is outside it, so the clear reached and the readback is not
    // simply the triangle colour everywhere.
    expect(result.corner, spikeClearColour);
  });

  /// **The two-by-two, and it is the whole reason this spike draws anything.**
  ///
  /// The triangle is wound counter-clockwise in clip space, which is what every
  /// mesh in the engine is wound as. Four draws say which winding WebGPU calls
  /// front-facing: under `WindingOrder.counterClockwise` the triangle must
  /// survive back-face culling and be discarded by front-face culling, and under
  /// `WindingOrder.clockwise` the two must swap.
  ///
  /// Asked from both sides on purpose. A test that only checked "it survives
  /// back-face culling" would pass just as happily on a backend that had stopped
  /// culling altogether, which is the same picture and a different bug.
  test('which winding WebGPU calls front-facing', () async {
    Future<List<int>?> centre(WindingOrder winding, CullMode cull) async =>
        (await drawSpikeTriangle(cull: cull, winding: winding)).centre;

    final probe = await drawSpikeTriangle(cull: CullMode.none);
    if (!probe.ran) {
      markTestSkipped('no WebGPU here: ${probe.why}');
      return;
    }

    expect(
      await centre(WindingOrder.counterClockwise, CullMode.backFace),
      spikeTriangleColour,
      reason:
          'a clip-space counter-clockwise triangle was culled as a back face. '
          'That is the prediction the coordinate systems make — WebGPU measures '
          'in a framebuffer whose y runs down — and it is the one this draw '
          'exists to settle. If this is what happens, gpuFrontFace has to cross '
          'the two over after all.',
    );
    expect(
      await centre(WindingOrder.counterClockwise, CullMode.frontFace),
      spikeClearColour,
      reason: 'the same triangle was not discarded as a front face',
    );
    expect(
      await centre(WindingOrder.clockwise, CullMode.frontFace),
      spikeTriangleColour,
      reason:
          'with clockwise named as front-facing, the triangle is a back face '
          'and front-face culling must leave it alone',
    );
    expect(
      await centre(WindingOrder.clockwise, CullMode.backFace),
      spikeClearColour,
    );
  });

  test('a device that cannot be had is reported, not thrown', () async {
    // Whatever this browser is, `create` answers with a device or with null and
    // never throws — which is what lets whatever chooses a backend fall back.
    final device = await WebGpuSpikeDevice.create();
    device?.dispose();
  });
}
