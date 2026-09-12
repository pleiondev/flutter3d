import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

/// A quad's own seven-float-per-vertex bytes — `x, y, z, r, g, b, a` — the
/// same interleaved shape [pass_coverage_checks.dart]'s own quads use.
Float32List _quad(double left, double right) => Float32List.fromList(<double>[
  left, -1, 0.5, 0, 1, 0, 1, //
  right, -1, 0.5, 0, 1, 0, 1,
  right, 1, 0.5, 0, 1, 0, 1,
  left, 1, 0.5, 0, 1, 0, 1,
]);

final Uint16List _quadIndices = Uint16List.fromList(<int>[0, 1, 2, 0, 2, 3]);

/// Draws [vertices] (already bound) into a fresh target and reads it back.
Future<Uint8List> _drawQuad(
  GraphicsDevice device,
  ShaderHandle vertex,
  ShaderHandle fragment,
  GeometryBuffer vertices,
) async {
  const size = 16;
  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4.zero(),
        ),
      ],
    ),
  );
  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(device.createPipeline(vertex, fragment))
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexBuffer(vertices, 4)
    ..bindIndexData(ByteData.sublistView(_quadIndices), IndexType.int16, 6)
    ..draw();
  pass.submit();

  final pixels = await device.readPixels(target);
  require(pixels != null, 'the target could not be read back');
  return pixels!.buffer.asUint8List();
}

/// `GraphicsDevice.overwriteGeometry` on a vertex buffer, then a draw with
/// it, comes back the same as a fresh upload of the overwritten bytes would
/// — `view-14`'s own acceptance clause, word for word.
///
/// **A left quad overwritten into a right one, rather than a colour or a
/// count.** Position is what a caller actually moves with this call —
/// sculpting, cloth, a skinned pose baked back to rest — so the picture has
/// to move, not merely change shade, or a backend that quietly ignored the
/// new bytes and kept drawing the old ones would still pass.
Future<void> checkGeometryOverwriteMatchesFreshUpload(
  GraphicsDevice device,
) async {
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(
    vertex != null && fragment != null,
    'the debug-line stages are missing, so this cannot draw anything',
  );

  final left = _quad(-1, 0);
  final right = _quad(0, 1);

  final overwritten = device.uploadGeometry(
    ByteData.sublistView(left),
    GeometryUsage.vertices,
  );
  // Visible starting the next pass — draw once on the original bytes first,
  // so a backend that only ever drew the very first upload cannot pass by
  // coincidence.
  final before = await _drawQuad(device, vertex!, fragment!, overwritten);
  int green(Uint8List rgba, int x, int y) => rgba[((y * 16 + x) * 4) + 1];
  require(
    green(before, 4, 8) > 128 && green(before, 12, 8) < 128,
    'the quad drawn before any overwrite did not paint the left half and '
    'leave the right half clear — nothing here overwrote anything yet',
  );

  device.overwriteGeometry(overwritten, 0, ByteData.sublistView(right));
  final afterOverwrite = await _drawQuad(
    device,
    vertex,
    fragment,
    overwritten,
  );

  final fresh = device.uploadGeometry(
    ByteData.sublistView(right),
    GeometryUsage.vertices,
  );
  final freshDraw = await _drawQuad(device, vertex, fragment, fresh);

  require(
    green(afterOverwrite, 4, 8) < 128 && green(afterOverwrite, 12, 8) > 128,
    'after overwriteGeometry moved the quad to the right half, the left '
    'half still painted and the right half did not — the overwrite was not '
    'visible to the next pass',
  );
  require(
    afterOverwrite.length == freshDraw.length &&
        _sameBytes(afterOverwrite, freshDraw),
    'a partial overwrite and a fresh upload of the identical bytes drew '
    'different pictures — the overwrite reached the device, but not '
    'faithfully',
  );
}

bool _sameBytes(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
