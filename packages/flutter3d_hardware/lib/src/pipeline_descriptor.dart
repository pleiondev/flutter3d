/// What a pipeline is built from, as one value.
///
/// **Why a descriptor and not parameters.** A member an outside backend
/// overrides can never gain a parameter within a major: Dart makes every
/// override accept every parameter of what it overrides, so a parameter added
/// to `GraphicsDevice.createPipeline` in a minor would break every backend
/// written before it. A field added to a descriptor breaks nobody. So every
/// input a pipeline gains after 1.0 (specialisation constants, a cache blob,
/// a hint of the pass state it will draw under, another kind of stage)
/// arrives as a field here with a default that means what the pipeline did
/// before, and `GraphicsDevice.createPipelineFrom` is the one entry point
/// that reads it.
library;

import 'package:meta/meta.dart';

import 'shader.dart';
import 'vertex_layout_spec.dart';

/// A vertex and a fragment stage, the layout their vertex inputs come from,
/// and a name: everything `GraphicsDevice.createPipelineFrom` links.
///
/// The fields are `GraphicsDevice.createPipeline`'s parameters with the same
/// defaults, plus [label]. A later minor adds fields with defaults; a backend
/// written before a field existed still builds what the descriptor described
/// before it, and a field that needs a capability is refused through the
/// feature it names rather than ignored.
@immutable
final class PipelineDescriptor {
  /// The pipeline linking [vertex] and [fragment], reading its vertex inputs
  /// as [layout] says.
  const PipelineDescriptor({
    required this.vertex,
    required this.fragment,
    this.layout,
    this.label,
  });

  /// The vertex stage.
  final ShaderHandle vertex;

  /// The fragment stage.
  final ShaderHandle fragment;

  /// Where the vertex inputs come from; **null means the backend works it
  /// out from the shader**, as `GraphicsDevice.createPipeline` says. A cache
  /// keys on it: two layouts over one pair are two pipelines.
  final VertexLayoutDescriptor? layout;

  /// The pipeline's name for a GPU debugger, a frame capture and the memory
  /// report, given through `GraphicsDevice.setLabel`; null for none.
  final String? label;

  /// Equal when every field is: the same stages, the same layout object and
  /// the same label. A layout compares by identity, as the engine's caches
  /// have always keyed it.
  @override
  bool operator ==(Object other) =>
      other is PipelineDescriptor &&
      identical(other.vertex, vertex) &&
      identical(other.fragment, fragment) &&
      identical(other.layout, layout) &&
      other.label == label;

  @override
  int get hashCode => Object.hash(
    identityHashCode(vertex),
    identityHashCode(fragment),
    identityHashCode(layout),
    label,
  );

  @override
  String toString() =>
      'PipelineDescriptor(${vertex.name}, ${fragment.name}'
      '${layout == null ? '' : ', ${layout!.buffers.length} buffers'}'
      '${label == null ? '' : ', $label'})';
}

/// A compute stage and a name: everything
/// `GraphicsDevice.createComputePipelineFrom` builds.
///
/// `GraphicsDevice.createComputePipeline`'s one parameter as a field, plus
/// [label], and room for what a compute pipeline gains in a minor
/// (specialisation constants, a workgroup size chosen at creation) as fields
/// with defaults, for [PipelineDescriptor]'s reason.
@immutable
final class ComputePipelineDescriptor {
  /// The pipeline running [shader].
  const ComputePipelineDescriptor({required this.shader, this.label});

  /// The compute stage.
  final ShaderHandle shader;

  /// The pipeline's name for a GPU debugger, as [PipelineDescriptor.label].
  final String? label;

  /// Equal for the same stage and the same label.
  @override
  bool operator ==(Object other) =>
      other is ComputePipelineDescriptor &&
      identical(other.shader, shader) &&
      other.label == label;

  @override
  int get hashCode => Object.hash(identityHashCode(shader), label);

  @override
  String toString() =>
      'ComputePipelineDescriptor(${shader.name}'
      '${label == null ? '' : ', $label'})';
}
