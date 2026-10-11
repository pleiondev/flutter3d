/// A pipeline linked off the calling turn, where the browser compiles on its
/// own threads.
///
///     flutter test --platform chrome test/parallel_link_test.dart
///
/// **`KHR_parallel_shader_compile` changes nothing until somebody stops
/// asking.** The driver compiles and links on its own threads either way;
/// what blocks is the first `getProgramParameter(LINK_STATUS)`, which waits
/// for the link to finish. With the extension a caller can ask
/// `COMPLETION_STATUS_KHR` instead, which never waits, and ask for the status
/// only once the answer is ready. `createPipelineAsync` does that, and these
/// checks hold it to the four things it promises: it does not finish in the
/// calling turn, its pipeline draws, a synchronous link of the same pair in
/// the meantime does not link it twice, and a pair the linker refuses is a
/// refused pipeline rather than a throw.
///
/// **A browser without the extension reports rather than fails**, as the
/// WebGPU suite does for a browser without WebGPU.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter3d_webgl/src/webgl_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A fragment stage that reads a varying no vertex stage writes: it
/// compiles, and the linker refuses it beside `DebugLineVertex`.
const String _unlinkable = '''#version 300 es
precision highp float;
in vec4 v_never_written;
out vec4 frag_color;
void main() { frag_color = v_never_written; }
''';

/// A full-screen triangle, position and colour per vertex.
final Float32List _triangle = Float32List.fromList(<double>[
  -1, -1, 0.5, 1, 0, 0, 1, //
  3, -1, 0.5, 1, 0, 0, 1,
  -1, 3, 0.5, 1, 0, 0, 1,
]);

/// The device, or null where this browser has no parallel compile.
Future<WebGlDevice?> _open() async {
  final device = await WebGlDevice.open(
    width: 8,
    height: 8,
    sources: ShaderSources(webGlEngineShaders.vertex, <String, String>{
      ...webGlEngineShaders.fragment,
      'Unlinkable': _unlinkable,
    }),
  );
  if (!device.parallelShaderCompile) {
    markTestSkipped('no KHR_parallel_shader_compile in this browser');
    device.dispose();
    return null;
  }
  return device;
}

void main() {
  test('links off the calling turn', () async {
    // Mutation: link and ask the status in the calling turn, as the default
    // `createPipelineAsync` does — the future is complete before the timer
    // queued ahead of it fires.
    final device = await _open();
    if (device == null) return;
    var turned = false;
    Timer.run(() => turned = true);
    await device.createPipelineAsync(
      device.shaders['DebugLineVertex']!,
      device.shaders['DebugLine']!,
    );
    expect(turned, isTrue);
    device.dispose();
  });

  test('the pipeline it links draws', () async {
    final device = await _open();
    if (device == null) return;
    final vertex = device.shaders['DebugLineVertex']!;
    final pipeline = await device.createPipelineAsync(
      vertex,
      device.shaders['DebugLine']!,
    );
    final target = device.createTexture(
      const RenderTargetDescriptor(
        width: 8,
        height: 8,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    device.beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[
            ColorTarget(texture: target, clearValue: Vector4(0, 0, 0, 1)),
          ],
        ),
      )
      ..bindPipeline(pipeline)
      ..setCullMode(CullMode.none)
      ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
        'view_projection': Float32List.fromList(Matrix4.identity().storage),
      })
      ..setPrimitiveType(PrimitiveType.triangle)
      ..bindVertexData(ByteData.sublistView(_triangle), 3)
      ..bindIndexData(
        ByteData.sublistView(Uint16List.fromList(<int>[0, 1, 2])),
        IndexType.int16,
        3,
      )
      ..draw()
      ..submit();
    final pixels = await device.readback(target);
    expect(pixels.getUint8(0), greaterThan(200), reason: 'red was drawn');
    expect(device.pipelineRefusals.drain(), isEmpty);
    device.dispose();
  });

  test('a synchronous link of the same pair meanwhile links once', () async {
    // Mutation: let `link` start its own program while the asynchronous one
    // is out — the pair is linked twice and one program is never deleted.
    final device = await _open();
    if (device == null) return;
    final vertex = device.shaders['DebugLineVertex']!;
    final fragment = device.shaders['DebugLine']!;
    final before = device.debugTrackedResourceCount;
    final later = device.createPipelineAsync(vertex, fragment);
    final now = device.createPipeline(vertex, fragment);
    final linked = await later;
    expect(
      (linked.backend as WebGlProgram).program,
      same((now.backend as WebGlProgram).program),
    );
    expect(device.debugTrackedResourceCount, before + 1);
    device.dispose();
  });

  test('a pair the linker refuses is a refused pipeline', () async {
    // Mutation: let the asynchronous link throw — the caller's future fails
    // where the synchronous `createPipeline` reports and goes on.
    final device = await _open();
    if (device == null) return;
    final pipeline = await device.createPipelineAsync(
      device.shaders['DebugLineVertex']!,
      device.shaders['Unlinkable']!,
    );
    final refusals = device.pipelineRefusals.drain();
    expect(refusals, hasLength(1));
    expect(refusals.single.reason, PipelineRefusalReason.link);
    expect(refusals.single.pipeline, pipeline.name);
    device.dispose();
  });
}
