/// Every translation this table makes, held against WebGPU's own value sets.
///
/// **The specification's enumerations are written out here as literals, and that
/// is the point.** A test that only asserted "the answers are distinct" would
/// pass a `"cw"` typed where `"ccw"` was meant and a `"less-equal"` spelled
/// `"lessEqual"` — and both of those are a browser refusing a pipeline at run
/// time in a message about a dictionary member, on a machine with a GPU, which
/// is the worst place to find out. Written this way the answer has to be a value
/// the API actually has.
///
/// The one assertion that is not a lookup is the winding, which is inverted on
/// purpose and would be invisible if it were wrong.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/src/webgpu_formats.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GPUTextureFormat`, the subset a colour, depth or compressed texture in this
/// engine could land on.
const Set<String> _textureFormats = <String>{
  'r8unorm',
  'rg8unorm',
  'rgba8unorm',
  'rgba8unorm-srgb',
  'bgra8unorm',
  'bgra8unorm-srgb',
  'rgba32float',
  'rgba16float',
  'r32float',
  'stencil8',
  'depth24plus-stencil8',
  'depth32float-stencil8',
  'bc1-rgba-unorm',
  'bc1-rgba-unorm-srgb',
  'bc3-rgba-unorm',
  'bc3-rgba-unorm-srgb',
  'bc5-rg-unorm',
  'bc7-rgba-unorm',
  'bc7-rgba-unorm-srgb',
  'etc2-rgb8unorm',
  'etc2-rgb8unorm-srgb',
  'etc2-rgba8unorm',
  'etc2-rgba8unorm-srgb',
  'astc-4x4-unorm',
  'astc-4x4-unorm-srgb',
  'astc-8x8-unorm',
  'astc-8x8-unorm-srgb',
  'rgba8snorm',
  'rgba8uint',
  'rgba8sint',
  'r16float',
  'rg16float',
  'rgba16uint',
  'rgba16sint',
  'r32uint',
  'r32sint',
  'rg32float',
  'rg32uint',
  'rg32sint',
  'rgba32uint',
  'rgba32sint',
  'rgb10a2unorm',
  'rg11b10ufloat',
  'rgb9e5ufloat',
  'depth16unorm',
  'depth32float',
};

const Set<String> _blendFactors = <String>{
  'zero',
  'one',
  'src',
  'one-minus-src',
  'src-alpha',
  'one-minus-src-alpha',
  'dst',
  'one-minus-dst',
  'dst-alpha',
  'one-minus-dst-alpha',
  'src-alpha-saturated',
  'constant',
  'one-minus-constant',
  'src1',
  'one-minus-src1',
  'src1-alpha',
  'one-minus-src1-alpha',
};

const Set<String> _blendOperations = <String>{
  'add',
  'subtract',
  'reverse-subtract',
  'min',
  'max',
};

const Set<String> _compareFunctions = <String>{
  'never',
  'less',
  'equal',
  'less-equal',
  'greater',
  'not-equal',
  'greater-equal',
  'always',
};

const Set<String> _stencilOperations = <String>{
  'keep',
  'zero',
  'replace',
  'invert',
  'increment-clamp',
  'decrement-clamp',
  'increment-wrap',
  'decrement-wrap',
};

const Set<String> _topologies = <String>{
  'point-list',
  'line-list',
  'line-strip',
  'triangle-list',
  'triangle-strip',
};

const Set<String> _vertexFormats = <String>{
  'float32',
  'float32x2',
  'float32x3',
  'float32x4',
  'uint32',
  'uint32x2',
  'uint32x3',
  'uint32x4',
  'sint32',
  'sint32x2',
  'sint32x3',
  'sint32x4',
};

void main() {
  group('every value lands on a value WebGPU has', () {
    test('texture formats, or a stated null', () {
      // Three of the engine's formats have no WebGPU spelling; the rest must.
      const noSpelling = <TextureFormat>{
        TextureFormat.unknown,
        TextureFormat.a8UNormInt,
        TextureFormat.astc4x4HDR,
        TextureFormat.astc8x8HDR,
      };
      for (final format in TextureFormat.values) {
        final spelling = gpuTextureFormat(format);
        if (noSpelling.contains(format)) {
          expect(
            spelling,
            isNull,
            reason: '${format.name} has no WebGPU format and must say so',
          );
          continue;
        }
        expect(
          _textureFormats,
          contains(spelling),
          reason: '${format.name} maps to "$spelling", which WebGPU has not',
        );
      }
      // Distinct as well as valid: a table that mapped two formats onto one
      // spelling would allocate the wrong texture and read back plausibly.
      final spelled = <String>[
        for (final format in TextureFormat.values)
          if (gpuTextureFormat(format) != null) gpuTextureFormat(format)!,
      ];
      expect(spelled.toSet().length, spelled.length);
    });

    test('a compressed format names the feature it rides on', () {
      // The three families WebGPU makes optional, spelled as the specification
      // spells them. A misspelt name here is a device that quietly reports it
      // cannot sample BC7 on a machine that can, because `GPUSupportedFeatures`
      // answers false for a name it does not know rather than failing.
      const families = <String>{
        'texture-compression-bc',
        'texture-compression-etc2',
        'texture-compression-astc',
      };
      for (final format in TextureFormat.values) {
        final feature = gpuTextureFormatFeature(format);
        if (!format.isCompressed) {
          expect(
            feature,
            isNull,
            reason: '${format.name} is not compressed and needs no feature',
          );
          continue;
        }
        if (gpuTextureFormat(format) == null) {
          // The two HDR ASTC layouts: no spelling, so no feature could unlock
          // them. See `gpuTextureFormat`.
          expect(feature, isNull, reason: '${format.name} has no spelling');
          continue;
        }
        expect(
          families,
          contains(feature),
          reason: '${format.name} rides on "$feature", which WebGPU has not',
        );
      }
      // The family a format lands in is the family its spelling begins with,
      // which is the one cross-check that catches a BC7 filed under ETC2.
      for (final format in TextureFormat.values) {
        final spelling = gpuTextureFormat(format);
        final feature = gpuTextureFormatFeature(format);
        if (spelling == null || feature == null) continue;
        expect(
          spelling.startsWith(feature.substring('texture-compression-'.length)),
          isTrue,
          reason: '${format.name} is "$spelling" but rides on "$feature"',
        );
      }
    });

    test('a compressed level is measured in blocks, rounded up', () {
      // BC1: 4x4 blocks of eight bytes. A 16x16 level is four blocks across and
      // four down.
      final bc1 = gpuBlockLayoutOf(TextureFormat.bc1RGBAUNormInt, 16, 16);
      expect(bc1.bytesPerRow, 32);
      expect(bc1.rowsPerImage, 4);
      expect(bc1.byteLength, 128);

      // The tail of a chain, which is where the rounding matters: a 2x2 level of
      // a 4x4-block format is one whole block and not a quarter of one.
      final tail = gpuBlockLayoutOf(TextureFormat.bc1RGBAUNormInt, 2, 2);
      expect(tail.bytesPerRow, 8);
      expect(tail.rowsPerImage, 1);
      expect(tail.byteLength, 8);

      // Sixteen bytes a block rather than eight, and a wider footprint: the two
      // numbers that would look identical if the layout were assumed.
      final astc = gpuBlockLayoutOf(TextureFormat.astc8x8LDR, 16, 16);
      expect(astc.bytesPerRow, 32);
      expect(astc.rowsPerImage, 2);
      expect(astc.byteLength, 64);

      // The arithmetic that is wrong by one for exactly the sizes nobody tries:
      // a level that is not whole blocks still occupies whole blocks.
      final ragged = gpuBlockLayoutOf(TextureFormat.bc7RGBAUNormInt, 5, 5);
      expect(ragged.bytesPerRow, 32);
      expect(ragged.rowsPerImage, 2);
      expect(ragged.byteLength, 64);
    });

    test('blend factors, and the two that have no spelling', () {
      for (final factor in BlendFactor.values) {
        final spelling = gpuBlendFactor(factor);
        if (factor == BlendFactor.blendAlpha ||
            factor == BlendFactor.oneMinusBlendAlpha) {
          expect(
            spelling,
            isNull,
            reason:
                '${factor.name} is CONSTANT_ALPHA, which WebGPU has no '
                'equivalent of in the colour equation',
          );
          continue;
        }
        expect(_blendFactors, contains(spelling));
      }
    });

    test('blend operations', () {
      for (final operation in BlendOperation.values) {
        expect(_blendOperations, contains(gpuBlendOperation(operation)));
      }
    });

    test('compare functions, one per value and all eight distinct', () {
      final spelled = <String>[
        for (final compare in CompareFunction.values)
          gpuCompareFunction(compare),
      ];
      for (final spelling in spelled) {
        expect(_compareFunctions, contains(spelling));
      }
      expect(spelled.toSet().length, CompareFunction.values.length);
    });

    test('stencil operations', () {
      final spelled = <String>[
        for (final operation in StencilOperation.values)
          gpuStencilOperation(operation),
      ];
      for (final spelling in spelled) {
        expect(_stencilOperations, contains(spelling));
      }
      expect(spelled.toSet().length, StencilOperation.values.length);
      expect(
        gpuStencilOperation(StencilOperation.setToReferenceValue),
        'replace',
      );
    });

    test('primitive topologies', () {
      final spelled = <String>[
        for (final type in PrimitiveType.values) gpuPrimitiveTopology(type),
      ];
      for (final spelling in spelled) {
        expect(_topologies, contains(spelling));
      }
      expect(spelled.toSet().length, PrimitiveType.values.length);
    });

    test('vertex formats', () {
      final spelled = <String>[
        for (final format in VertexFormat.values) gpuVertexFormat(format),
      ];
      for (final spelling in spelled) {
        expect(_vertexFormats, contains(spelling));
      }
      expect(spelled.toSet().length, VertexFormat.values.length);
    });

    test('cull modes, address modes, filters, index formats, step modes', () {
      expect(
        <String>[for (final mode in CullMode.values) gpuCullMode(mode)],
        <String>['none', 'front', 'back'],
      );
      expect(
        <String>[
          for (final mode in SamplerAddressMode.values) gpuAddressMode(mode),
        ],
        <String>['clamp-to-edge', 'repeat', 'mirror-repeat'],
      );
      expect(
        <String>[
          for (final filter in MinMagFilter.values) gpuFilterMode(filter),
        ],
        <String>['nearest', 'linear'],
      );
      expect(
        <String>[
          for (final filter in MipFilter.values) gpuMipmapFilterMode(filter),
        ],
        <String>['nearest', 'linear'],
      );
      expect(
        <String>[for (final type in IndexType.values) gpuIndexFormat(type)],
        <String>['uint16', 'uint32'],
      );
      expect(
        <String>[
          for (final mode in VertexStepMode.values) gpuVertexStepMode(mode),
        ],
        <String>['vertex', 'instance'],
      );
    });
  });

  group('the conventions that are not lookups', () {
    /// **The value this table cannot establish on its own**, kept here so that
    /// changing it means changing a test rather than a word in a descriptor.
    ///
    /// The argument from coordinate systems predicts the crossed mapping —
    /// WebGPU's framebuffer y runs down, and a Vulkan port, which faces the same
    /// arrangement, does have to cross it. `webgpu_triangle_test.dart` draws the
    /// two-by-two of winding against cull mode on a real GPU and refuses that
    /// prediction; this is the answer it came back with, written where a reader
    /// meets the table.
    test('a clip-space counter-clockwise winding is WebGPU "ccw"', () {
      expect(gpuFrontFace(WindingOrder.counterClockwise), 'ccw');
      expect(gpuFrontFace(WindingOrder.clockwise), 'cw');
    });

    test('a resolve is an attachment field, not a store operation', () {
      expect(gpuStoreOp(StoreAction.store), 'store');
      expect(gpuStoreOp(StoreAction.dontCare), 'discard');
      // The two resolving actions differ only in whether the multisampled
      // texture survives, which in WebGPU is exactly the store op beside a
      // resolve target.
      expect(gpuStoreOp(StoreAction.multisampleResolve), 'discard');
      expect(gpuStoreOp(StoreAction.storeAndMultisampleResolve), 'store');
      expect(gpuResolves(StoreAction.multisampleResolve), isTrue);
      expect(gpuResolves(StoreAction.storeAndMultisampleResolve), isTrue);
      expect(gpuResolves(StoreAction.store), isFalse);
      expect(gpuResolves(StoreAction.dontCare), isFalse);
    });

    test('a load that does not care clears rather than loading', () {
      expect(gpuLoadOp(LoadAction.load), 'load');
      expect(gpuLoadOp(LoadAction.clear), 'clear');
      expect(gpuLoadOp(LoadAction.dontCare), 'clear');
    });

    test('tile memory is a transient attachment where the browser has it', () {
      // `H7`. Mutation: drop the storage-mode check, and every render target
      // is allocated unsampleable; drop the `supported` one, and a browser
      // without the flag refuses the texture.
      const tile = RenderTargetDescriptor(
        width: 4,
        height: 4,
        format: TextureFormat.d32FloatS8UInt,
        storageMode: StorageMode.deviceTransient,
      );
      const kept = RenderTargetDescriptor(
        width: 4,
        height: 4,
        format: TextureFormat.r16g16b16a16Float,
      );
      expect(webgpuIsTransientAttachment(tile, supported: true), isTrue);
      expect(webgpuIsTransientAttachment(tile, supported: false), isFalse);
      expect(webgpuIsTransientAttachment(kept, supported: true), isFalse);
    });

    test('a transient attachment is cleared and discarded, whatever the '
        'pass asked', () {
      // WebGPU refuses "load" from one and "store" into one. Mutation: return
      // the pass's own operation, and a pass that keeps its MSAA samples
      // stores into a texture that has no memory.
      for (final action in LoadAction.values) {
        expect(gpuAttachmentLoadOp(action, transient: true), 'clear');
        expect(
          gpuAttachmentLoadOp(action, transient: false),
          gpuLoadOp(action),
        );
      }
      for (final action in StoreAction.values) {
        expect(gpuAttachmentStoreOp(action, transient: true), 'discard');
        expect(
          gpuAttachmentStoreOp(action, transient: false),
          gpuStoreOp(action),
        );
      }
    });

    test('a write is padded to four bytes, and only when it needs it', () {
      // Three sixteen-bit indices: the smallest draw in the engine, six bytes,
      // and the length `writeBuffer` refuses.
      final indices = Uint16List.fromList(<int>[0, 1, 2]);
      final padded = gpuWritableBytes(ByteData.sublistView(indices));
      expect(padded.length, 8);
      expect(padded.sublist(0, 6), <int>[0, 0, 1, 0, 2, 0]);
      expect(padded.sublist(6), <int>[0, 0]);

      // An aligned length is handed straight through: a copy here would be a
      // copy of every vertex buffer in a frame, for nothing.
      final vertices = Float32List.fromList(<double>[1, 2, 3]);
      final view = ByteData.sublistView(vertices);
      expect(gpuWritableBytes(view).length, 12);

      for (var length = 0; length <= 32; length++) {
        final written = gpuWritableBytes(ByteData(length));
        expect(written.length % 4, 0, reason: '$length bytes is not padded');
        expect(written.length - length, lessThan(4));
      }
    });

    test('a readback row is padded to 256 bytes, and not over-padded', () {
      // Already aligned: 64 pixels is 256 bytes exactly and must be left alone.
      expect(paddedBytesPerRow(64), 256);
      expect(paddedBytesPerRow(128), 512);
      // The editor's pick, which is the cheapest region there is and the one
      // that pays the most padding.
      expect(paddedBytesPerRow(1), 256);
      // The golden window's width. 1920 bytes is not a multiple of 256, which
      // is exactly the arithmetic somebody does in their head and gets wrong:
      // 480 is a round number of pixels and its row is not a round number of
      // blocks.
      expect(paddedBytesPerRow(480), 2048);
      // A width that lands mid-block.
      expect(paddedBytesPerRow(65), 512);
      for (var width = 1; width <= 600; width++) {
        final stride = paddedBytesPerRow(width);
        expect(stride % 256, 0, reason: 'width $width is not 256-aligned');
        expect(stride, greaterThanOrEqualTo(width * 4));
        expect(stride - width * 4, lessThan(256));
      }
    });
  });

  group('the pipeline key carries everything WebGPU bakes in', () {
    WebGpuPipelineKey key({
      String pipeline = 'A+B',
      String topology = 'triangle-list',
      String cullMode = 'back',
      String frontFace = 'cw',
      String depthCompare = 'less',
      bool depthWrite = true,
      BlendState? blend,
      List<String> colorFormats = const <String>['rgba8unorm'],
      String? depthFormat = 'depth24plus-stencil8',
      int sampleCount = 1,
    }) => WebGpuPipelineKey(
      pipeline: pipeline,
      topology: topology,
      cullMode: cullMode,
      frontFace: frontFace,
      depthCompare: depthCompare,
      depthWrite: depthWrite,
      blend: blend,
      colorFormats: colorFormats,
      depthFormat: depthFormat,
      sampleCount: sampleCount,
    );

    test('two draws in the same state share one pipeline', () {
      expect(key(), key());
      expect(key().hashCode, key().hashCode);
    });

    /// Every field, one at a time. A key that dropped one would hand a draw the
    /// pipeline built for the state before it — which on this API is not a
    /// missing pipeline but a picture drawn with the wrong cull mode, the wrong
    /// depth test or the wrong blend, and no error anywhere.
    test('a change to any one field is a different pipeline', () {
      final baseline = key();
      expect(key(pipeline: 'C+D'), isNot(baseline));
      expect(key(topology: 'line-list'), isNot(baseline));
      expect(key(cullMode: 'none'), isNot(baseline));
      expect(key(frontFace: 'ccw'), isNot(baseline));
      expect(key(depthCompare: 'less-equal'), isNot(baseline));
      expect(key(depthWrite: false), isNot(baseline));
      expect(key(blend: BlendState.alphaBlend), isNot(baseline));
      expect(key(colorFormats: const <String>['rgba16float']), isNot(baseline));
      expect(
        key(colorFormats: const <String>['rgba8unorm', 'rgba8unorm']),
        isNot(baseline),
      );
      expect(key(depthFormat: null), isNot(baseline));
      expect(key(sampleCount: 4), isNot(baseline));
    });

    test('two blend equations are two pipelines', () {
      expect(
        key(blend: BlendState.alphaBlend),
        isNot(key(blend: BlendState.additive)),
      );
      expect(key(blend: BlendState.alphaBlend), key(blend: BlendState()));
    });
  });

  group('what a device was granted decides what it reports', () {
    bool none(String _) => false;
    bool all(String _) => true;

    test('the pre-1.0 answers are what they were', () {
      // `DeviceCapabilityForwarders` reads these; the getters they replaced
      // answered exactly this on every adapter.
      //
      // Mutation: make `float32-renderable` depend on a grant. On an adapter
      // without `float32-filterable` nothing changes, and on one with it
      // `supportsFloat32Filtering` goes false where it used to be true.
      final bare = webgpuDeviceFeatures(granted: none);
      for (final yes in <DeviceFeature>[
        DeviceFeature.offscreenMultisample,
        DeviceFeature.manualMipmaps,
        DeviceFeature.cubeTextures,
        DeviceFeature.renderToMipLevel,
        DeviceFeature.alphaToCoverage,
        DeviceFeature.stencil,
        DeviceFeature.compute,
        DeviceFeature.independentBlend,
        DeviceFeature.float32Renderable,
      ]) {
        expect(bare.has(yes), isTrue, reason: yes.name);
      }
      for (final no in <DeviceFeature>[
        DeviceFeature.blendConstant,
        DeviceFeature.wireframe,
        DeviceFeature.gpuTimestamps,
        DeviceFeature.float32Filterable,
      ]) {
        expect(bare.has(no), isFalse, reason: no.name);
      }
      final full = webgpuDeviceFeatures(granted: all);
      expect(full.has(DeviceFeature.gpuTimestamps), isTrue);
      expect(
        full.has(DeviceFeature.float32Filterable) &&
            full.has(DeviceFeature.float32Renderable),
        isTrue,
      );
    });

    test('an adapter feature is reported only when it was granted', () {
      // Mutation: list `depth-clip-control`'s feature unconditionally. A device
      // without it then promises `setDepthClamp`, and the pipeline it builds
      // with `unclippedDepth: true` is refused by the browser.
      const behindGrant = <DeviceFeature, String>{
        DeviceFeature.depthClamp: 'depth-clip-control',
        DeviceFeature.indirectFirstInstance: 'indirect-first-instance',
        DeviceFeature.dualSourceBlending: 'dual-source-blending',
        DeviceFeature.timestampQuery: 'timestamp-query',
        DeviceFeature.float32Blendable: 'float32-blendable',
        DeviceFeature.rg11b10Renderable: 'rg11b10ufloat-renderable',
        DeviceFeature.shaderF16: 'shader-f16',
        DeviceFeature.subgroups: 'subgroups',
        DeviceFeature.clipDistances: 'clip-distances',
        DeviceFeature.textureCompressionBC: 'texture-compression-bc',
        DeviceFeature.multiDrawIndirect: 'multi-draw-indirect',
      };
      for (final MapEntry(key: feature, value: name) in behindGrant.entries) {
        expect(
          webgpuDeviceFeatures(granted: none).has(feature),
          isFalse,
          reason: '${feature.name} without $name',
        );
        expect(
          webgpuDeviceFeatures(granted: (String f) => f == name).has(feature),
          isTrue,
          reason: '${feature.name} with $name',
        );
      }
    });

    test('what WebGPU cannot do is never reported, whatever is granted', () {
      // Mutation: list `sampler-border-color`. The conformance check then
      // binds a border sampler and the browser has no field to put it in.
      final full = webgpuDeviceFeatures(granted: all);
      for (final no in <DeviceFeature>[
        DeviceFeature.blendConstant,
        DeviceFeature.wireframe,
        DeviceFeature.renderStageStorage,
        DeviceFeature.samplerBorderColor,
        DeviceFeature.textureCompressionASTCHdr,
        DeviceFeature.synchronousReadback,
        DeviceFeature.pipelineStatisticsQuery,
      ]) {
        expect(full.has(no), isFalse, reason: no.name);
      }
    });

    test('the format table agrees with the features about the same thing', () {
      // The conformance honesty check asks both questions and wants one
      // answer. Mutation: answer r32float's `filterable` true without the
      // grant. A sampler then filters a texture the layout calls
      // unfilterable, and the pipeline does not build.
      for (final granted in <bool Function(String)>[none, all]) {
        final features = webgpuDeviceFeatures(granted: granted);
        TextureFormatSupport of(TextureFormat f) =>
            webgpuTextureFormatSupport(f, granted: granted);
        expect(
          of(TextureFormat.r32Float).filterable,
          features.has(DeviceFeature.float32Filterable),
        );
        expect(
          of(TextureFormat.r32Float).renderable,
          features.has(DeviceFeature.float32Renderable),
        );
        expect(
          of(TextureFormat.r32Float).blendable,
          features.has(DeviceFeature.float32Blendable),
        );
        expect(
          of(TextureFormat.r11g11b10UFloat).renderable,
          features.has(DeviceFeature.rg11b10Renderable),
        );
        expect(
          of(TextureFormat.bc7RGBAUNormInt).sampled,
          features.has(DeviceFeature.textureCompressionBC),
        );
        expect(
          of(TextureFormat.etc2RGBA8UNormInt).sampled,
          features.has(DeviceFeature.textureCompressionETC2),
        );
        expect(
          of(TextureFormat.astc4x4LDR).sampled,
          features.has(DeviceFeature.textureCompressionASTC),
        );
        expect(of(TextureFormat.astc4x4HDR), TextureFormatSupport.none);
      }
    });

    test('sampled is what supportsTextureFormat always answered', () {
      // Mutation: ask the depth32float-stencil8 feature for `sampled`. The
      // legacy getter answered true for it on every adapter, and the
      // forwarder may not change a legacy answer.
      for (final format in TextureFormat.values) {
        final family = gpuTextureFormatFeature(format);
        final legacy = gpuTextureFormat(format) != null && family == null;
        expect(
          webgpuTextureFormatSupport(format, granted: none).sampled,
          legacy,
          reason: format.name,
        );
      }
    });

    test('read-write storage is the three formats WebGPU allows', () {
      // Mutation: mark rgba8unorm read-write. A stage declared that way is a
      // pipeline the browser refuses.
      final readWrite = <TextureFormat>[
        for (final format in TextureFormat.values)
          if (webgpuTextureFormatSupport(format, granted: all).storageReadWrite)
            format,
      ];
      expect(readWrite, <TextureFormat>[
        TextureFormat.r32Float,
        TextureFormat.r32UInt,
        TextureFormat.r32SInt,
      ]);
    });
  });

  group('copies', () {
    test('an encoded copy refuses a row stride that is not 256-aligned', () {
      // Mutation: accept any positive stride. The copy is then an invalid
      // command buffer, refused asynchronously with nothing naming the call.
      expect(() => gpuCheckCopyBytesPerRow(256), returnsNormally);
      expect(() => gpuCheckCopyBytesPerRow(512), returnsNormally);
      expect(() => gpuCheckCopyBytesPerRow(16), throwsArgumentError);
      expect(() => gpuCheckCopyBytesPerRow(0), throwsArgumentError);
    });

    test('depth copies follow the direction the specification allows', () {
      // Mutation: give depth32float a layout into the texture too. A write
      // into it is then refused by the browser rather than here.
      expect(
        gpuCopyBlock(TextureFormat.d32Float, intoTexture: false),
        isNotNull,
      );
      expect(gpuCopyBlock(TextureFormat.d32Float, intoTexture: true), isNull);
      expect(
        gpuCopyBlock(TextureFormat.d16UNormInt, intoTexture: true),
        isNotNull,
      );
      expect(
        gpuCopyBlock(TextureFormat.d24UnormS8Uint, intoTexture: false),
        isNull,
      );
      expect(gpuCopyBlock(TextureFormat.bc7RGBAUNormInt, intoTexture: true), (
        blockWidth: 4,
        blockHeight: 4,
        bytesPerBlock: 16,
      ));
      expect(gpuCopyBlock(TextureFormat.r16g16b16a16Float, intoTexture: true), (
        blockWidth: 1,
        blockHeight: 1,
        bytesPerBlock: 8,
      ));
    });

    test('min and max are spelled, and so are the source1 factors', () {
      expect(gpuBlendOperation(BlendOperation.min), 'min');
      expect(gpuBlendOperation(BlendOperation.max), 'max');
      expect(gpuBlendFactor(BlendFactor.source1Alpha), 'src1-alpha');
    });
  });
}
