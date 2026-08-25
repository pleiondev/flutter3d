/// A library of Dart stages, by the names the engine asks for, and a linked
/// pair.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'cpu_shader.dart';

/// A library of Dart stages, by the names the engine asks for.
final class CpuShaderLibrary implements ShaderLibrary {
  CpuShaderLibrary(this.stages);

  final Map<String, CpuStage> stages;

  @override
  ShaderHandle? operator [](String name) {
    final stage = stages[name];
    if (stage == null) return null;
    return ShaderHandle(backend: stage, name: name);
  }
}

/// A vertex and a fragment stage, paired.
final class CpuPipeline {
  const CpuPipeline(this.vertex, this.fragment, this.layout);
  final CpuVertexShader vertex;
  final CpuFragmentShader fragment;

  /// Where the vertex stage's inputs come from, or null to read one
  /// interleaved buffer in shader order — see `CpuEncoder._drawOnce`.
  final VertexLayoutSpec? layout;
}
