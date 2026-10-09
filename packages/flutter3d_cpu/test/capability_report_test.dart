/// What the software rasteriser says it can do, and that the pre-1.0
/// getters still say what they always said.
///
/// The conformance suite holds every backend to "a listed feature works and
/// an unlisted one refuses"; these hold this backend to its own list, so a
/// feature quietly dropped from it — or a legacy getter whose answer moved
/// when it was folded into the set — fails here by name.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

import 'support/cpu_rig.dart';

void main() {
  CpuDevice device({
    bool independentBlend = true,
    int attachments = 3,
    Iterable<DeviceFeature> withhold = const <DeviceFeature>[],
  }) => CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
    supportsIndependentBlend: independentBlend,
    maxColorAttachments: attachments,
    withhold: withhold,
  );

  test('the pre-1.0 getters answer exactly what they answered before', () {
    // Mutation: listing offscreenMultisample, wireframe or alphaToCoverage,
    // or dropping blendConstant, manualMipmaps, cubeTextures,
    // renderToMipLevel, stencil, compute or a float32 feature — each moves
    // one of these answers.
    final d = device();
    expect(d.features.has(DeviceFeature.offscreenMultisample), isFalse);
    expect(d.features.has(DeviceFeature.blendConstant), isTrue);
    expect(d.features.has(DeviceFeature.manualMipmaps), isTrue);
    expect(d.features.has(DeviceFeature.cubeTextures), isTrue);
    expect(d.features.has(DeviceFeature.renderToMipLevel), isTrue);
    expect(d.features.has(DeviceFeature.wireframe), isFalse);
    expect(d.features.has(DeviceFeature.alphaToCoverage), isFalse);
    expect(d.features.has(DeviceFeature.stencil), isTrue);
    expect(d.features.has(DeviceFeature.gpuTimestamps), isFalse);
    expect(d.features.has(DeviceFeature.compute), isTrue);
    expect(
      d.features.has(DeviceFeature.float32Filterable) &&
          d.features.has(DeviceFeature.float32Renderable),
      isTrue,
    );
    expect(d.features.has(DeviceFeature.independentBlend), isTrue);
    expect(d.limits.maxSamplerAnisotropy, 16);
    expect(d.limits.maxColorAttachments, 3);
    expect(d.preferredSampleCount, 1);
    for (final format in TextureFormat.values.where((f) => f.isMirrored)) {
      expect(
        d.textureFormatSupport(format).sampled,
        !format.isCompressed,
        reason: format.name,
      );
    }
  });

  test('the constructor flags still reach the getters', () {
    // Mutation: dropping `supportsIndependentBlend` or `maxColorAttachments`
    // on the way from the constructor into `features` and `limits`.
    final d = device(independentBlend: false, attachments: 1);
    expect(d.features.has(DeviceFeature.independentBlend), isFalse);
    expect(d.features.has(DeviceFeature.independentBlend), isFalse);
    expect(d.limits.maxColorAttachments, 1);
    expect(d.limits.maxColorAttachments, 1);
  });

  test('every 1.0 feature the rasteriser implements is listed, and the rest '
      'are not', () {
    // Mutation: removing any entry of `CpuDevice._implemented`, or adding
    // one that has no implementation behind it.
    final d = device();
    const listed = <DeviceFeature>[
      DeviceFeature.textureArrays,
      DeviceFeature.texture3D,
      DeviceFeature.cubeArrayTextures,
      DeviceFeature.renderToArrayLayer,
      DeviceFeature.textureWrites,
      DeviceFeature.buffers,
      DeviceFeature.bufferCopy,
      DeviceFeature.textureCopy,
      DeviceFeature.bufferTextureCopy,
      DeviceFeature.storageTextures,
      DeviceFeature.readWriteStorageTextures,
      DeviceFeature.renderStageStorage,
      DeviceFeature.indirectDraw,
      DeviceFeature.indirectDispatch,
      DeviceFeature.indirectFirstInstance,
      DeviceFeature.nonIndexedDraw,
      DeviceFeature.depthBias,
      DeviceFeature.colorWriteMask,
      DeviceFeature.depthClamp,
      DeviceFeature.minMaxBlend,
      DeviceFeature.dualSourceBlending,
      DeviceFeature.samplerCompare,
      DeviceFeature.samplerLodClamp,
      DeviceFeature.samplerBorderColor,
      DeviceFeature.occlusionQuery,
      DeviceFeature.timestampQuery,
      DeviceFeature.float32Blendable,
      DeviceFeature.mappedBuffers,
      DeviceFeature.synchronousReadback,
      DeviceFeature.pipelineStatisticsQuery,
      DeviceFeature.renderBundles,
      DeviceFeature.multiDraw,
      DeviceFeature.multiDrawIndirect,
      DeviceFeature.baseVertexBaseInstance,
    ];
    const absent = <DeviceFeature>[
      DeviceFeature.textureCompressionBC,
      DeviceFeature.textureCompressionETC2,
      DeviceFeature.textureCompressionASTC,
      DeviceFeature.textureCompressionASTCHdr,
      DeviceFeature.rg11b10Renderable,
      DeviceFeature.shaderF16,
      DeviceFeature.subgroups,
      DeviceFeature.clipDistances,
      DeviceFeature.uniformBytes,
    ];
    for (final f in listed) {
      expect(d.features.has(f), isTrue, reason: f.name);
    }
    for (final f in absent) {
      expect(d.features.has(f), isFalse, reason: f.name);
    }
  });

  test('the format table agrees with the families and with the store', () {
    // Mutation: answering sampled for a 32-bit integer format the float
    // store cannot hold, or renderable for an integer format whose writes
    // the rasteriser does not round.
    final d = device();
    expect(
      d.textureFormatSupport(TextureFormat.r32UInt),
      TextureFormatSupport.none,
    );
    expect(
      d.textureFormatSupport(TextureFormat.bc7RGBAUNormInt),
      TextureFormatSupport.none,
    );
    final uint8 = d.textureFormatSupport(TextureFormat.r8g8b8a8UInt);
    expect(uint8.sampled, isTrue);
    expect(uint8.filterable, isFalse);
    expect(uint8.renderable, isFalse);
    expect(uint8.storage, isTrue);
    final float32 = d.textureFormatSupport(TextureFormat.r32Float);
    expect(
      float32.filterable && float32.renderable && float32.blendable,
      isTrue,
    );
    expect(
      d.textureFormatSupport(TextureFormat.r11g11b10UFloat).renderable,
      isFalse,
    );
    expect(
      d.textureFormatSupport(TextureFormat.r8g8b8a8UNormIntSRGB).storage,
      isFalse,
    );
  });

  test('a withheld feature is refused by name, in the one refusal type', () {
    // Mutation: a gated call that skips `features.require`, so a device
    // built without the feature does the work anyway.
    final rig = Rig(withhold: const <DeviceFeature>[DeviceFeature.depthBias]);
    final pass = rig.pass();
    expect(
      () => pass.setDepthBias(const DepthBias(constant: 1)),
      throwsA(
        isA<UnsupportedCapability>().having(
          (UnsupportedCapability e) => e.feature,
          'feature',
          DeviceFeature.depthBias,
        ),
      ),
    );
    pass.submit();
  });

  test('wireframe, uniform bytes and resolves are refused as capabilities', () {
    // Mutation: refusing `PolygonMode.line` with a bare UnsupportedError,
    // or letting `bindUniformBytes` and `resolveTexture` answer at all.
    final rig = Rig();
    final pass = rig.pass();
    Matcher refusing(DeviceFeature f) => throwsA(
      isA<UnsupportedCapability>().having(
        (UnsupportedCapability e) => e.feature,
        'feature',
        f,
      ),
    );
    expect(
      () => pass.setPolygonMode(PolygonMode.line),
      refusing(DeviceFeature.wireframe),
    );
    expect(
      () => pass.bindUniformBytes(
        rig.device.shaders['Solid']!,
        'Block',
        ByteData(16),
      ),
      refusing(DeviceFeature.uniformBytes),
    );
    pass.submit();
    expect(
      () => rig.device.beginTransferPass().resolveTexture(
        TextureCopyLocation(rig.target),
        TextureCopyLocation(rig.target),
      ),
      refusing(DeviceFeature.offscreenMultisample),
    );
  });

  test(
    'a device without compute refuses its creators before anything else',
    () {
      // Mutation: looking at the bytes or the stage before the compute gate,
      // which the conformance probe calls with handles no device made.
      final d = device(withhold: const <DeviceFeature>[DeviceFeature.compute]);
      expect(
        () => d.createStorageBuffer(ByteData(16)),
        throwsA(isA<UnsupportedCapability>()),
      );
      expect(() => d.beginComputePass(), throwsA(isA<UnsupportedCapability>()));
    },
  );
}
