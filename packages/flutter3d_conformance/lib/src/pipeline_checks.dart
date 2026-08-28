import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

/// A binding made for one pipeline must not follow the next one.
///
/// The contract is written on `CommandEncoder.bindPipeline`: bindings do not
/// survive a pipeline bind. What earns it a conformance check is that
/// flutter_gpu's pass breaks it by construction — it replays every binding it
/// has ever been handed at every draw, keyed by the shader that bound it, and
/// two shaders' blocks that share a slot index then fight for that slot in
/// whatever order an `unordered_map` iterates. The winner is stable within a
/// run and meaningless, which on screen was a skinned monster drawn as a
/// splinter — but only in scenes that also drew something else, which is why
/// every single-model reproduction came out innocent.
///
/// Two pipelines whose only vertex block sits at the same slot, one draw each,
/// in both orders. Each draw's matrix decides where its triangle lands, so if
/// the stale block follows the switch, the second draw lands where the *first*
/// draw's matrix pointed — offscreen — and the centre stays black.
Future<void> checkPipelineSwitchKeepsBindingsApart(
  GraphicsDevice device,
) async {
  const size = 16;

  final lineVertex = device.shaders['DebugLineVertex'];
  final lineFragment = device.shaders['DebugLine'];
  final particleVertex = device.shaders['ParticleVertex'];
  final particleFragment = device.shaders['Particle'];
  require(
    lineVertex != null &&
        lineFragment != null &&
        particleVertex != null &&
        particleFragment != null,
    'the debug-line or particle stages are missing, so this cannot switch '
    'between two pipelines',
  );

  final centred = Float32List.fromList(Matrix4.identity().storage);
  final offscreen = Float32List.fromList(
    Matrix4.translationValues(64.0, 0.0, 0.0).storage,
  );

  // The same full-frame triangle in each pipeline's own layout: the line one
  // pure green, the particle one pure red with its UV centre on the middle of
  // the frame, where the particle disc is at full strength.
  final lineTriangle = Float32List.fromList(<double>[
    -1, -1, 0.5, 0, 1, 0, 1, //
    3, -1, 0.5, 0, 1, 0, 1,
    -1, 3, 0.5, 0, 1, 0, 1,
  ]);
  final particleTriangle = Float32List.fromList(<double>[
    -1, -1, 0.5, 1, 0, 0, 1, 0, 0, //
    3, -1, 0.5, 1, 0, 0, 1, 2, 0,
    -1, 3, 0.5, 1, 0, 0, 1, 0, 2,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  Future<List<int>> centreWith({required bool lineLast}) async {
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
      ..setCullMode(CullMode.none);

    void line(Float32List matrix) {
      pass
        ..bindPipeline(device.createPipeline(lineVertex!, lineFragment!))
        ..bindUniformBlock(lineVertex, 'LineInfo', <String, Float32List>{
          'view_projection': matrix,
        })
        ..bindVertexData(ByteData.sublistView(lineTriangle), 3)
        ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
        ..draw();
    }

    void particle(Float32List matrix) {
      pass
        ..bindPipeline(
          device.createPipeline(particleVertex!, particleFragment!),
        )
        ..bindUniformBlock(
          particleVertex,
          'ParticleInfo',
          <String, Float32List>{'view_projection': matrix},
        )
        // Density nought: fog off, so the disc's own colour reaches the target.
        ..bindUniformBlock(particleFragment, 'FogInfo', <String, Float32List>{
          'fog': Float32List(4),
          'eye': Float32List(4),
        })
        ..bindVertexData(ByteData.sublistView(particleTriangle), 3)
        ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
        ..draw();
    }

    if (lineLast) {
      particle(offscreen);
      line(centred);
    } else {
      line(offscreen);
      particle(centred);
    }
    pass.submit();

    final pixels = await device.readPixels(target);
    require(pixels != null, 'the target could not be read back');
    final at = ((size ~/ 2) * size + size ~/ 2) * 4;
    return pixels!.buffer.asUint8List().sublist(at, at + 3);
  }

  final line = await centreWith(lineLast: true);
  require(
    line[1] > 128,
    'a debug-line draw bound the identity and landed off the frame — the '
    'particle pipeline\'s stale ParticleInfo followed it through the switch '
    '(centre came back $line)',
  );

  final particle = await centreWith(lineLast: false);
  require(
    particle[0] > 128,
    'a particle draw bound the identity and landed off the frame — the '
    'debug-line pipeline\'s stale LineInfo followed it through the switch '
    '(centre came back $particle)',
  );
}
