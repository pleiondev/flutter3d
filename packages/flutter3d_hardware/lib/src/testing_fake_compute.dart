/// Compute on the fake device: a pass that records what it was told and
/// runs nothing — since 1.0.0-rc.1.
///
/// **For a plugin author's test of a `ComputeStep`.** A step's `record`
/// can be handed a `FakeBackend(compute: true)` and asked what it did:
/// which pipeline it bound, which buffers by which names, how many
/// workgroups it dispatched, whether it submitted. Nothing is computed, so
/// a test of the numbers a kernel gives runs on `flutter3d_cpu` instead.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'compute_checks.dart';
import 'testing_recorded.dart';

/// A compute pass that records rather than runs: each call a
/// [RecordedCall] in [commands], in order, after the checks a real encoder
/// makes (the storage range and its alignment, the dispatch size).
final class FakeComputePass extends ComputeEncoder {
  /// A pass held to [limits], labelled [label].
  FakeComputePass({required this.limits, this.label});

  /// What the device that opened it reports.
  final DeviceLimits limits;

  /// The label it was opened with.
  final String? label;

  /// Everything recorded, in order.
  final List<RecordedCall> commands = <RecordedCall>[];

  /// Whether [submit] has run.
  bool get wasSubmitted => _submitted;
  bool _submitted = false;

  ComputePipelineHandle? _pipeline;

  /// How many dispatches were recorded.
  int get dispatches =>
      commands.where((RecordedCall c) => c.name == 'dispatch').length;

  @override
  void bindPipeline(ComputePipelineHandle pipeline) {
    _pipeline = pipeline;
    commands.add(RecordedCall('bindPipeline', arguments: pipeline));
  }

  @override
  bool bindStorageBuffer(
    ShaderHandle stage,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    final size = checkStorageBinding(
      buffer,
      limits,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
    commands.add(
      RecordedCall(
        'bindStorageBuffer',
        arguments: (
          name: name,
          buffer: buffer,
          offsetInBytes: offsetInBytes,
          sizeInBytes: size,
        ),
      ),
    );
    return true;
  }

  @override
  bool bindTexture(
    ShaderHandle stage,
    String name,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    commands.add(
      RecordedCall('bindTexture', arguments: (name: name, texture: texture)),
    );
    return true;
  }

  @override
  bool bindUniformBlock(
    ShaderHandle stage,
    String block,
    Map<String, Float32List> members,
  ) {
    commands.add(
      RecordedCall(
        'bindUniformBlock',
        arguments: (block: block, members: members),
      ),
    );
    return true;
  }

  @override
  void dispatch(int x, [int y = 1, int z = 1]) {
    if (_pipeline == null) {
      throw StateError('dispatch before any compute pipeline was bound');
    }
    checkDispatch(limits, x, y, z);
    commands.add(RecordedCall('dispatch', arguments: (x: x, y: y, z: z)));
  }

  @override
  void submit() {
    if (_submitted) throw StateError('this pass has already been submitted');
    _submitted = true;
    commands.add(const RecordedCall('submit'));
  }
}
