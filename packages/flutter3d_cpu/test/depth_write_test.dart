/// The depth-write mirror, pinned.
///
/// `CpuEncoder.setDepthWrite` ignores its argument and turns writes on,
/// because `flutter_gpu`'s native setter does exactly that — see the comment
/// on that method for the engine source. This file exists so that the mirror
/// is a decision with a test behind it rather than a line somebody deletes on
/// a Tuesday because it looks obviously wrong.
///
/// It does look obviously wrong. That is the point of the test.
///
/// **Delete this file the day the SDK is fixed**, and make `setDepthWrite`
/// honest again in the same commit. Until then the two backends draw the same
/// picture, which is worth more here than either of them being right on its
/// own: a five to ten percent gap on the particle scenes is loud enough to
/// hide a genuine regression behind.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_graphics/flutter3d_graphics.dart';
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
  test('asking for depth writes off does not turn them off', () {
    // A quarter, not a half. The request was ignored, so the first draw wrote
    // its depth of 0.5, and the second compared `less` against it, failed, and
    // never reached the target. A backend that honoured the request would
    // leave the buffer alone, both draws would land, and additive blending
    // would give a half.
    expect(_twoCoincidentTriangles(askForDepthWriteOff: true), closeTo(0.25, 1e-6),
        reason: 'the second triangle landed, so depth writes really were '
            'disabled — which means this backend has stopped mirroring '
            'flutter_gpu. If the SDK was fixed, delete this file and make '
            'setDepthWrite honest; if it was not, the mirror broke.');
  });

  test('a pass nobody asks starts with depth writes off', () {
    // The other half of the mirror, and the half that is easy to miss: a fresh
    // flutter_gpu RenderPass has writes disabled until something calls the
    // setter. Never calling it therefore leaves both draws landing.
    expect(_twoCoincidentTriangles(askForDepthWriteOff: false),
        closeTo(0.5, 1e-6),
        reason: 'a pass that was never told anything about depth writes '
            'behaved as though they were on');
  });
}
