/// The 1.0 draws and pass state on the software rasteriser: non-indexed,
/// base-vertex, indirect and multi-indirect draws, depth bias and clamp,
/// write masks, min/max and dual-source blending, render-stage storage,
/// queries and bundles.
///
/// Every fixture is a four-by-one target, so a draw's footprint is a set of
/// columns and the picture is four numbers.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/cpu_rig.dart';

/// Adds one to the first word of the storage buffer `Counts` per fragment,
/// and declares that buffer and nothing else.
final class _CountFragments extends CpuFragmentShader with CpuStorageReader {
  const _CountFragments();

  @override
  Set<String> get storageBindings => const <String>{'Counts'};

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final counts = b.storage['Counts']!;
    counts.setUint32(0, counts.getUint32(0, Endian.little) + 1, Endian.little);
    return Vector4(1, 1, 1, 1);
  }
}

List<double> _reds(Rig rig) => <double>[
  for (var x = 0; x < rig.width; x++) rig.redAt(x),
];

void main() {
  test('drawNonIndexed draws in order and ignores the bound indices', () {
    // Mutation: `drawNonIndexed` reading through the bound index buffer,
    // which here names one vertex three times and draws nothing.
    final rig = Rig();
    rig.pass()
      ..bindVertexData(fullScreen(), 3)
      ..bindIndexData(
        ByteData.sublistView(Uint16List.fromList(<int>[0, 0, 0])),
        IndexType.int16,
        3,
      )
      ..drawNonIndexed(vertexCount: 3)
      ..submit();
    expect(_reds(rig), <double>[1, 1, 1, 1]);
  });

  test('a base vertex is added to every index', () {
    // Mutation: `_drawOnce` dropping `baseVertex`, which draws the first
    // quad, in column zero, instead of the second.
    final rig = Rig();
    final first = columnQuad(0);
    final second = columnQuad(2);
    final vertices = Uint8List(96)
      ..setAll(0, Uint8List.sublistView(first.vertices))
      ..setAll(48, Uint8List.sublistView(second.vertices));
    rig.pass()
      ..bindVertexData(ByteData.sublistView(vertices), 8)
      ..bindIndexData(first.indices, IndexType.int16, 6)
      ..drawIndexed(const IndexedDraw(baseVertex: 4))
      ..submit();
    expect(_reds(rig), <double>[0, 0, 1, 0]);
  });

  test('an indirect draw reads its counts and first instance from the '
      'buffer, and the occlusion query counts what it drew', () async {
    // Mutation: `_drawIndirect` starting at instance zero, which lights
    // columns zero and one; or the occlusion counter left out of the
    // triangle loop, which answers nought.
    final rig = Rig();
    final quad = columnQuad(0);
    final arguments = rig.device.createBuffer(
      const BufferDescriptor(lengthInBytes: 20, usage: BufferUsage.indirect),
      contents: drawIndexedIndirectArguments(
        indexCount: 6,
        instanceCount: 2,
        firstInstance: 1,
      ),
    );
    final queries = rig.device.createQuerySet(QueryType.occlusion, 1);
    rig.pass(occlusion: queries)
      ..bindVertexData(quad.vertices, 4)
      ..bindIndexData(quad.indices, IndexType.int16, 6)
      ..beginOcclusionQuery(0)
      ..drawIndirect(arguments)
      ..endOcclusionQuery()
      ..submit();
    expect(_reds(rig), <double>[0, 1, 1, 0]);
    expect(await rig.device.readQueryResults(queries), <int>[2]);
  });

  test('a count buffer caps a multi-draw-indirect', () {
    // Mutation: `multiDrawIndirect` drawing `drawCount` records whatever
    // the count buffer holds.
    final rig = Rig();
    final quad = columnQuad(0);
    final records = Uint8List(40)
      ..setAll(
        0,
        Uint8List.sublistView(drawIndexedIndirectArguments(indexCount: 6)),
      )
      ..setAll(
        20,
        Uint8List.sublistView(
          drawIndexedIndirectArguments(indexCount: 6, firstInstance: 3),
        ),
      );
    final arguments = rig.device.createBuffer(
      const BufferDescriptor(lengthInBytes: 40, usage: BufferUsage.indirect),
      contents: ByteData.sublistView(records),
    );
    final count = rig.device.createBuffer(
      const BufferDescriptor(lengthInBytes: 4, usage: BufferUsage.indirect),
      contents: ByteData(4)..setUint32(0, 1, Endian.little),
    );
    rig.pass()
      ..bindVertexData(quad.vertices, 4)
      ..bindIndexData(quad.indices, IndexType.int16, 6)
      ..multiDrawIndirect(arguments, 2, countBuffer: count)
      ..submit();
    expect(_reds(rig), <double>[1, 0, 0, 0]);
  });

  test('a constant depth bias moves depth by the format\'s step, and the '
      'clamp holds it', () {
    // Mutation: `_biasOf` using a unorm step for the float depth, or
    // ignoring `DepthBias.clamp`.
    final step = math.pow(2.0, -24).toDouble();
    final biased = Rig(withDepth: true);
    biased.pass()
      ..setDepthBias(const DepthBias(constant: 1000))
      ..bindVertexData(fullScreen(), 3)
      ..draw()
      ..submit();
    expect(biased.depthPlane[0], closeTo(0.5 + 1000 * step, 1e-7));
    final clamped = Rig(withDepth: true);
    clamped.pass()
      ..setDepthBias(const DepthBias(constant: 1000, clamp: 1e-5))
      ..bindVertexData(fullScreen(), 3)
      ..draw()
      ..submit();
    expect(clamped.depthPlane[0], closeTo(0.5 + 1e-5, 1e-7));
  });

  test('a depth clamp keeps a fragment past the far plane, at the far '
      'plane', () {
    // Mutation: the depth clip ignoring `_depthClamp`, which drops the
    // triangle in both passes.
    final rig = Rig(withDepth: true);
    rig.pass()
      ..bindVertexData(fullScreen(z: 1.5), 3)
      ..draw()
      ..submit();
    expect(rig.redAt(0), 0);
    rig.pass()
      ..setDepthClamp(enabled: true)
      ..bindVertexData(fullScreen(z: 1.5), 3)
      ..draw()
      ..submit();
    expect(rig.redAt(0), 1);
    expect(rig.depthPlane[0], 1);
  });

  test('a colour write mask leaves the other channels alone', () {
    // Mutation: `_restore` never called, so all four channels are written.
    final rig = Rig();
    rig.pass()
      ..setColorWriteMask(ColorWriteMask.red)
      ..bindVertexData(fullScreen(), 3)
      ..draw()
      ..submit();
    expect(rig.pixels.sublist(0, 4), <double>[1, 0, 0, 0]);
  });

  test('min and max ignore both factors', () {
    // Mutation: `_combine` handing min and max the factored terms, which
    // under the default factors scales the destination by one minus alpha.
    for (final (op, red, green) in <(BlendOperation, double, double)>[
      (BlendOperation.max, 0.5, 0.9),
      (BlendOperation.min, 0.2, 0.5),
    ]) {
      final rig = Rig(color: Vector4(0.2, 0.9, 0, 1));
      rig.pass(clear: Vector4(0.5, 0.5, 0.5, 0.5))
        ..setBlend(BlendState(colorOperation: op, alphaOperation: op))
        ..bindVertexData(fullScreen(), 3)
        ..draw()
        ..submit();
      expect(rig.pixels[0], closeTo(red, 1e-6), reason: op.name);
      expect(rig.pixels[1], closeTo(green, 1e-6), reason: op.name);
    }
  });

  test('a dual-source factor reads the fragment\'s second output', () {
    // Mutation: `_factor` answering nought for `source1Color`, or the
    // encoder not passing `FragmentContext.source1` to the blend.
    final rig = Rig(
      color: Vector4(0.1, 0.1, 0.1, 1),
      second: Vector4(0.25, 0.25, 0.25, 0.5),
    );
    rig.pass(clear: Vector4(1, 1, 1, 1))
      ..setBlend(
        const BlendState(destinationColorFactor: BlendFactor.source1Color),
      )
      ..bindVertexData(fullScreen(), 3)
      ..draw()
      ..submit();
    expect(rig.pixels[0], closeTo(0.35, 1e-6));
  });

  test(
    'a render stage writes the storage it declares, and only that',
    () async {
      // Mutation: `bindStorageBuffer` answering true for a name the stage
      // does not declare, or the draw not handing `ShaderBindings.storage`.
      final rig = Rig(
        stages: <String, CpuStage>{
          'Count': const CpuStage.fragment(_CountFragments()),
        },
      );
      final counts = rig.device.createBuffer(
        BufferDescriptor(
          lengthInBytes: 4,
          usage: BufferUsage.storage | BufferUsage.hostReadable,
        ),
      );
      final stage = rig.device.shaders['Count']!;
      final pass = rig.pass(fragment: 'Count');
      expect(pass.bindStorageBuffer(stage, 'Elsewhere', counts), isFalse);
      expect(pass.bindStorageBuffer(stage, 'Counts', counts), isTrue);
      pass
        ..bindVertexData(fullScreen(), 3)
        ..draw()
        ..submit();
      final read = await rig.device.readBuffer(counts);
      expect(read.getUint32(0, Endian.little), 4);
    },
  );

  test('pipeline statistics count one triangle\'s work', () async {
    // Mutation: a counter left out — the fragment one in the triangle
    // loop, or the clipper's out count on the unclipped path.
    final rig = Rig();
    final stats = rig.device.createQuerySet(QueryType.pipelineStatistics, 1);
    rig.pass()
      ..beginPipelineStatisticsQuery(stats, 0)
      ..bindVertexData(fullScreen(), 3)
      ..draw()
      ..endPipelineStatisticsQuery()
      ..submit();
    expect(await rig.device.readQueryResults(stats), <int>[3, 1, 1, 4, 0]);
  });

  test('a pass writes its timestamps in order', () async {
    // Mutation: the end timestamp never written, which reads nought.
    final rig = Rig();
    final times = rig.device.createQuerySet(QueryType.timestamp, 2);
    rig
        .pass(
          timestamps: PassTimestampWrites(
            querySet: times,
            beginningOfPassIndex: 0,
            endOfPassIndex: 1,
          ),
        )
        .submit();
    final results = await rig.device.readQueryResults(times);
    expect(results[1], greaterThan(0));
    expect(results[1], greaterThanOrEqualTo(results[0]));
  });

  test('a bundle replays its draws and leaks no state either way', () {
    // Mutation: `executeBundles` not putting the pass's own state back, so
    // the bundle's additive blend doubles the draw after it.
    final rig = Rig();
    final pipeline = rig.device.createPipeline(
      rig.device.shaders['Position']!,
      rig.device.shaders['Solid']!,
    );
    final recorder = rig.device.createRenderBundleEncoder(
      const RenderBundleDescriptor(
        colorFormats: <TextureFormat>[TextureFormat.r32g32b32a32Float],
      ),
    );
    expect(
      () => recorder.setViewport(const ScreenRect(width: 1, height: 1)),
      throwsStateError,
    );
    recorder
      ..bindPipeline(pipeline)
      ..setBlend(BlendState.additive)
      ..bindVertexData(fullScreen(), 3)
      ..draw();
    final bundle = recorder.finish();
    rig.pass()
      ..executeBundles(<RenderBundle>[bundle])
      ..bindPipeline(pipeline)
      ..bindVertexData(fullScreen(), 3)
      ..draw()
      ..submit();
    expect(rig.redAt(0), 1);

    final wrong = rig.device
        .createRenderBundleEncoder(
          const RenderBundleDescriptor(
            colorFormats: <TextureFormat>[TextureFormat.r8g8b8a8UNormInt],
          ),
        )
        .finish();
    final pass = rig.pass();
    expect(
      () => pass.executeBundles(<RenderBundle>[wrong]),
      throwsArgumentError,
    );
    pass.submit();
  });
}
