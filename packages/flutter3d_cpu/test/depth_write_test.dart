/// Depth writes go off when they are asked to, and a fresh pass has them off.
///
/// This file used to say the opposite. `CpuEncoder.setDepthWrite` ignored its
/// argument and turned writes on, because `flutter_gpu`'s native setter
/// assigned the literal `true`, and a software backend that behaved correctly
/// would have drawn the particle scenes five and ten percent away from the
/// hardware one — a gap wide enough to hide a real regression behind.
///
/// Its header said to delete it the day the SDK was fixed. That was written
/// when its only job was pinning a mirror, and it was wrong: the fixture below
/// is the minimal reproduction that *found* the engine bug, it runs in a
/// millisecond, and flipping one expectation turns it from "the mirror is
/// still in place" into "the mirror is gone and the argument is honoured".
/// Deleting it would have thrown away the only direct evidence either way.
///
/// The second test never changed at all. The default is a property of
/// `DepthAttachmentDescriptor` rather than of the setter 3.47 fixed, and a
/// default nobody states is a default that drifts.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Draws two coincident triangles and reports how many times the second one
/// reached the target.
///
/// Coincident and additive on purpose: with depth writes genuinely off both
/// land and the result is twice one triangle, and with them on the first
/// writes its depth and the second fails `less`. One number tells the two
/// apart, which is the whole experiment that found the engine bug, reduced to
/// something that runs in a millisecond.
double _twoCoincidentTriangles({required bool askForDepthWriteOff}) {
  final device = CpuDevice(
    width: 8,
    height: 8,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final colour = device.createTexture(const RenderTargetSpec(
    width: 8,
    height: 8,
    format: TextureFormat.r16g16b16a16Float,
  ));
  final depth = device.createTexture(const RenderTargetSpec(
    width: 8,
    height: 8,
    format: TextureFormat.d32FloatS8UInt,
  ));

  final pass = device.beginRenderPass(RenderPassDescriptor(
    colors: <ColorTarget>[
      ColorTarget(
        texture: colour,
        loadAction: LoadAction.clear,
        clearValue: Vector4.zero(),
      ),
    ],
    depth: DepthTarget(texture: depth, clearValue: 1.0),
  ));

  // The debug-line stages: a vertex stage that needs one matrix and a fragment
  // stage that returns its varying unchanged, which makes the arithmetic here
  // something a reader can check by eye.
  final vertex = device.shaders['DebugLineVertex']!;
  final fragment = device.shaders['DebugLine']!;
  pass.bindPipeline(device.createPipeline(vertex, fragment));
  pass.setPrimitiveType(PrimitiveType.triangle);
  pass.setCullMode(CullMode.none);
  pass.setBlend(BlendState.additive);
  pass.setDepthCompare(CompareFunction.less);
  if (askForDepthWriteOff) pass.setDepthWrite(false);
  pass.bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
    'view_projection': Float32List.fromList(Matrix4.identity().storage),
  });

  // One triangle covering the target, quarter brightness, drawn twice.
  final one = Float32List.fromList(<double>[
    -1, -1, 0.5, 0.25, 0, 0, 1, //
    3, -1, 0.5, 0.25, 0, 0, 1,
    -1, 3, 0.5, 0.25, 0, 0, 1,
  ]);
  for (var i = 0; i < 2; i++) {
    pass.bindVertexData(ByteData.sublistView(one), 3);
    pass.draw();
  }
  pass.submit();

  return (colour.backend as CpuTexture).pixels[0];
}

void main() {
  test('asking for depth writes off turns them off', () {
    // A half, not a quarter. The request was honoured, so the first draw left
    // the depth buffer alone, the second passed `less` against the cleared
    // value, both landed, and additive blending added them.
    //
    // A quarter here means this backend is back to ignoring the argument — the
    // shape of the bug flutter_gpu had until 3.47, and the reason this fixture
    // exists rather than a comment saying the same thing.
    expect(_twoCoincidentTriangles(askForDepthWriteOff: true),
        closeTo(0.5, 1e-6),
        reason: 'the second triangle never reached the target, so depth writes '
            'were on despite being switched off');
  });

  test('a pass nobody asks starts with depth writes off', () {
    // Unchanged, and deliberately so: a fresh flutter_gpu RenderPass has writes
    // disabled until something calls the setter, and 3.47 changed the setter
    // rather than that default. Never calling it therefore leaves both draws
    // landing, exactly as it did before.
    expect(_twoCoincidentTriangles(askForDepthWriteOff: false),
        closeTo(0.5, 1e-6),
        reason: 'a pass that was never told anything about depth writes '
            'behaved as though they were on');
  });
}
