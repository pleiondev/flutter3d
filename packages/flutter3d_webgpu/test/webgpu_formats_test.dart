/// Every translation this spike makes, held against WebGPU's own value sets.
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
import 'package:flutter3d_webgpu/flutter3d_webgpu.dart';
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
}
