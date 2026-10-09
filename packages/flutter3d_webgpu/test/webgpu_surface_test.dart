/// The 1.0 surface on a real device: buffers, copies, texture writes, queries,
/// bundles, write masks — and the refusals `features` promises.
///
///     flutter test --platform chrome test/webgpu_surface_test.dart
///
/// Each test opens its own device over `quad_stages.dart`, which is the
/// smallest stage table that draws a coloured quad, so a byte that comes back
/// wrong names one mechanism rather than a shading pipeline.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import 'quad_stages.dart';

Future<WebGpuDevice?> _open() async {
  try {
    return await WebGpuDevice.open(width: 8, height: 8, stages: quadStages);
  } on DeviceUnavailableException {
    markTestSkipped('no WebGPU in this browser');
    return null;
  }
}

ByteData _bytes(List<int> values) =>
    ByteData.sublistView(Uint8List.fromList(values));

List<int> _list(ByteData data) =>
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

/// A green quad over the whole of [encoder]'s target.
void _drawQuad(WebGpuDevice device, PassEncoder encoder) {
  final vertex = device.shaders['QuadVertex']!;
  final fragment = device.shaders['QuadFragment']!;
  final palette = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: _bytes(<int>[0, 255, 0, 255]),
  );
  encoder
    ..bindPipeline(device.createPipeline(vertex, fragment))
    ..bindVertexBuffer(
      device.uploadGeometry(quadVertices(), GeometryUsage.vertices),
      4,
    )
    ..bindIndexBuffer(
      device.uploadGeometry(quadIndices(), GeometryUsage.indices),
      IndexType.int16,
      6,
    )
    ..bindUniformBlock(vertex, 'Placement', <String, Float32List>{
      'value': Float32List.fromList(<double>[0, 0, 1, 1]),
    })
    ..bindUniformBlock(fragment, 'Tint', <String, Float32List>{
      'value': Float32List.fromList(<double>[1, 1, 1, 1]),
    })
    ..bindTexture(fragment, 'palette', palette)
    ..draw();
}

TextureHandle _target(WebGpuDevice device) => device.createTexture(
  const RenderTargetDescriptor(
    width: 8,
    height: 8,
    format: TextureFormat.r8g8b8a8UNormInt,
  ),
);

Future<List<int>> _center(WebGpuDevice device, TextureHandle target) async =>
    _list(
      await device.readback(
        target,
        region: const ScreenRect(x: 4, y: 4, width: 1, height: 1),
      ),
    );

void main() {
  test('a buffer made with contents reads back, and takes a write', () async {
    // Mutation: skip the mapped write at creation. The first read is zeros.
    final device = await _open();
    if (device == null) return;
    final buffer = device.createBuffer(
      BufferDescriptor(
        lengthInBytes: 8,
        usage: BufferUsage.hostReadable | BufferUsage.copyDestination,
      ),
      contents: _bytes(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
    );
    expect(_list(await device.readBuffer(buffer)), <int>[
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
    ]);
    device.writeBuffer(buffer, 4, _bytes(<int>[9, 9, 9, 9]));
    expect(_list(await device.readBuffer(buffer)), <int>[
      1,
      2,
      3,
      4,
      9,
      9,
      9,
      9,
    ]);
    final mapped = await device.mapBuffer(
      buffer,
      MapMode.read,
      offsetInBytes: 4,
      sizeInBytes: 4,
    );
    expect(_list(mapped.bytes), <int>[9, 9, 9, 9]);
    mapped.unmap();
    expect(await device.debugDrainErrors(), isNull);
    device.dispose();
  });

  test('a transfer pass clears and copies a buffer', () async {
    // Mutation: drop the `clearBuffer` call from the encoder. The first four
    // bytes come back as the source's rather than zeros.
    final device = await _open();
    if (device == null) return;
    final usage =
        BufferUsage.storage |
        BufferUsage.copySource |
        BufferUsage.copyDestination |
        BufferUsage.hostReadable;
    final source = device.createBuffer(
      BufferDescriptor(lengthInBytes: 8, usage: usage),
      contents: _bytes(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
    );
    final destination = device.createBuffer(
      BufferDescriptor(lengthInBytes: 8, usage: usage),
      contents: _bytes(<int>[7, 7, 7, 7, 7, 7, 7, 7]),
    );
    device.beginTransferPass()
      ..copyBufferToBuffer(source, 4, destination, 4, 4)
      ..clearBuffer(destination, sizeInBytes: 4)
      ..submit();
    expect(_list(await device.readBuffer(destination)), <int>[
      0,
      0,
      0,
      0,
      5,
      6,
      7,
      8,
    ]);
    expect(await device.debugDrainErrors(), isNull);
    device.dispose();
  });

  test('a layer of an array texture is written and copied out', () async {
    // Mutation: ignore `region.z` in `webgpuWriteTexture`. The texel lands in
    // layer zero and layer two copies out as zeros.
    final device = await _open();
    if (device == null) return;
    final array = device.createTexture(
      const TextureDescriptor(
        width: 4,
        height: 1,
        depthOrArrayLayers: 3,
        format: TextureFormat.r8g8b8a8UNormInt,
        dimension: TextureDimension.d2Array,
      ),
    );
    device.writeTexture(
      array,
      _bytes(<int>[for (var i = 0; i < 16; i++) i]),
      region: const TextureRegion(z: 2, width: 4, height: 1),
    );
    final out = device.createBuffer(
      BufferDescriptor(
        lengthInBytes: 256,
        usage: BufferUsage.hostReadable | BufferUsage.copyDestination,
      ),
    );
    device.beginTransferPass()
      ..copyTextureToBuffer(
        TextureCopyLocation(array, z: 2),
        out,
        const BufferTextureLayout(bytesPerRow: 256),
        width: 4,
        height: 1,
      )
      ..submit();
    expect(_list(await device.readBuffer(out)).take(16), <int>[
      for (var i = 0; i < 16; i++) i,
    ]);
    expect(await device.debugDrainErrors(), isNull);
    device.dispose();
  });

  test(
    'a copy with rows not 256 apart is refused before it is encoded',
    () async {
      // Mutation: drop `gpuCheckCopyBytesPerRow`. The copy is encoded, the
      // browser refuses the command buffer, and nothing names the call.
      final device = await _open();
      if (device == null) return;
      final texture = _target(device);
      final buffer = device.createBuffer(
        const BufferDescriptor(
          lengthInBytes: 256,
          usage: BufferUsage.copySource,
        ),
      );
      expect(
        () => device.beginTransferPass().copyBufferToTexture(
          buffer,
          const BufferTextureLayout(bytesPerRow: 16),
          TextureCopyLocation(texture),
          width: 4,
          height: 2,
        ),
        throwsArgumentError,
      );
      device.dispose();
    },
  );

  test(
    'an occlusion query counts what a draw passed, and zero for none',
    () async {
      // Mutation: never set `occlusionQuerySet` on the pass descriptor. The
      // browser refuses `beginOcclusionQuery` and both results read zero.
      final device = await _open();
      if (device == null) return;
      final queries = device.createQuerySet(QueryType.occlusion, 2);
      final target = _target(device);
      final pass = device.beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[ColorTarget(texture: target)],
          occlusionQuerySet: queries,
        ),
      )..beginOcclusionQuery(0);
      _drawQuad(device, pass);
      pass
        ..endOcclusionQuery()
        ..beginOcclusionQuery(1)
        ..endOcclusionQuery()
        ..submit();
      final results = await device.readQueryResults(queries);
      expect(results, hasLength(2));
      expect(results[0], greaterThan(0));
      expect(results[1], 0);
      expect(await device.debugDrainErrors(), isNull);
      device.dispose();
    },
  );

  test('a write mask keeps the channels it leaves out', () async {
    // Mutation: build every target with `GpuColorWrite.all`. The quad's green
    // reaches the target and the centre reads (0, 255, 0).
    final device = await _open();
    if (device == null) return;
    final target = _target(device);
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(texture: target, clearValue: Vector4(1, 0, 0, 1)),
        ],
      ),
    )..setColorWriteMask(ColorWriteMask.red);
    _drawQuad(device, pass);
    pass.submit();
    // Red is written (the quad's red is zero); green is not.
    expect(await _center(device, target), <int>[0, 0, 0, 255]);
    expect(await device.debugDrainErrors(), isNull);
    device.dispose();
  });

  test('a bundle replays its draw into a pass', () async {
    // Mutation: make `executeBundles` a no-op. The centre keeps the clear.
    final device = await _open();
    if (device == null) return;
    final target = _target(device);
    final recorder = device.createRenderBundleEncoder(
      const RenderBundleDescriptor(
        colorFormats: <TextureFormat>[TextureFormat.r8g8b8a8UNormInt],
      ),
    );
    _drawQuad(device, recorder);
    final bundle = recorder.finish(label: 'quad');
    expect(() => recorder.setViewport(ScreenRect.of(target)), throwsStateError);
    device.beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[
            ColorTarget(texture: target, clearValue: Vector4(1, 0, 0, 1)),
          ],
        ),
      )
      ..executeBundles(<RenderBundle>[bundle])
      ..submit();
    expect(await _center(device, target), <int>[0, 255, 0, 255]);
    expect(await device.debugDrainErrors(), isNull);
    device.dispose();
  });

  test('what the device does not list is refused by name', () async {
    // The other half of the honesty rule: an unlisted feature's call throws
    // `UnsupportedCapability` naming that feature, before anything looks at
    // the handle it was given.
    //
    // Mutation: look the slot up before checking the sampler. The border
    // sampler on an undeclared slot answers false instead of refusing.
    final device = await _open();
    if (device == null) return;
    final target = _target(device);
    final foreign = wrapStorageBuffer(backend: Object(), lengthInBytes: 16);
    Matcher refuses(DeviceFeature feature) => throwsA(
      isA<UnsupportedCapability>().having(
        (UnsupportedCapability e) => e.feature,
        'feature',
        feature,
      ),
    );
    final pass = device.beginRenderPass(
      RenderPassDescriptor(colors: <ColorTarget>[ColorTarget(texture: target)]),
    );
    final fragment = device.shaders['QuadFragment']!;
    expect(
      () => pass.bindTexture(
        fragment,
        'flutter3dNoSuchSlot',
        target,
        sampler: const SamplerDescriptor(
          borderColor: SamplerBorderColor.opaqueWhite,
        ),
      ),
      refuses(DeviceFeature.samplerBorderColor),
    );
    expect(
      () => pass.setBlendColor(Vector4.zero()),
      refuses(DeviceFeature.blendConstant),
    );
    expect(
      () => pass.setPolygonMode(PolygonMode.line),
      refuses(DeviceFeature.wireframe),
    );
    expect(
      () => pass.bindStorageBuffer(fragment, 'anything', foreign),
      refuses(DeviceFeature.renderStageStorage),
    );
    expect(
      () => pass.beginPipelineStatisticsQuery(
        wrapQuerySet(
          backend: Object(),
          type: QueryType.pipelineStatistics,
          count: 1,
        ),
        0,
      ),
      refuses(DeviceFeature.pipelineStatisticsQuery),
    );
    pass.submit();
    // Not a `SynchronousBufferReadback` at all: WebGPU has no such call.
    expect(device, isNot(isA<SynchronousBufferReadback>()));
    expect(device.features.has(DeviceFeature.synchronousReadback), isFalse);
    expect(
      () => device.createQuerySet(QueryType.pipelineStatistics, 1),
      refuses(DeviceFeature.pipelineStatisticsQuery),
    );
    device.dispose();
  });
}
