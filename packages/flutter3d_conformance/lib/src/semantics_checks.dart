/// Two rules from the backend contract that a signature cannot state, and that
/// nothing in this suite was asking about.
///
/// ARCHITECTURE.md §7.2 enumerates nine of these — "a backend that gets one of
/// these wrong compiles and draws the wrong thing" — and three had checks. The
/// two here are the ones a *new* backend is most likely to get wrong, because
/// both are decisions somebody has to make deliberately and neither produces an
/// error when made the other way.
///
/// Deliberately not here: the vertex-attribute divisor. It has its own test in
/// `flutter3d_webgl`, and that file's own argument for staying out of this
/// suite holds — a sticky divisor is a property of a context-based backend, and
/// a check the other two pass by construction says nothing about them while
/// suggesting the risk is covered everywhere.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

/// A null sampler means [SamplerOptions.linearRepeat], not the constructor's
/// own defaults.
///
/// **Worth about two percent of every textured golden.** The constructor
/// defaults are nearest and clamp; the contract says a binding that names no
/// sampler gets linear and repeat. A backend that takes the constructor
/// defaults draws hard seams where the others draw soft ones — which looks
/// exactly like a filtering bug in the engine, and is the sort of difference
/// somebody spends a day bisecting.
///
/// Asked with the coordinate *outside* `[0, 1]`, because that is where the two
/// answers differ: clamped, the far edge repeats the last column; repeated, it
/// wraps to the first.
Future<void> checkNullSamplerRepeats(GraphicsDevice device) async {
  const size = 8;

  final vertex = device.shaders['ParticleVertex'];
  // **`ParticleTextured`, not `Particle`.** The plain one draws its disc
  // procedurally and never reads the texture it is handed — so the first
  // version of this check bound a texture nothing sampled, could not tell a
  // clamp from a repeat, and passed with the wrong default deliberately put
  // back. A check that cannot fail is worse than none.
  final fragment = device.shaders['ParticleTextured'];
  require(
    vertex != null && fragment != null,
    'the textured particle stages are missing, so nothing here samples',
  );

  // Two texels side by side: black then white. Sampled past the right-hand
  // edge, a repeat comes back to the black and a clamp stays on the white.
  final pixels = ByteData(2 * 1 * 4);
  for (var i = 0; i < 4; i++) {
    pixels.setUint8(i, i == 3 ? 255 : 0);
    pixels.setUint8(4 + i, 255);
  }
  final texture = device.createTextureFromPixels(
    width: 2,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: pixels,
  );
  require(texture != null, 'a two-texel texture could not be uploaded');

  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );

  // A full-frame triangle whose U runs from 1.25 to 1.25 — one full period
  // past the edge and a quarter, which lands on the first texel under a repeat
  // and on the last one under a clamp. V is held at the middle.
  final triangle = Float32List.fromList(<double>[
    -1, -1, 0.5, 1, 1, 1, 1, 1.25, 0.5, //
    3, -1, 0.5, 1, 1, 1, 1, 1.25, 0.5,
    -1, 3, 0.5, 1, 1, 1, 1, 1.25, 0.5,
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
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(device.createPipeline(vertex!, fragment!))
    ..bindUniformBlock(vertex, 'ParticleInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindUniformBlock(fragment, 'FogInfo', <String, Float32List>{
      'fog': Float32List(4),
      'eye': Float32List(4),
    })
    // **The whole check is this argument being absent.**
    ..bindTexture(fragment, 'particle_texture', texture!)
    ..bindVertexData(ByteData.sublistView(triangle), 3)
    ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
    ..draw();
  pass.submit();

  final read = await device.readPixels(target);
  require(read != null, 'the target could not be read back');
  final bytes = read!.buffer.asUint8List();
  final at = ((size ~/ 2) * size + size ~/ 2) * 4;
  final red = bytes[at];

  require(
    red < 128,
    'a texture bound with no sampler was clamped rather than repeated: at '
    'u = 1.25 it came back $red, which is the far texel. A null sampler means '
    'SamplerOptions.linearRepeat — not the constructor defaults, which are '
    'nearest and clamp. See ARCHITECTURE.md §7.2.',
  );
}

/// `setDepthWrite(false)` means depth writes are off.
///
/// **This was a lie for a whole SDK version**, in both directions: flutter_gpu's
/// native setter ignored its argument and turned writes on, and the software
/// backend mirrored the bug on purpose because an honest implementation put the
/// particle scenes five to ten percent away from the hardware one. Both are
/// fixed since 3.47, and what is left is a rule a new backend has to be told —
/// there is nothing in the signature that says which way it goes, and a backend
/// that ignores the argument passes every other check in this suite.
///
/// Two overlapping draws at different depths, with writes off. The second is
/// behind the first, so with writes on it is rejected by the depth the first
/// one wrote and the frame stays the first colour; with writes off there is
/// nothing to reject it and it lands.
Future<void> checkDepthWriteIsHonoured(GraphicsDevice device) async {
  const size = 8;

  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(
    vertex != null && fragment != null,
    'the debug-line stages are missing, so this cannot draw twice',
  );

  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final depth = device.createTexture(
    RenderTargetSpec(
      width: size,
      height: size,
      format: device.defaultDepthStencilFormat,
      storageMode: StorageMode.deviceTransient,
    ),
  );

  Float32List triangleAt(double z, List<double> colour) =>
      Float32List.fromList(<double>[
        -1, -1, z, ...colour, //
        3, -1, z, ...colour,
        -1, 3, z, ...colour,
      ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);
  final identity = Float32List.fromList(Matrix4.identity().storage);

  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4.zero(),
        ),
      ],
      depth: DepthTarget(texture: depth),
    ),
  );
  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..setDepthCompare(CompareFunction.lessEqual)
    // The argument under test. Everything below draws with writes off, so the
    // depth buffer keeps the 1.0 it was cleared to and neither draw is ever
    // rejected by the other.
    ..setDepthWrite(false)
    ..bindPipeline(device.createPipeline(vertex!, fragment!));

  void triangle(double z, List<double> colour) {
    pass
      ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
        'view_projection': identity,
      })
      ..bindVertexData(ByteData.sublistView(triangleAt(z, colour)), 3)
      ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
      ..draw();
  }

  // Near and red first, then far and green. With writes off the second one is
  // still allowed through and wins by being last.
  triangle(0.2, <double>[1, 0, 0, 1]);
  triangle(0.8, <double>[0, 1, 0, 1]);
  pass.submit();

  final read = await device.readPixels(target);
  require(read != null, 'the target could not be read back');
  final bytes = read!.buffer.asUint8List();
  final at = ((size ~/ 2) * size + size ~/ 2) * 4;

  require(
    bytes[at + 1] > bytes[at],
    'setDepthWrite(false) did not stop depth writes: the second, further draw '
    'was rejected by depth the first one should not have written. The centre '
    'came back r=${bytes[at]} g=${bytes[at + 1]}. See ARCHITECTURE.md §7.2.',
  );
}
