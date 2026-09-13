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

/// Draws [vertexCount] vertices of [vertices] (already bound), indexed by
/// [indices], into a fresh [size]-square target and reads it back.
Future<Uint8List> _draw(
  GraphicsDevice device,
  ShaderHandle vertex,
  ShaderHandle fragment,
  GeometryBuffer vertices,
  int vertexCount,
  Uint16List indices, {
  int size = 16,
}) async {
  final target = device.createTexture(
    RenderTargetSpec(
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
    ..bindVertexBuffer(vertices, vertexCount)
    ..bindIndexData(
      ByteData.sublistView(indices),
      IndexType.int16,
      indices.length,
    )
    ..draw();
  pass.submit();

  final pixels = await device.readPixels(target);
  require(pixels != null, 'the target could not be read back');
  return pixels!.buffer.asUint8List();
}

/// Draws a single quad (already bound) into a fresh target and reads it back.
Future<Uint8List> _drawQuad(
  GraphicsDevice device,
  ShaderHandle vertex,
  ShaderHandle fragment,
  GeometryBuffer vertices,
) => _draw(device, vertex, fragment, vertices, 4, _quadIndices);

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
  final afterOverwrite = await _drawQuad(device, vertex, fragment, overwritten);

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

/// One band's four vertices, at [left]..[right] in clip space, the full
/// height, in the colour [r], [g], [b] — the same seven-float-per-vertex
/// shape [_quad] uses.
Float32List _band(double left, double right, double r, double g, double b) =>
    Float32List.fromList(<double>[
      left, -1, 0.5, r, g, b, 1, //
      right, -1, 0.5, r, g, b, 1,
      right, 1, 0.5, r, g, b, 1,
      left, 1, 0.5, r, g, b, 1,
    ]);

/// Three quads' indices, back to back: `0..3` is the first quad's own
/// [_quadIndices] shape, `4..7` the second's, `8..11` the third's.
final Uint16List _threeBandIndices = Uint16List.fromList(<int>[
  for (var band = 0; band < 3; band++)
    for (final i in <int>[0, 1, 2, 0, 2, 3]) i + band * 4,
]);

/// `GraphicsDevice.overwriteGeometry` at a non-zero, non-final offset touches
/// only the bytes it was asked to, and refuses a write that would not fit —
/// `qa-11`'s own follow-on to `view-14`'s "partial overwrite draws what a
/// fresh upload draws": that check overwrites a whole buffer from offset
/// zero, which cannot tell a backend that copied to the right destination
/// from one that copied over the *entire* buffer, or one whose destination
/// arithmetic drifted by a few bytes into whatever sits next to it.
///
/// **Three bands, not two.** The middle one is overwritten; the left band
/// sits *before* the write in the buffer and the right band sits *after* it
/// — so a destination offset that lands short corrupts the left band's
/// trailing bytes, one that lands long corrupts the right band's leading
/// bytes, and only the correct offset leaves both alone while the middle
/// band changes colour. A two-band buffer (as [checkGeometryOverwriteMatchesFreshUpload]
/// uses) cannot distinguish "wrote to the whole buffer" from "wrote to the
/// right third of it".
///
/// **The bounds check is asked here too, not only on the software backend.**
/// `flutter3d_cpu`'s own unit tests already prove the CPU backend refuses an
/// out-of-range write; nothing before this exercised the same contract
/// through an actual GPU-backed buffer on WebGL2, WebGPU or Impeller.
Future<void> checkGeometryOverwriteLeavesNeighboursUntouched(
  GraphicsDevice device,
) async {
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(
    vertex != null && fragment != null,
    'the debug-line stages are missing, so this cannot draw anything',
  );

  // Thirds of an 18-pixel target land on whole pixel columns (0-5, 6-11,
  // 12-17), so the sample points below sit well clear of any edge a
  // rasteriser might antialias.
  const size = 18;
  const red = (1.0, 0.0, 0.0);
  const green = (0.0, 1.0, 0.0);
  const yellow = (1.0, 1.0, 0.0);
  const blue = (0.0, 0.0, 1.0);

  final bands = Float32List.fromList(<double>[
    ..._band(-1, -1 / 3, red.$1, red.$2, red.$3),
    ..._band(-1 / 3, 1 / 3, green.$1, green.$2, green.$3),
    ..._band(1 / 3, 1, yellow.$1, yellow.$2, yellow.$3),
  ]);
  final buffer = device.uploadGeometry(
    ByteData.sublistView(bands),
    GeometryUsage.vertices,
  );

  const bytesPerVertex = 7 * 4;
  const bytesPerBand = 4 * bytesPerVertex;
  require(
    buffer.lengthInBytes == 3 * bytesPerBand,
    'a buffer of three bands of four seven-float vertices should be '
    '${3 * bytesPerBand} bytes; the device made one of ${buffer.lengthInBytes}',
  );

  // The out-of-range write, checked before the real one touches anything:
  // starting where the right band's own bytes start, a write longer than
  // the buffer has left cannot fit no matter where it lands.
  var refused = false;
  try {
    device.overwriteGeometry(
      buffer,
      2 * bytesPerBand,
      ByteData(bytesPerBand * 2),
    );
  } on ArgumentError {
    refused = true;
  }
  require(
    refused,
    'an overwrite reaching past the end of the buffer was accepted rather '
    'than refused with an ArgumentError',
  );

  // The real write: the middle band only, at the offset where it starts —
  // neither zero nor the buffer's own length.
  device.overwriteGeometry(
    buffer,
    bytesPerBand,
    ByteData.sublistView(_band(-1 / 3, 1 / 3, blue.$1, blue.$2, blue.$3)),
  );

  final pixels = await _draw(
    device,
    vertex!,
    fragment!,
    buffer,
    12,
    _threeBandIndices,
    size: size,
  );
  (int, int, int) at(int x, int y) {
    final i = (y * size + x) * 4;
    return (pixels[i], pixels[i + 1], pixels[i + 2]);
  }

  final left = at(3, size ~/ 2);
  final middle = at(size ~/ 2, size ~/ 2);
  final right = at(size - 4, size ~/ 2);

  require(
    left.$1 > 128 && left.$2 < 128 && left.$3 < 128,
    'the left band, entirely before the overwritten bytes, reads back '
    '$left rather than red — the overwrite reached bytes before the '
    'offset it was given',
  );
  require(
    right.$1 > 128 && right.$2 > 128 && right.$3 < 128,
    'the right band, entirely after the overwritten bytes, reads back '
    '$right rather than yellow — the overwrite reached bytes past the '
    'range it was given',
  );
  require(
    middle.$3 > 128 && middle.$1 < 128 && middle.$2 < 128,
    'the middle band, exactly where the overwrite was aimed, reads back '
    '$middle rather than blue — the overwrite did not reach the bytes it '
    'was aimed at',
  );
}
