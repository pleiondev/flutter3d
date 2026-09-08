/// One triangle, drawn through `flutter3d_hardware` on WebGPU and read back.
///
/// **The smallest thing that can disagree with the contract.** It clears a
/// target, draws one indexed triangle with back-face culling on, and reads the
/// pixels back — so it exercises, in one go, the four conventions this spike was
/// written to check: where row zero is, which way clip depth runs, which winding
/// counts as front-facing, and whether a rectangle stated from the top left
/// needs turning over.
///
/// **The winding is the one that fails silently.** The triangle below is wound
/// counter-clockwise in clip space and drawn with `CullMode.backFace`. With
/// `gpuFrontFace` written straight through — `counterClockwise` to `"ccw"` — the
/// triangle is back-facing to WebGPU, the draw is discarded, and the readback
/// comes back the clear colour with no error anywhere. That is the whole reason
/// this is a drawing test and not a table of strings.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import 'webgpu_spike_device.dart';

/// What the triangle found.
final class SpikeTriangleResult {
  const SpikeTriangleResult({
    required this.ran,
    required this.why,
    this.centre,
    this.corner,
  });

  /// Whether there was a WebGPU device to draw on at all.
  ///
  /// False is the ordinary answer in a headless test runner, and it is reported
  /// rather than thrown: a spike that cannot find a GPU has established nothing
  /// and should say so, not fail as though the contract were wrong.
  final bool ran;

  /// What happened, in one sentence, whichever way [ran] went.
  final String why;

  /// The middle pixel, RGBA, where the triangle covers.
  final List<int>? centre;

  /// The top-left pixel, RGBA, where only the clear reaches.
  final List<int>? corner;
}

/// The clear colour: opaque green, so a triangle that never drew is
/// unmistakable.
const List<int> spikeClearColour = <int>[0, 255, 0, 255];

/// The triangle's colour: opaque red.
const List<int> spikeTriangleColour = <int>[255, 0, 0, 255];

/// Draws it, or says why it could not.
///
/// [cull] is a parameter so the winding can be asked about from both sides. The
/// triangle is wound counter-clockwise in clip space, so with
/// [CullMode.backFace] it must survive and with [CullMode.frontFace] it must
/// disappear — and a test that only asked the first would pass on a backend that
/// had switched culling off by accident.
Future<SpikeTriangleResult> drawSpikeTriangle({
  int size = 64,
  CullMode cull = CullMode.backFace,
  WindingOrder winding = WindingOrder.counterClockwise,
}) async {
  final device = await WebGpuSpikeDevice.create();
  if (device == null) {
    return const SpikeTriangleResult(
      ran: false,
      why:
          'this browser has no navigator.gpu, or no adapter answered — nothing '
          'about the contract was established here',
    );
  }

  try {
    final target = device.createTexture(
      RenderTargetSpec(
        width: size,
        height: size,
        format: device.defaultColorFormat,
      ),
    );

    final vertex = device.shaders['SpikeVertex']!;
    final fragment = device.shaders['SpikeFragment']!;
    final pipeline = device.createPipeline(
      vertex,
      fragment,
      // Stated rather than inferred, because on this API it cannot be inferred.
      layout: const VertexLayoutSpec(<BufferLayout>[
        BufferLayout(
          strideInBytes: 28,
          attributes: <InputAttribute>[
            InputAttribute(name: 'position', format: VertexFormat.float32x3),
            InputAttribute(
              name: 'colour',
              format: VertexFormat.float32x4,
              offsetInBytes: 12,
            ),
          ],
        ),
      ]),
    );

    // Counter-clockwise in clip space, with y up: bottom left, bottom right,
    // top middle. Big enough to cover the centre and to leave every corner to
    // the clear.
    const r = 1.0;
    const g = 0.0;
    const b = 0.0;
    const a = 1.0;
    final vertices = Float32List.fromList(<double>[
      -0.8, -0.8, 0.5, r, g, b, a, //
      0.8, -0.8, 0.5, r, g, b, a,
      0.0, 0.8, 0.5, r, g, b, a,
    ]);
    final indices = Uint16List.fromList(<int>[0, 1, 2]);

    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(
            texture: target,
            loadAction: LoadAction.clear,
            clearValue: Vector4(0.0, 1.0, 0.0, 1.0),
          ),
        ],
      ),
    );
    pass
      ..setViewport(ScreenRect(width: size, height: size))
      ..setScissor(ScreenRect(width: size, height: size))
      ..setPrimitiveType(PrimitiveType.triangle)
      // The assertion. A front face here is a triangle wound
      // counter-clockwise in clip space, and WebGPU measures the other way up.
      ..setCullMode(cull)
      ..setWindingOrder(winding)
      ..bindPipeline(pipeline)
      ..bindVertexData(ByteData.sublistView(vertices), 3)
      ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
      ..draw();
    pass.submit();

    final pixels = (await device.readback(target)).buffer.asUint8List();
    List<int> at(int x, int y) {
      final i = (y * size + x) * 4;
      return <int>[pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]];
    }

    return SpikeTriangleResult(
      ran: true,
      why: 'one triangle drawn and read back',
      centre: at(size ~/ 2, size ~/ 2),
      corner: at(0, 0),
    );
  } finally {
    device.dispose();
  }
}
