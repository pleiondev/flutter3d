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
import 'package:flutter3d_hardware/backend.dart' show wrapTexture;
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
          heightAddressMode: SamplerAddressMode.clampToBorder,
          borderColor: SamplerBorderColor.opaqueBlack,
        ).checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.samplerBorderColor),
      );
    });

    test('any clampToBorder axis needs the border, even with no colour', () {
      // Mutation: ask for the border only when `borderColor` is set. A
      // sampler clamping its depth axis to the transparent-black default
      // reaches a backend with no border, which clamps to the edge instead.
      expect(
        () => const SamplerDescriptor(
          depthAddressMode: SamplerAddressMode.clampToBorder,
        ).checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.samplerBorderColor),
      );
      expect(
        const SamplerDescriptor(
          widthAddressMode: SamplerAddressMode.clampToBorder,
        ).usesExtendedState,
        isTrue,
      );
    });

    test('a border colour with no clampToBorder axis needs nothing', () {
      // Mutation: keep asking for the border whenever a colour is set. A
      // sampler whose colour no axis uses is refused for a border it never
      // samples.
      const SamplerDescriptor(
        borderColor: SamplerBorderColor.opaqueWhite,
      ).checkFeatures(DeviceFeatures.none, backend: 'Null');
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
    test('a 1D texture names its feature', () {
      // Mutation: `d1` mapped to no feature again, and a device without 1D
      // textures refuses one untyped, or makes it, with nothing to ask first.
      const line = TextureDescriptor(
        width: 4,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        dimension: TextureDimension.d1,
      );
      line.checkFeatures(
        DeviceFeatures(<DeviceFeature>[DeviceFeature.texture1D]),
        backend: 'Null',
      );
      expect(
        () => line.checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.texture1D),
      );
    });

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

  group('DepthBias', () {
    test('a bias needs depthBias, and a clamp needs its own feature', () {
      // Mutation: `checkFeatures` ignoring the clamp leaves a backend without
      // one drawing unclamped, or refusing untyped, as WebGL2 used to.
      const clamped = DepthBias(constant: 1, clamp: 0.01);
      expect(
        () => const DepthBias(
          constant: 1,
        ).checkFeatures(DeviceFeatures.none, backend: 'Null'),
        _refusedFor(DeviceFeature.depthBias),
      );
      const DepthBias(constant: 1).checkFeatures(
        DeviceFeatures(<DeviceFeature>[DeviceFeature.depthBias]),
        backend: 'Null',
      );
      expect(
        () => clamped.checkFeatures(
          DeviceFeatures(<DeviceFeature>[DeviceFeature.depthBias]),
          backend: 'Null',
        ),
        _refusedFor(DeviceFeature.depthBiasClamp),
      );
      clamped.checkFeatures(
        DeviceFeatures(<DeviceFeature>[
          DeviceFeature.depthBias,
          DeviceFeature.depthBiasClamp,
        ]),
        backend: 'Null',
      );
    });
  });

  group('RenderPassDescriptor', () {
    test('a pass over the attachment limit is a typed refusal', () {
      // Mutation: throw an untyped `UnsupportedError`, as the limit did; a
      // caller catching the device's refusals cannot tell it from a bug.
      final colors = <ColorTarget>[
        for (var i = 0; i < 2; i++)
          ColorTarget(
            texture: wrapTexture(
              backend: Object(),
              width: 1,
              height: 1,
              format: TextureFormat.r8g8b8a8UNormInt,
            ),
          ),
      ];
      final pass = RenderPassDescriptor(colors: colors);
      pass.checkAttachmentLimit(2, backend: 'Null');
      expect(
        () => pass.checkAttachmentLimit(1, backend: 'Null'),
        throwsA(
          isA<DeviceResourceException>()
              .having((e) => e.operation, 'operation', 'beginRenderPass')
              .having((e) => e.message, 'message', contains('at most 1')),
        ),
      );
    });
  });
}
