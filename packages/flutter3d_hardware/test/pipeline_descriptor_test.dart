/// Pipelines built from a descriptor.
///
/// A member a backend overrides cannot gain a parameter within a major, so
/// every input a pipeline gains after 1.0 arrives as a field of
/// `PipelineDescriptor` or `ComputePipelineDescriptor`. The entry points
/// that take them have default bodies over the parameter forms, so a backend
/// that overrides only `createPipeline` builds the same pipeline through
/// either.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:test/test.dart';

/// Overrides only the parameter forms and says what it was handed.
final class _PairDevice extends GraphicsDevice {
  final List<(String, String, VertexLayoutDescriptor?)> linked =
      <(String, String, VertexLayoutDescriptor?)>[];
  final List<String> computed = <String>[];

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) {
    linked.add((vertex.name, fragment.name, layout));
    return wrapPipeline(owner: this, backend: Object(), name: vertex.name);
  }

  @override
  ComputePipelineHandle createComputePipeline(ShaderHandle shader) {
    computed.add(shader.name);
    return wrapComputePipeline(owner: this, backend: Object(), shader: shader);
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName} has no default body');
}

/// Overrides nothing: every abstract member answers with a `StateError`.
final class _BareDevice extends GraphicsDevice {
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName} has no default body');
}

final ShaderHandle _vertex = wrapShader(backend: Object(), name: 'QuadVertex');
final ShaderHandle _fragment = wrapShader(
  backend: Object(),
  name: 'QuadFragment',
);
final ShaderHandle _kernel = wrapShader(backend: Object(), name: 'Sum');

const VertexLayoutDescriptor _layout = VertexLayoutDescriptor(<BufferLayout>[
  BufferLayout(
    strideInBytes: 12,
    attributes: <InputAttribute>[
      InputAttribute(
        name: 'position',
        format: VertexFormat.float32x3,
        offsetInBytes: 0,
      ),
    ],
  ),
]);

void main() {
  test('a descriptor links through createPipeline by default', () async {
    // Mutation: drop `layout:` from the default body's call. The pair is
    // linked with no layout, which reads instance data as vertices.
    final device = _PairDevice();
    final pipeline = device.createPipelineFrom(
      PipelineDescriptor(
        vertex: _vertex,
        fragment: _fragment,
        layout: _layout,
        label: 'quad',
      ),
    );
    expect(device.linked.single, ('QuadVertex', 'QuadFragment', _layout));
    expect(device.labelOf(pipeline), 'quad');

    final later = await device.createPipelineFromAsync(
      PipelineDescriptor(vertex: _vertex, fragment: _fragment),
    );
    expect(device.linked.last, ('QuadVertex', 'QuadFragment', null));
    expect(device.labelOf(later), isNull);
  });

  test('a compute descriptor builds through createComputePipeline', () async {
    // Mutation: return without the label in the compute default. The
    // pipeline has no name for a debugger.
    final device = _PairDevice();
    final pipeline = device.createComputePipelineFrom(
      ComputePipelineDescriptor(shader: _kernel, label: 'prefix sum'),
    );
    expect(device.computed, <String>['Sum']);
    expect(device.labelOf(pipeline), 'prefix sum');
    final later = await device.createComputePipelineFromAsync(
      ComputePipelineDescriptor(shader: _kernel),
    );
    expect(later.shader, same(_kernel));
    expect(device.computed, <String>['Sum', 'Sum']);
  });

  test('a device without compute refuses the descriptor as compute', () {
    // Mutation: refuse `buffers` in the default. The refusal names a
    // feature the device may well have.
    final fake = _BareDevice();
    expect(
      () => fake.createComputePipelineFrom(
        ComputePipelineDescriptor(shader: _kernel),
      ),
      throwsA(
        isA<UnsupportedCapabilityException>().having(
          (UnsupportedCapabilityException e) => e.feature,
          'feature',
          DeviceFeature.compute,
        ),
      ),
    );
  });

  test('descriptors compare by their fields', () {
    expect(
      PipelineDescriptor(vertex: _vertex, fragment: _fragment, layout: _layout),
      PipelineDescriptor(vertex: _vertex, fragment: _fragment, layout: _layout),
    );
    expect(
      PipelineDescriptor(vertex: _vertex, fragment: _fragment),
      isNot(
        PipelineDescriptor(
          vertex: _vertex,
          fragment: _fragment,
          layout: _layout,
        ),
      ),
    );
    expect(
      ComputePipelineDescriptor(shader: _kernel).hashCode,
      ComputePipelineDescriptor(shader: _kernel).hashCode,
    );
  });

  test('the recorder writes a descriptor pipeline and its label', () {
    // Mutation: forward `createPipelineFrom` to the inner device without
    // recording it. The trace names no pipeline, and its replay binds one
    // it never made.
    final device = RecordingDevice(FakeBackend());
    final pipeline = device.createPipelineFrom(
      PipelineDescriptor(
        vertex: device.shaders['UnlitVertex']!,
        fragment: device.shaders['UnlitFragment']!,
        label: 'unlit',
      ),
    );
    final created = device.events.whereType<TraceCreatePipeline>().single;
    expect(
      (created.vertex, created.fragment),
      ('UnlitVertex', 'UnlitFragment'),
    );
    final label = device.events.whereType<TraceSetLabel>().single;
    expect(
      (label.resource, label.id, label.label),
      (TraceLabeled.pipeline, created.id, 'unlit'),
    );
    expect(device.labelOf(pipeline), 'unlit');
  });
}
