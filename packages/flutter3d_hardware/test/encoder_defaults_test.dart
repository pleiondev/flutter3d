/// What an encoder inherits for a feature-gated member it does not override.
///
/// **The promise of the base classes.** `PassEncoder`, `ComputeEncoder` and
/// `TransferEncoder` are extended by backends outside this repository, and a
/// member added to them in a minor must arrive with a body, or every such
/// backend stops compiling. So every member a `DeviceFeature` gates has one,
/// and it is the refusal the contract promises a device without the feature:
/// an `UnsupportedCapabilityException` naming that feature. These encoders override
/// nothing a feature gates; anything else they are asked answers with a
/// `StateError`, so a member left without a body fails here by name.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor, UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

final class _BarePass extends PassEncoder with CommandEncoder {
  final List<String> draws = <String>[];

  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) =>
      draws.add('draw $instanceCount $firstIndex $indexCount');

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName} has no default body');
}

final class _BareCompute extends ComputeEncoder {
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName} has no default body');
}

final class _BareTransfer extends TransferEncoder {
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName} has no default body');
}

Matcher _refuses(DeviceFeature feature) => throwsA(
  isA<UnsupportedCapabilityException>().having(
    (UnsupportedCapabilityException e) => e.feature,
    'feature',
    feature,
  ),
);

void main() {
  final device = FakeBackend(
    extraFeatures: const <DeviceFeature>[
      DeviceFeature.buffers,
      DeviceFeature.occlusionQuery,
      DeviceFeature.textureWrites,
    ],
  );
  final buffer = device.createBuffer(
    const BufferDescriptor(lengthInBytes: 64, usage: BufferUsage.indirect),
  );
  final texture = device.createTexture(
    const TextureDescriptor(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final queries = device.createQuerySet(QueryType.occlusion, 1);
  final shader = device.shaders['quad.vert']!;
  final at = TextureCopyLocation(texture);

  group(
    'a pass encoder refuses, by its feature, what it does not override',
    () {
      final cases = <String, (DeviceFeature, void Function(PassEncoder))>{
        'setBlendColor': (
          DeviceFeature.blendConstant,
          (p) => p.setBlendColor(LinearColor.black),
        ),
        'drawIndexed with a base vertex': (
          DeviceFeature.baseVertexBaseInstance,
          (p) => p.drawIndexed(const IndexedDraw(baseVertex: 1)),
        ),
        'multiDraw': (
          DeviceFeature.multiDraw,
          (p) => p.multiDraw(const <IndexedDraw>[IndexedDraw()]),
        ),
        'multiDrawIndirect': (
          DeviceFeature.multiDrawIndirect,
          (p) => p.multiDrawIndirect(buffer, 1),
        ),
        'executeBundles': (
          DeviceFeature.renderBundles,
          (p) => p.executeBundles(const <RenderBundle>[]),
        ),
        'beginPipelineStatisticsQuery': (
          DeviceFeature.pipelineStatisticsQuery,
          (p) => p.beginPipelineStatisticsQuery(queries, 0),
        ),
        'endPipelineStatisticsQuery': (
          DeviceFeature.pipelineStatisticsQuery,
          (p) => p.endPipelineStatisticsQuery(),
        ),
        'setDepthBias': (
          DeviceFeature.depthBias,
          (p) => p.setDepthBias(const DepthBias(constant: 1)),
        ),
        'setColorWriteMask': (
          DeviceFeature.colorWriteMask,
          (p) => p.setColorWriteMask(ColorWriteMask.red),
        ),
        'setDepthClamp': (
          DeviceFeature.depthClamp,
          (p) => p.setDepthClamp(enabled: true),
        ),
        'bindStorageBuffer': (
          DeviceFeature.renderStageStorage,
          (p) => p.bindStorageBuffer(shader, 'data', buffer),
        ),
        'bindStorageTexture': (
          DeviceFeature.renderStageStorage,
          (p) => p.bindStorageTexture(shader, 'image', texture),
        ),
        'bindUniformBytes': (
          DeviceFeature.uniformBytes,
          (p) => p.bindUniformBytes(shader, 'block', ByteData(16)),
        ),
        'drawIndirect': (
          DeviceFeature.indirectDraw,
          (p) => p.drawIndirect(buffer),
        ),
        'drawNonIndexed': (
          DeviceFeature.nonIndexedDraw,
          (p) => p.drawNonIndexed(vertexCount: 3),
        ),
        'beginOcclusionQuery': (
          DeviceFeature.occlusionQuery,
          (p) => p.beginOcclusionQuery(0),
        ),
        'endOcclusionQuery': (
          DeviceFeature.occlusionQuery,
          (p) => p.endOcclusionQuery(),
        ),
      };
      for (final MapEntry(key: name, value: (feature, call)) in cases.entries) {
        test(name, () => expect(() => call(_BarePass()), _refuses(feature)));
      }
    },
  );

  test('an indexed draw with no base vertex is an ordinary draw', () {
    // `drawIndexed` with both bases zero works on every device, so its
    // default is `draw` and not a refusal.
    final pass = _BarePass()
      ..drawIndexed(const IndexedDraw(firstIndex: 3, indexCount: 6));
    expect(pass.draws, <String>['draw 1 3 6']);
  });

  test('alpha to coverage is ignored, as a device without it promises', () {
    expect(
      () => _BarePass().setAlphaToCoverage(enabled: true),
      returnsNormally,
    );
  });

  group('a compute encoder refuses what it does not override', () {
    final cases = <String, (DeviceFeature, void Function(ComputeEncoder))>{
      'bindStorageTexture': (
        DeviceFeature.storageTextures,
        (c) => c.bindStorageTexture(shader, 'image', texture),
      ),
      'bindUniformBytes': (
        DeviceFeature.uniformBytes,
        (c) => c.bindUniformBytes(shader, 'block', ByteData(16)),
      ),
      'dispatchIndirect': (
        DeviceFeature.indirectDispatch,
        (c) => c.dispatchIndirect(buffer),
      ),
      'beginPipelineStatisticsQuery': (
        DeviceFeature.pipelineStatisticsQuery,
        (c) => c.beginPipelineStatisticsQuery(queries, 0),
      ),
      'endPipelineStatisticsQuery': (
        DeviceFeature.pipelineStatisticsQuery,
        (c) => c.endPipelineStatisticsQuery(),
      ),
    };
    for (final MapEntry(key: name, value: (feature, call)) in cases.entries) {
      test(name, () => expect(() => call(_BareCompute()), _refuses(feature)));
    }
  });

  group('a transfer encoder refuses what it does not override', () {
    final cases = <String, (DeviceFeature, void Function(TransferEncoder))>{
      'copyBufferToBuffer': (
        DeviceFeature.bufferCopy,
        (t) => t.copyBufferToBuffer(buffer, 0, buffer, 16, 16),
      ),
      'clearBuffer': (DeviceFeature.bufferCopy, (t) => t.clearBuffer(buffer)),
      'copyTextureToTexture': (
        DeviceFeature.textureCopy,
        (t) => t.copyTextureToTexture(at, at, width: 1, height: 1),
      ),
      'copyBufferToTexture': (
        DeviceFeature.bufferTextureCopy,
        (t) => t.copyBufferToTexture(
          buffer,
          const BufferTextureLayout(bytesPerRow: 256),
          at,
          width: 1,
          height: 1,
        ),
      ),
      'copyTextureToBuffer': (
        DeviceFeature.bufferTextureCopy,
        (t) => t.copyTextureToBuffer(
          at,
          buffer,
          const BufferTextureLayout(bytesPerRow: 256),
          width: 1,
          height: 1,
        ),
      ),
      'resolveTexture': (
        DeviceFeature.offscreenMultisample,
        (t) => t.resolveTexture(at, at),
      ),
    };
    for (final MapEntry(key: name, value: (feature, call)) in cases.entries) {
      test(name, () => expect(() => call(_BareTransfer()), _refuses(feature)));
    }
  });
}
