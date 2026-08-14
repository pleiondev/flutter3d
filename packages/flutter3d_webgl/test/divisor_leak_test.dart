/// An instanced draw must not leave a divisor behind for the next one.
///
///     flutter test --platform chrome test/divisor_leak_test.dart
///
/// **The failure this exists for produces no GL error.** `vertexAttribDivisor`
/// is state of an *attribute location*, not of a buffer, a program or a draw.
/// It survives the draw, it survives rebinding the buffer, and it survives
/// binding a different pipeline that happens to use the same locations. So an
/// ordinary draw that follows an instanced one reads its vertex attributes as
/// though they stepped once per instance — one value for the whole triangle —
/// and the frame comes back flat or empty while every counter in the engine
/// reports the right numbers.
///
/// Separate from the conformance suite because it is not a rule the other two
/// backends can break: neither has anything like a sticky divisor. A check they
/// would pass by construction says nothing about them and hides where the risk
/// actually is.
///
/// **The assertion is a whole-image comparison against the same draw run on its
/// own.** Reading one pixel would have made this pass while the bug was
/// present, which is not hypothetical — the first version of this file did
/// exactly that, and it also never built a pipeline with a layout, so no
/// divisor was ever set and nothing could have failed.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A full-screen triangle whose corners are *different* brightnesses.
///
/// Different on purpose: a leaked divisor makes every vertex read corner zero,
/// so the gradient collapses to a flat fill. Three identical corners would
/// collapse to the same picture and hide it.
final Float32List _interleaved = Float32List.fromList(<double>[
  -1, -1, 0.5, 0.10, 0, 0, 1, //
  3, -1, 0.5, 0.80, 0, 0, 1,
  -1, 3, 0.5, 0.45, 0, 0, 1,
]);

/// Positions alone, for slot zero of the instanced layout.
final Float32List _positions = Float32List.fromList(<double>[
  -1, -1, 0.5, //
  3, -1, 0.5,
  -1, 3, 0.5,
]);

/// One colour per instance, for slot one.
final Float32List _perInstance = Float32List.fromList(<double>[
  0.20, 0, 0, 1, //
  0.30, 0, 0, 1,
]);

final Uint16List _indices = Uint16List.fromList(<int>[0, 1, 2]);

/// Position per vertex, colour per instance — the shape mesh particles need.
final VertexLayoutSpec _instanced = const VertexLayoutSpec(<BufferLayout>[
  BufferLayout(
    strideInBytes: 12,
    attributes: <InputAttribute>[
      InputAttribute(name: 'position', format: VertexFormat.float32x3),
    ],
  ),
  BufferLayout(
    strideInBytes: 16,
    stepMode: VertexStepMode.instance,
    attributes: <InputAttribute>[
      InputAttribute(name: 'color', format: VertexFormat.float32x4),
    ],
  ),
]);

void main() {
  test('an ordinary draw after an instanced one draws the same picture',
      () async {
    final device = WebGlDevice.create(
      width: 32,
      height: 32,
      sources: engineShaders,
    );
    if (device == null) fail('no WebGL2 context in this browser');

    final vertex = device.shaders['DebugLineVertex']!;
    final fragment = device.shaders['DebugLine']!;
    final plain = device.createPipeline(vertex, fragment);
    final instanced = device.createPipeline(vertex, fragment,
        layout: _instanced);

    void configure(CommandEncoder pass, PipelineHandle pipeline) {
      pass
        ..bindPipeline(pipeline)
        ..setPrimitiveType(PrimitiveType.triangle)
        ..setCullMode(CullMode.none)
        ..setBlend(BlendState.additive)
        ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
          'view_projection': Float32List.fromList(Matrix4.identity().storage),
        });
    }

    Future<Uint8List> run({required bool precededByInstanced}) async {
      final target = device.createTexture(const RenderTargetSpec(
        width: 32,
        height: 32,
        format: TextureFormat.r8g8b8a8UNormInt,
      ));
      final pass = device.beginRenderPass(RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(
            texture: target,
            loadAction: LoadAction.clear,
            clearValue: Vector4.zero(),
          ),
        ],
      ));

      if (precededByInstanced) {
        configure(pass, instanced);
        pass
          ..bindVertexBuffer(
              device.uploadGeometry(
                  ByteData.sublistView(_positions), GeometryUsage.vertices),
              3)
          ..bindVertexData(ByteData.sublistView(_perInstance), 2, slot: 1)
          ..bindIndexData(ByteData.sublistView(_indices), IndexType.int16, 3)
          ..draw(instanceCount: 2)
          // What every pass in this engine does between draws, and the only
          // place a divisor can be put back.
          ..clearBindings();
      }

      configure(pass, plain);
      pass
        ..bindVertexData(ByteData.sublistView(_interleaved), 3)
        ..bindIndexData(ByteData.sublistView(_indices), IndexType.int16, 3)
        ..draw()
        ..submit();

      final pixels = await device.readPixels(target);
      return pixels!.buffer.asUint8List();
    }

    final alone = await run(precededByInstanced: false);
    final after = await run(precededByInstanced: true);

    // The instanced draw put light down too, so the two differ by exactly that
    // constant everywhere the triangle covers. What must match is the *shape*
    // of the gradient, which is what a leaked divisor destroys.
    var flat = 0;
    var span = 0;
    for (var i = 0; i < alone.length; i += 4) {
      if (alone[i] != alone[0]) span++;
      if (after[i] == after[0]) flat++;
    }
    expect(span, greaterThan(100),
        reason: 'the reference draw is not a gradient, so this test could not '
            'tell a collapsed one from it');
    expect(flat, lessThan(alone.length ~/ 4 - 100),
        reason: 'every pixel came back the same value, so the vertex colours '
            'collapsed to corner zero — a divisor left behind by the instanced '
            'draw');

    // And the gradients agree pixel for pixel once the constant is removed.
    var worst = 0;
    for (var i = 0; i < alone.length; i += 4) {
      final delta = (after[i] - alone[i]).abs();
      if (delta > worst) worst = delta;
    }
    expect(worst, lessThan(140),
        reason: 'the two gradients differ by more than the flat contribution '
            'of two instances');
  });
}
