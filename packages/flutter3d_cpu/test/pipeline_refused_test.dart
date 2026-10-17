/// A pipeline the software rasteriser cannot build is refused the way every
/// backend refuses one: reported once, its draws skipped.
///
///     dart test test/pipeline_refused_test.dart
///
/// The one pipeline this backend cannot build is one whose layout names an
/// integer attribute: a stage here is handed floats. That threw an
/// `UnsupportedError` from `createPipeline`, which a renderer met at the first
/// frame that drew the mesh and every frame after.
library;

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

CpuDevice _device() => CpuDevice(
  width: 4,
  height: 4,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

const _integerJoints = VertexLayoutDescriptor(<BufferLayout>[
  BufferLayout(
    strideInBytes: 16,
    attributes: <InputAttribute>[
      InputAttribute(name: 'joints', format: VertexFormat.uint32x4),
    ],
  ),
]);

void main() {
  test('an integer attribute is a refused pipeline, not a throw', () {
    // Mutation: put back the `UnsupportedError`, and createPipeline throws.
    final device = _device();
    final pipeline = device.createPipeline(
      device.shaders['MeshVertex']!,
      device.shaders['Unlit']!,
      layout: _integerJoints,
    );
    final told = device.pipelineRefusals.drain().single;
    expect(told.pipeline, 'MeshVertex+Unlit');
    expect(told.reason, PipelineRefusalReason.unsupportedFormat);
    expect(told.backend, device.backendName);
    expect(told.detail, contains('uint32x4'));
    // A format does not change between frames, so nothing is built again.
    expect(device.pipelineRefusals.isRefused(pipeline), isTrue);
  });

  test('a draw with it draws nothing, and the pass goes on', () {
    // Mutation: bind the refusal as if it were a `CpuPipeline`, and the
    // bind throws a cast error mid-pass.
    final device = _device();
    final pipeline = device.createPipeline(
      device.shaders['MeshVertex']!,
      device.shaders['Unlit']!,
      layout: _integerJoints,
    );
    final target = device.createTexture(
      const RenderTargetDescriptor(
        width: 4,
        height: 4,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    device.beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[ColorTarget(texture: target)],
        ),
      )
      ..bindPipeline(pipeline)
      ..draw()
      ..submit();
  });
}
