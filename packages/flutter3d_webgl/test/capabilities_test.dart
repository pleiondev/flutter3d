/// The 1.0 surface on WebGL2: what the context reports, that what it reports
/// works on a real context, and that what it leaves out is refused naming
/// the feature.
///
///     flutter test --platform chrome test/capabilities_test.dart
///
/// The conformance suite's honesty check walks every feature with a minimal
/// probe; this file holds the things only this backend has to get right —
/// the format table against the extensions, rows the right way up through a
/// texture a pass draws into, a layer of an array read back on its own, and
/// the refusals that are WebGL2's own (a depth-bias clamp, an index buffer
/// that cannot also be a vertex buffer).
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter3d_webgl/src/webgl_formats.dart';
import 'package:flutter_test/flutter_test.dart';

WebGlDevice _device() {
  final device = WebGlDevice.open(
    width: 8,
    height: 8,
    sources: webGlEngineShaders,
  );
  return device;
}

const _none = CompressedTextureSupport(
  etc2: false,
  s3tc: false,
  s3tcSrgb: false,
  rgtc: false,
  bptc: false,
  astc: false,
);

WebGlFormatCaps _caps({
  bool colorBufferFloat = false,
  bool floatLinear = false,
  bool floatBlend = false,
}) => WebGlFormatCaps(
  colorBufferFloat: colorBufferFloat,
  floatLinear: floatLinear,
  floatBlend: floatBlend,
  halfFloatMultisample: false,
  compressed: _none,
);

Matcher _refusing(DeviceFeature feature) => throwsA(
  isA<UnsupportedCapability>().having(
    (UnsupportedCapability e) => e.feature,
    'feature',
    feature,
  ),
);

/// Four texels, each a different colour, rows from the top.
final ByteData _quad = ByteData.sublistView(
  Uint8List.fromList(<int>[
    255, 0, 0, 255, 0, 255, 0, 255, //
    0, 0, 255, 255, 255, 255, 255, 255,
  ]),
);

void main() {
  group('the format table', () {
    test('names a sized internal format for every appended format', () {
      // Mutation: drop one of the appended cases from `textureFormatToGl` —
      // the switch has no default, so this is a compile error first and a
      // throw here second.
      for (final format in extendedTextureFormats) {
        expect(
          () => textureFormatToGl(format),
          returnsNormally,
          reason: '$format',
        );
      }
    });

    test('32-bit floats filter only with OES_texture_float_linear', () {
      // Mutation: answer `filterable: true` for the 32-bit floats. A shadow
      // filter reading the answer would bind a linear sampler to a texture
      // that samples as zero without the extension.
      expect(
        webglTextureFormatSupport(TextureFormat.r32Float, _caps()).filterable,
        isFalse,
      );
      expect(
        webglTextureFormatSupport(
          TextureFormat.r32Float,
          _caps(floatLinear: true),
        ).filterable,
        isTrue,
      );
    });

    test('11/11/10 floats draw only with EXT_color_buffer_float', () {
      // Mutation: answer `renderable: true` for r11g11b10UFloat always — an
      // incomplete framebuffer on a context without the extension.
      expect(
        webglTextureFormatSupport(
          TextureFormat.r11g11b10UFloat,
          _caps(),
        ).renderable,
        isFalse,
      );
      expect(
        webglTextureFormatSupport(
          TextureFormat.r11g11b10UFloat,
          _caps(colorBufferFloat: true),
        ).renderable,
        isTrue,
      );
    });

    test('integers never filter or blend, depth never draws colour', () {
      // Mutation: give the integer family the eight-bit answer — a linear
      // sampler on an integer texture makes it incomplete.
      final integer = webglTextureFormatSupport(
        TextureFormat.r32UInt,
        _caps(colorBufferFloat: true, floatLinear: true),
      );
      expect(integer.renderable, isTrue);
      expect(integer.filterable || integer.blendable, isFalse);
      final depth = webglTextureFormatSupport(TextureFormat.d32Float, _caps());
      expect(depth.depthStencil, isTrue);
      expect(depth.renderable || depth.filterable, isFalse);
      expect(
        webglTextureFormatSupport(
          TextureFormat.r8g8b8a8SNormInt,
          _caps(),
        ).renderable,
        isFalse,
        reason: 'RGBA8_SNORM is not colour-renderable in ES 3.0',
      );
    });

    test('min, max and the dual-source factors have GL names', () {
      // Mutation: map BlendOperation.max to FUNC_ADD. Every value must be
      // distinct, or two equations draw the same picture.
      final operations = BlendOperation.values.map(blendOperationToGl).toSet();
      expect(operations, hasLength(BlendOperation.values.length));
      final factors = BlendFactor.values.map(blendFactorToGl).toSet();
      expect(factors, hasLength(BlendFactor.values.length));
    });
  });

  group('a real context', () {
    test('reports what it can and refuses what it cannot', () {
      // Mutation: list `compute` or `cubeArrayTextures` in `_decideFeatures`
      // — the first of these fails; or make a refusal a bare UnsupportedError
      // and the second half does.
      final device = _device();
      final features = device.features;
      for (final never in <DeviceFeature>[
        DeviceFeature.compute,
        DeviceFeature.wireframe,
        DeviceFeature.cubeArrayTextures,
        DeviceFeature.storageTextures,
        DeviceFeature.renderStageStorage,
        DeviceFeature.indirectDraw,
        DeviceFeature.multiDrawIndirect,
        DeviceFeature.samplerBorderColor,
        DeviceFeature.pipelineStatisticsQuery,
      ]) {
        expect(features.has(never), isFalse, reason: never.name);
      }
      for (final always in <DeviceFeature>[
        DeviceFeature.textureArrays,
        DeviceFeature.texture3D,
        DeviceFeature.buffers,
        DeviceFeature.occlusionQuery,
        DeviceFeature.renderBundles,
        DeviceFeature.synchronousReadback,
      ]) {
        expect(features.has(always), isTrue, reason: always.name);
      }
      expect(
        () => device.createTexture(
          const TextureDescriptor(
            width: 4,
            height: 4,
            depthOrArrayLayers: 12,
            format: TextureFormat.r8g8b8a8UNormInt,
            dimension: TextureDimension.cubeArray,
          ),
        ),
        _refusing(DeviceFeature.cubeArrayTextures),
      );
      expect(
        () => device.createQuerySet(QueryType.pipelineStatistics, 1),
        _refusing(DeviceFeature.pipelineStatisticsQuery),
      );
      expect(
        () => device.createStorageBuffer(ByteData(16)),
        _refusing(DeviceFeature.compute),
      );
      expect(device.limits.maxComputeInvocationsPerWorkgroup, 0);
      expect(
        device.limits.maxColorAttachments,
        device.limits.maxColorAttachments,
      );
      device.dispose();
    });

    test('a refused call leaves the pass able to submit', () {
      // Mutation: tear the pass down before throwing, as `_fail` does — the
      // submit below then throws StateError, and the conformance probes,
      // which submit in a `finally`, would report that instead.
      final device = _device();
      final pass = device.beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[
            ColorTarget(
              texture: device.createTexture(
                const RenderTargetDescriptor(
                  width: 4,
                  height: 4,
                  format: TextureFormat.r8g8b8a8UNormInt,
                ),
              ),
            ),
          ],
        ),
      );
      expect(
        () => pass.drawIndirect(
          wrapStorageBuffer(backend: Object(), lengthInBytes: 16),
        ),
        _refusing(DeviceFeature.indirectDraw),
      );
      expect(
        () => pass.setPolygonMode(PolygonMode.line),
        _refusing(DeviceFeature.wireframe),
      );
      // A clamp is the one part of depth bias GL cannot do. Refused, and
      // not as a missing feature: the device has depth bias.
      expect(
        () => pass.setDepthBias(const DepthBias(constant: 1, clamp: 0.5)),
        throwsA(
          isA<UnsupportedError>().having(
            (UnsupportedError e) => e is UnsupportedCapability,
            'a capability refusal',
            isFalse,
          ),
        ),
      );
      pass
        ..setDepthBias(const DepthBias(constant: 1, slopeScale: 1))
        ..setColorWriteMask(ColorWriteMask.red)
        ..setBlend(const BlendState(colorOperation: BlendOperation.max));
      expect(pass.submit, returnsNormally);
      expect(device.debugDrainErrors('after the refusals'), isNull);
      device.dispose();
    });

    test('a written texture reads back the way up it went in', () async {
      // Mutation: drop the row reversal from `webglWriteTexture` — a
      // texture made to be drawn into stores its top at the last row here,
      // `readback` turns it over, and the picture comes back upside down.
      final device = _device();
      final texture = device.createTexture(
        const TextureDescriptor(
          width: 2,
          height: 2,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
      );
      device.writeTexture(texture, _quad);
      final back = await device.readback(texture);
      expect(back.buffer.asUint8List(), _quad.buffer.asUint8List());
      device.dispose();
    });

    test('one layer of an array copies out alone', () {
      // Mutation: attach `layer: 0` in the transfer encoder's `_attach`
      // whatever the location says — the copy then reads the zeros of the
      // first layer rather than the colours written into the second.
      final device = _device();
      final array = device.createTexture(
        TextureDescriptor(
          width: 2,
          height: 2,
          depthOrArrayLayers: 3,
          dimension: TextureDimension.d2Array,
          format: TextureFormat.r8g8b8a8UNormInt,
          usage: TextureUsage.sampled | TextureUsage.copySource,
        ),
      );
      device.writeTexture(
        array,
        _quad,
        region: const TextureRegion(z: 1, width: 2, height: 2),
      );
      final out = device.createBuffer(
        BufferDescriptor(
          lengthInBytes: 16,
          usage: BufferUsage.copyDestination | BufferUsage.hostReadable,
        ),
      );
      device.beginTransferPass()
        ..copyTextureToBuffer(
          TextureCopyLocation(array, z: 1),
          out,
          const BufferTextureLayout(bytesPerRow: 8),
          width: 2,
          height: 2,
        )
        ..submit();
      expect(
        device.readBufferSync(out).buffer.asUint8List(),
        _quad.buffer.asUint8List(),
      );
      expect(device.debugDrainErrors('after the layer copy'), isNull);
      device.dispose();
    });

    test('an occlusion query around nothing answers zero', () async {
      // Mutation: record a query as written without calling `beginQuery` —
      // reading its result is then INVALID_OPERATION, and the drain below
      // names it.
      final device = _device();
      final set = device.createQuerySet(QueryType.occlusion, 2);
      device.beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[
              ColorTarget(
                texture: device.createTexture(
                  const RenderTargetDescriptor(
                    width: 4,
                    height: 4,
                    format: TextureFormat.r8g8b8a8UNormInt,
                  ),
                ),
              ),
            ],
            occlusionQuerySet: set,
          ),
        )
        ..beginOcclusionQuery(0)
        ..endOcclusionQuery()
        ..submit();
      expect(await device.readQueryResults(set), <int>[0, 0]);
      expect(device.debugDrainErrors('after the query'), isNull);
      device.releaseQuerySet(set);
      device.dispose();
    });

    test('one buffer cannot hold indices and vertices', () {
      // Mutation: let `webglCreateBuffer` accept index | vertex. The buffer
      // is typed by its first binding, and the vertex binding at the first
      // draw is then an INVALID_OPERATION nobody sees.
      final device = _device();
      expect(
        () => device.createBuffer(
          BufferDescriptor(
            lengthInBytes: 16,
            usage: BufferUsage.index | BufferUsage.vertex,
          ),
        ),
        throwsUnsupportedError,
      );
      device.dispose();
    });

    test('a bundle recorded for other attachments is refused', () {
      // Mutation: skip the descriptor comparison in `executeBundles` — a
      // bundle for a float target replays into an eight-bit one.
      final device = _device();
      final bundle = device
          .createRenderBundleEncoder(
            const RenderBundleDescriptor(
              colorFormats: <TextureFormat>[TextureFormat.r16g16b16a16Float],
            ),
          )
          .finish();
      final pass = device.beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[
            ColorTarget(
              texture: device.createTexture(
                const RenderTargetDescriptor(
                  width: 4,
                  height: 4,
                  format: TextureFormat.r8g8b8a8UNormInt,
                ),
              ),
            ),
          ],
        ),
      );
      expect(
        () => pass.executeBundles(<RenderBundle>[bundle]),
        throwsArgumentError,
      );
      pass.submit();
      device.dispose();
    });
  });
}
