/// Multisampling, which is three fields of the HAL and no other check.
///
/// `RenderTargetSpec.sampleCount`, `ColorTarget.resolveTexture` and
/// `StoreAction.multisampleResolve` are all of it, and they are the kind of
/// thing a backend can get wrong without erring: an attachment allocated with
/// one sample, or a resolve that never runs, gives a picture with hard edges,
/// and hard edges read as a scene nobody asked to antialias rather than as a
/// backend that is broken.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

/// A multisample resolve actually resolves: an edge that is one colour or the
/// other without multisampling comes back blended with it.
///
/// **The three fields nothing held.** `RenderTargetSpec.sampleCount`,
/// `ColorTarget.resolveTexture` and `StoreAction.multisampleResolve` are the
/// whole of multisampling in this HAL, and until this check they were carried
/// by nothing: a backend that allocated the multisampled attachment and never
/// blitted it into the resolve target, or that quietly allocated a
/// single-sample one, produced a frame with hard edges — which reads as a
/// scene that was not multisampled rather than as a backend that is wrong.
///
/// Asked by counting rather than by naming a pixel, because where the partly
/// covered pixels are depends on the rasteriser's sample positions and those
/// are nobody's business but the driver's. What every multisampling backend
/// must produce is *some* of them along a slanted edge, and none at all when
/// the resolve is single-sampled: a byte that is neither the clear nor the draw
/// cannot exist without coverage having been averaged.
///
/// **Written to be run on a device by somebody who did not write it.** The
/// software rasteriser answers false to `supportsOffscreenMsaa`, and this
/// [decline]s there rather than returning — a check that passes without running
/// would tell a reader the software rasteriser resolves correctly, which is the
/// opposite of true. The line the harness prints names the backend and what it
/// answered.
///
/// Mutations watched go red, one per assertion:
///
///  * `WebGlEncoder.submit`, `continue` out of the resolve loop before the
///    blit — the resolve texture holds what it was allocated with, 0 covered
///    and 256 clear, and the first assertion says the pass never reached it;
///  * `webglCreateTexture`, the `spec.sampleCount > 1` branch skipped so the
///    attachment is a plain single-sample renderbuffer — 0 pixels of 256 come
///    back in between, and the second assertion says so.
///
/// Not a mutation, but worth knowing before writing one: passing `1` to
/// `renderbufferStorageMultisample` does *not* produce a single-sampled
/// attachment on ANGLE, which rounds it up to a count it supports. Thirteen
/// pixels still came back averaged. The allocation has to take the other
/// branch entirely.
Future<void> checkMultisampleResolveResolves(GraphicsDevice device) async {
  if (!device.supportsOffscreenMsaa) {
    decline(
      device,
      'answers false to supportsOffscreenMsaa: it has no multisampled '
      'offscreen target to resolve, so there is nothing here to ask it. A '
      'backend that answers true runs this check.',
    );
  }
  final samples = device.preferredSampleCount;
  if (samples < 2) {
    decline(
      device,
      'answers true to supportsOffscreenMsaa and $samples to '
      'preferredSampleCount, so the only target it would build is '
      'single-sampled and no resolve would happen.',
    );
  }

  const size = 16;
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(
    vertex != null && fragment != null,
    'the debug-line stages are missing, so this cannot draw an edge',
  );

  final multisampled = device.createTexture(
    RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
      sampleCount: samples,
      // Tile memory, which is what a multisampled attachment is for: nothing
      // reads it, the resolve target is what the next pass samples.
      storageMode: StorageMode.deviceTransient,
    ),
  );
  final resolved = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );

  // A hypotenuse from (1, −1) to (−1, 0.3): a slope that is not the pixel
  // grid's, so the edge crosses most rows part of the way through a pixel.
  final wedge = Float32List.fromList(<double>[
    -1, -1, 0.5, 1, 1, 1, 1, //
    1, -1, 0.5, 1, 1, 1, 1,
    -1, 0.3, 0.5, 1, 1, 1, 1,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: multisampled,
          resolveTexture: resolved,
          loadAction: LoadAction.clear,
          storeAction: StoreAction.multisampleResolve,
          clearValue: Vector4(0.0, 0.0, 0.0, 1.0),
        ),
      ],
    ),
  );
  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(device.createPipeline(vertex!, fragment!))
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(ByteData.sublistView(wedge), 3)
    ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
    ..draw();
  pass.submit();

  final read = await device.readPixels(resolved);
  require(read != null, 'the resolve target could not be read back');
  final bytes = read!.buffer.asUint8List();
  final reds = <int>[for (var i = 0; i < size * size; i++) bytes[i * 4]];
  final painted = reds.where((int r) => r >= 250).length;
  final clear = reds.where((int r) => r <= 5).length;
  final partial = reds.where((int r) => r > 5 && r < 250).length;

  require(
    painted > 0 && clear > 0,
    'the resolve target came back with $painted covered and $clear clear '
    'pixels of ${size * size} — a wedge covering rather less than half the '
    'frame should give plenty of each. Nothing of either means the pass never '
    'reached the resolve texture: the multisampled attachment was drawn into '
    'and StoreAction.multisampleResolve did not carry it across.',
  );
  require(
    partial >= 3,
    'every pixel of the resolve came back fully covered or fully clear '
    '($partial of ${size * size} in between), so the ${samples}x attachment '
    'was resolved as though it had one sample — or was allocated with one. A '
    'slanted edge over $size rows crosses a dozen pixels part way; each of '
    'those has to arrive averaged. See RenderTargetSpec.sampleCount and '
    'ColorTarget.resolveTexture.',
  );
}
