/// A descriptor says which features its fields need.
///
/// `RenderPassDescriptor.checkFeatures` was the one shared check; the
/// sampler, blend, texture and buffer descriptors left each backend to map
/// fields to features by hand, so a field a minor adds with its feature
/// would be ignored by a backend written before it. Each now answers for
/// its own fields, and each feature is asked for alone: a comparison
/// sampler does not need the level-of-detail clamp.
///
/// Mutation: ask for `samplerLodClamp` whenever `usesExtendedState` holds.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

Matcher _refusedFor(DeviceFeature feature) => throwsA(
  isA<UnsupportedCapabilityException>()
      .having(
        (UnsupportedCapabilityException e) => e.feature,
        'feature',
        feature,
      )
      .having(
        (UnsupportedCapabilityException e) => e.message,
        'message',
        contains('Null'),
      ),
);

void main() {
  group('SamplerDescriptor', () {
    test('a comparison sampler needs only the comparison', () {
      const sampler = SamplerDescriptor(compare: CompareFunction.less);
      sampler.checkFeatures(
        DeviceFeatures(<DeviceFeature>[DeviceFeature.samplerCompare]),
        backend: 'Null',
      );
      expect(
        () => sampler.checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.samplerCompare),
      );
    });

    test('a clamp and a border each name their own feature', () {
      expect(
        () => const SamplerDescriptor(
          lodMaxClamp: 4,
        ).checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.samplerLodClamp),
      );
      expect(
        () => const SamplerDescriptor(
          borderColor: SamplerBorderColor.opaqueBlack,
        ).checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.samplerBorderColor),
      );
    });

    test('a plain sampler needs nothing', () {
      SamplerDescriptor.linearRepeat.checkFeatures(
        DeviceFeatures.none,
        backend: 'Null',
      );
    });
  });

  group('BlendState', () {
    test('each extended blend names its feature', () {
      expect(
        () => const BlendState(
          sourceColorFactor: BlendFactor.blendColor,
        ).checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.blendConstant),
      );
      expect(
        () => const BlendState(
          colorOperation: BlendOperation.max,
        ).checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.minMaxBlend),
      );
      const BlendState().checkFeatures(DeviceFeatures.none, backend: 'Null');
    });
  });

  group('TextureDescriptor', () {
    test('a shape, a storage usage and samples each name a feature', () {
      expect(
        () => const TextureDescriptor(
          width: 4,
          height: 4,
          format: TextureFormat.r8g8b8a8UNormInt,
          dimension: TextureDimension.cube,
          depthOrArrayLayers: 6,
        ).checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.cubeTextures),
      );
      expect(
        () => const TextureDescriptor(
          width: 4,
          height: 4,
          format: TextureFormat.r8g8b8a8UNormInt,
          sampleCount: 4,
        ).checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.offscreenMultisample),
      );
      const TextureDescriptor(
        width: 4,
        height: 4,
        format: TextureFormat.r8g8b8a8UNormInt,
      ).checkFeatures(DeviceFeatures.none, backend: 'Null');
    });
  });

  group('BufferDescriptor', () {
    test('a storage buffer takes either feature, and names its shape', () {
      final render = DeviceFeatures(<DeviceFeature>[
        DeviceFeature.buffers,
        DeviceFeature.renderStageStorage,
      ]);
      const BufferDescriptor(
        lengthInBytes: 16,
        usage: BufferUsage.standardStorage,
      ).checkFeatures(render, backend: 'Null');
      expect(
        () =>
            const BufferDescriptor(
              lengthInBytes: 16,
              usage: BufferUsage.standardStorage,
            ).checkFeatures(
              DeviceFeatures(<DeviceFeature>[DeviceFeature.buffers]),
              backend: 'Null',
            ),
        _refusedFor(DeviceFeature.compute),
      );
      expect(
        () => const BufferDescriptor(
          lengthInBytes: 16,
          usage: BufferUsage.vertex,
        ).checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.buffers),
      );
    });
  });
}
