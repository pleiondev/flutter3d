/// Two rules from the backend contract that a signature cannot state, and that
/// nothing in this suite was asking about.
///
/// Two of the fourteen rules ARCHITECTURE.md §7.2 states — "a backend that gets
/// one of these wrong compiles and draws the wrong thing". They are the ones a
/// *new* backend is most likely to get wrong, because both are decisions
/// somebody has to make deliberately and neither produces an error when made
/// the other way.
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

/// A block the shader has, missing a member the caller named, is an error —
/// on every backend that can see the difference.
///
/// **The two failures look alike and are not.** A compiler drops a whole block
/// nothing reads, and `bindUniformBlock` answers false for it: ordinary, and
/// the caller is entitled to shrug. A block that *exists* without one of the
/// members written into it means the engine and the shader disagree about its
/// shape, and the member's bytes stay zero — a plausible value for nearly
/// everything that goes through here. A shadow strength of zero is a scene with
/// no shadows and no error anywhere.
///
/// This went unchecked for as long as the suite existed, and the two hardware
/// backends drifted apart under it: the web backend threw, Impeller returned,
/// so one bundle was a named exception in a browser and a quietly wrong picture
/// on a phone. `flutter3d_conformance`'s own header used to name "a uniform
/// block's members" as deliberately outside the suite.
///
/// **Asked only of a backend that reflects its shaders, and it is asked which
/// one it is rather than told.** A backend with no reflection — the software
/// rasteriser hands the block to a Dart shader that looks up what it needs by
/// name — cannot tell a misspelt member from a member nobody reads, and is not
/// asked to. The discriminator is the block case above it: a backend that
/// answers false for a block no shader has is one that can see inside a shader,
/// and it is then held to the member rule. One that answers true for a block
/// that does not exist has no reflection at all, and the check says so and
/// stops. That keeps this from being a check every backend passes by
/// construction, which is what the cube-face check was until it started
/// pointing a direction at a face.
Future<void> checkUniformMemberMismatchIsRefused(GraphicsDevice device) async {
  final vertex = device.shaders['ParticleVertex'];
  require(vertex != null, 'the particle vertex stage is missing');

  final target = device.createTexture(
    const RenderTargetSpec(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4(0.0, 0.0, 0.0, 1.0),
        ),
      ],
    ),
  );
  pass.bindPipeline(
    device.createPipeline(vertex!, device.shaders['Particle'] ?? vertex),
  );

  // Which kind of backend this is, asked rather than assumed.
  final reflects = !pass.bindUniformBlock(
    vertex,
    'NoBlockAnyShaderHasEverDeclared',
    <String, Float32List>{'anything': Float32List(4)},
  );
  if (!reflects) {
    // Not a failure, and not silence either: the run says which rule it could
    // not ask about, so a reader of the pass list can tell "checked" from
    // "does not apply here".
    pass.submit();
    return;
  }

  var threw = false;
  try {
    pass.bindUniformBlock(vertex, 'ParticleInfo', <String, Float32List>{
      // `ParticleInfo` has `view_projection` and no such member as this.
      'view_projection_typed_wrong': Float32List(16),
    });
    // Only a backend that refused nothing gets here, and its pass is still
    // open: submitted so the check leaves no encoder behind on the way to
    // reporting the failure.
    pass.submit();
  } on Object {
    threw = true;
    // Deliberately not submitted. A backend is entitled to release the pass
    // on the way out — the web one does, and calling `submit` after it throws
    // is a second, misleading exception on top of the right behaviour. The
    // first version of this check did exactly that and reported a correct
    // backend as broken.
  }

  require(
    threw,
    'a backend that reflects its shaders bound "ParticleInfo" with a member '
    'the block does not have and did not throw. The bytes for that member '
    'stay zero, and zero is a plausible value for most of what goes through a '
    'uniform block — so the picture comes out wrong with nothing logged. See '
    'ARCHITECTURE.md §7.1 and CommandEncoder.bindUniformBlock.',
  );
}
