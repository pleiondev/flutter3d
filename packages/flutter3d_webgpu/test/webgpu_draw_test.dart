/// The device and the encoder, in front of a real WebGPU implementation.
///
///     flutter test --platform chrome test/webgpu_draw_test.dart
///
/// **Every check here is a colour, because every mistake this backend can make
/// is a picture rather than an exception.** A pipeline handed back for the
/// wrong state draws. A bind group assembled from stale bindings draws. A row
/// order carried over from the backend that needed one draws, and reads back
/// correctly, and shows upside down. So the questions are asked as draws with a
/// control that comes back the *other* colour, rather than as counters that a
/// backend which had stopped working would go on reporting.
///
/// The stage pair is `quad_stages.dart`'s rather than the engine's, and that
/// file says why.
///
/// **A browser with no WebGPU reports rather than fails.** A runner may have
/// none, and a red line about the machine is not a finding about the code.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import 'quad_stages.dart';

const List<int> _red = <int>[255, 0, 0, 255];
const List<int> _green = <int>[0, 255, 0, 255];
const List<int> _black = <int>[0, 0, 0, 255];

/// Everything a draw needs, built once per test.
final class _Scene {
  _Scene(this.device)
    : vertexStage = device.shaders['QuadVertex']!,
      fragmentStage = device.shaders['QuadFragment']!,
      pairStage = device.shaders['QuadFragmentPair']!,
      vertices = device.uploadGeometry(quadVertices(), GeometryUsage.vertices),
      indices = device.uploadGeometry(quadIndices(), GeometryUsage.indices) {
    // Two texels: red on the left, green on the right. The colour that comes
    // back names which end of the texture a coordinate reached.
    palette = device.createTextureFromPixels(
      width: 2,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(
        Uint8List.fromList(<int>[..._red, ..._green]),
      ),
    )!;
    pipeline = device.createPipeline(vertexStage, fragmentStage);
    pairPipeline = device.createPipeline(vertexStage, pairStage);
  }

  final WebGpuDevice device;
  final ShaderHandle vertexStage;
  final ShaderHandle fragmentStage;
  final ShaderHandle pairStage;
  final GeometryBuffer vertices;
  final GeometryBuffer indices;
  late final TextureHandle palette;
  late final PipelineHandle pipeline;
  late final PipelineHandle pairPipeline;

  TextureHandle target({int size = 4, int sampleCount = 1}) =>
      device.createTexture(
        RenderTargetSpec(
          width: size,
          height: size,
          format: TextureFormat.r8g8b8a8UNormInt,
          sampleCount: sampleCount,
        ),
      );

  /// Binds everything one textured quad needs, at [where], tinted [tint].
  void bindQuad(
    PassEncoder pass, {
    required Float32List where,
    Float32List? tint,
    SamplerOptions? sampler,
    GeometryBuffer? geometry,
  }) {
    pass
      ..bindVertexBuffer(geometry ?? vertices, 4)
      ..bindIndexBuffer(indices, IndexType.int16, 6);
    expect(
      pass.bindUniformBlock(vertexStage, 'Placement', <String, Float32List>{
        'value': where,
      }),
      isTrue,
    );
    expect(
      pass.bindUniformBlock(fragmentStage, 'Tint', <String, Float32List>{
        'value': tint ?? tinted(1, 1, 1, 1),
      }),
      isTrue,
    );
    pass.bindTexture(fragmentStage, 'palette', palette, sampler: sampler);
  }
}

Future<WebGpuDevice?> _open() =>
    WebGpuDevice.create(width: 64, height: 64, stages: quadStages);

/// The device and a scene over it, or null where this browser has no WebGPU.
Future<_Scene?> _scene() async {
  final device = await _open();
  if (device == null) {
    markTestSkipped('no WebGPU in this browser');
    return null;
  }
  device.beginFrame();
  return _Scene(device);
}

List<int> _texel(ByteData pixels, int width, int x, int y) {
  final at = (y * width + x) * 4;
  return <int>[
    pixels.getUint8(at),
    pixels.getUint8(at + 1),
    pixels.getUint8(at + 2),
    pixels.getUint8(at + 3),
  ];
}

ColorTarget _clearTo(TextureHandle texture) =>
    ColorTarget(texture: texture, clearValue: Vector4(0, 0, 0, 1));

void main() {
  test('a textured quad comes back with the palette it sampled', () async {
    final scene = await _scene();
    if (scene == null) return;
    final target = scene.target();

    final pass = scene.device.beginRenderPass(
      RenderPassDescriptor(colors: <ColorTarget>[_clearTo(target)]),
    )..bindPipeline(scene.pipeline);
    scene.bindQuad(
      pass,
      where: placedAt(),
      sampler: SamplerOptions.nearestClamp,
    );
    pass
      ..draw()
      ..submit();

    final pixels = await scene.device.readback(target);
    // **The browser's verdict is read before the colours, and the order is the
    // finding rather than a habit.** A descriptor this backend gets wrong —
    // a bind group layout that names the wrong stages, a vertex format that
    // does not match the buffer — is not refused by a throw. The object comes
    // back marked invalid, the pass that sets it draws nothing, and the
    // readback is black. Asked the other way round, every such mistake is
    // reported as a texel that should have been red, and the sentence the
    // browser wrote about what was actually wrong is drained afterwards and
    // never printed.
    expect(await scene.device.debugDrainErrors('the draw'), isNull);
    // A four-pixel row samples the two-texel palette at 0.125, 0.375, 0.625 and
    // 0.875, so the left half is the left texel and the right half the right.
    expect(_texel(pixels, 4, 0, 1), _red);
    expect(_texel(pixels, 4, 3, 1), _green);
    scene.device.dispose();
  });

  test('rows come back from the top, and nothing is turned over', () async {
    // **The check the WebGL2 backend needed a person looking at a sphere to
    // find.** That backend flips its readback because GL hands rows back from
    // the bottom; WebGPU's origin is the top left, so a flip carried across
    // "just in case" gives a frame that reads back correctly and presents
    // upside down.
    //
    // Mutation: reverse the row loop in `_copyBack`. The painted rows move to
    // the bottom and this fails on both expectations at once.
    final scene = await _scene();
    if (scene == null) return;
    final target = scene.target();

    final pass = scene.device.beginRenderPass(
      RenderPassDescriptor(colors: <ColorTarget>[_clearTo(target)]),
    )..bindPipeline(scene.pipeline);
    // Clip space with y up, so a quad from y=0 to y=+1 covers the top half of
    // the picture — and row zero of a readback is the top of the picture.
    scene.bindQuad(
      pass,
      where: placedAt(y: 0.5, height: 0.5),
      sampler: SamplerOptions.nearestClamp,
    );
    pass
      ..draw()
      ..submit();

    final pixels = await scene.device.readback(target);
    expect(_texel(pixels, 4, 0, 0), _red, reason: 'the top row was painted');
    expect(_texel(pixels, 4, 3, 1), _green);
    expect(
      _texel(pixels, 4, 0, 3),
      _black,
      reason: 'the bottom row was not, and a flip would have swapped the two',
    );
    scene.device.dispose();
  });

  test(
    'a readback of a region is that region, at the offset asked for',
    () async {
      final scene = await _scene();
      if (scene == null) return;
      final target = scene.target(size: 8);

      final pass = scene.device.beginRenderPass(
        RenderPassDescriptor(colors: <ColorTarget>[_clearTo(target)]),
      )..bindPipeline(scene.pipeline);
      scene.bindQuad(
        pass,
        where: placedAt(y: 0.5, height: 0.5),
        sampler: SamplerOptions.nearestClamp,
      );
      pass
        ..draw()
        ..submit();

      // Two texels of the bottom-left corner, which the quad never reached. The
      // row stride of a two-pixel region is eight bytes packed and 256 in the
      // copy, so this is also the repacking at its most lopsided.
      final corner = await scene.device.readback(
        target,
        region: const ScreenRect(x: 0, y: 6, width: 2, height: 2),
      );
      expect(corner.lengthInBytes, 2 * 2 * 4);
      expect(_texel(corner, 2, 0, 0), _black);
      expect(_texel(corner, 2, 1, 1), _black);

      final painted = await scene.device.readback(
        target,
        region: const ScreenRect(x: 0, y: 0, width: 2, height: 2),
      );
      expect(_texel(painted, 2, 0, 0), _red);
      scene.device.dispose();
    },
  );

  test(
    'two placements in one pass share a bind group and differ by offset',
    () async {
      // **What the dynamic offset bought.** Without it each draw's uniform block
      // is a different buffer range and so a different bind group, and a frame of
      // forty materials against one camera block builds forty copies of the
      // camera. With it the group is made once and only the offset moves.
      final scene = await _scene();
      if (scene == null) return;
      final target = scene.target();

      final pass = scene.device.beginRenderPass(
        RenderPassDescriptor(colors: <ColorTarget>[_clearTo(target)]),
      )..bindPipeline(scene.pipeline);
      scene.bindQuad(
        pass,
        where: placedAt(y: 0.5, height: 0.5),
        sampler: SamplerOptions.nearestClamp,
      );
      pass.draw();
      scene.bindQuad(
        pass,
        where: placedAt(y: -0.5, height: 0.5),
        tint: tinted(0, 1, 1, 1),
        sampler: SamplerOptions.nearestClamp,
      );
      pass
        ..draw()
        ..submit();

      final pixels = await scene.device.readback(target);
      expect(_texel(pixels, 4, 0, 0), _red, reason: 'the first placement');
      expect(_texel(pixels, 4, 0, 3), <int>[
        0,
        0,
        0,
        255,
      ], reason: 'the second placement, tinted to drop the palette\'s red');
      expect(_texel(pixels, 4, 3, 3), _green);
      expect(
        scene.device.debugBindGroupCount,
        1,
        reason:
            'two draws bound the same buffer, view and sampler at different '
            'offsets, which is one bind group and two dynamic offsets',
      );
      expect(await scene.device.debugDrainErrors('two placements'), isNull);
      scene.device.dispose();
    },
  );

  test('a sampler is one object per description, not one per bind', () async {
    // In GL the filter and the wrap modes are properties of the texture, so the
    // WebGL2 backend sets four `texParameteri` on every bind. WebGPU has real
    // sampler objects compared by value, and `SamplerOptions` already is one.
    final scene = await _scene();
    if (scene == null) return;
    final target = scene.target();

    final pass = scene.device.beginRenderPass(
      RenderPassDescriptor(colors: <ColorTarget>[_clearTo(target)]),
    )..bindPipeline(scene.pipeline);
    scene.bindQuad(
      pass,
      where: placedAt(),
      sampler: SamplerOptions.nearestClamp,
    );
    pass.draw();
    scene.bindQuad(
      pass,
      where: placedAt(),
      sampler: SamplerOptions.nearestClamp,
    );
    pass.draw();
    expect(scene.device.debugSamplerCount, 1);

    scene.bindQuad(
      pass,
      where: placedAt(),
      sampler: SamplerOptions.linearClamp,
    );
    pass
      ..draw()
      ..submit();
    expect(scene.device.debugSamplerCount, 2);
    expect(await scene.device.debugDrainErrors('samplers'), isNull);
    scene.device.dispose();
  });

  test('two vertex layouts over one stage pair are two pipelines', () async {
    // **The field the spike's ten-field key did not have**, asked of the
    // browser rather than of the map. `GraphicsDevice.createPipeline` says a
    // cache that misses it hands the first pipeline back for the second, which
    // reads one layout's bytes through the other's stride — a picture, and no
    // error anywhere.
    //
    // Mutation: drop `vertexLayout` from the signature. One pipeline is built,
    // the padded buffer is read at the packed stride, and the second quad comes
    // back as noise rather than as the palette.
    final scene = await _scene();
    if (scene == null) return;
    final target = scene.target();
    final padded = scene.device.uploadGeometry(
      quadVertices(stride: 32),
      GeometryUsage.vertices,
    );
    final paddedPipeline = scene.device.createPipeline(
      scene.vertexStage,
      scene.fragmentStage,
      layout: const VertexLayoutSpec(<BufferLayout>[
        BufferLayout(
          strideInBytes: 32,
          attributes: <InputAttribute>[
            InputAttribute(name: 'position', format: VertexFormat.float32x2),
            InputAttribute(
              name: 'uv',
              format: VertexFormat.float32x2,
              offsetInBytes: 8,
            ),
          ],
        ),
      ]),
    );

    final pass = scene.device.beginRenderPass(
      RenderPassDescriptor(colors: <ColorTarget>[_clearTo(target)]),
    )..bindPipeline(scene.pipeline);
    scene.bindQuad(
      pass,
      where: placedAt(y: 0.5, height: 0.5),
      sampler: SamplerOptions.nearestClamp,
    );
    pass
      ..draw()
      ..bindPipeline(paddedPipeline);
    scene.bindQuad(
      pass,
      where: placedAt(y: -0.5, height: 0.5),
      sampler: SamplerOptions.nearestClamp,
      geometry: padded,
    );
    pass
      ..draw()
      ..submit();

    expect(scene.device.pipelines.length, 2);
    final pixels = await scene.device.readback(target);
    expect(_texel(pixels, 4, 0, 0), _red);
    expect(_texel(pixels, 4, 3, 3), _green);
    expect(await scene.device.debugDrainErrors('two layouts'), isNull);
    scene.device.dispose();
  });

  test('a blend equation reaches the attachment its index names', () async {
    // **The one thing this backend can do that the other three cannot.**
    // `PassEncoder.setBlend` calls the index a hint, because Impeller is the
    // only other backend that honours it and WebGL2 would need an optional
    // extension. Here every colour target carries its own equation in the
    // pipeline, so the two attachments genuinely blend differently.
    //
    // Mutation: ignore `attachment` and write index zero. Both attachments end
    // at the same value and the second expectation fails.
    final scene = await _scene();
    if (scene == null) return;
    final first = scene.target();
    final second = scene.target();

    final pass =
        scene.device.beginRenderPass(
            RenderPassDescriptor(
              colors: <ColorTarget>[_clearTo(first), _clearTo(second)],
            ),
          )
          ..bindPipeline(scene.pairPipeline)
          ..setBlend(null)
          ..setBlend(BlendState.additive, attachment: 1);

    for (var i = 0; i < 2; i++) {
      pass
        ..bindVertexBuffer(scene.vertices, 4)
        ..bindIndexBuffer(scene.indices, IndexType.int16, 6)
        ..bindUniformBlock(
          scene.vertexStage,
          'Placement',
          <String, Float32List>{'value': placedAt()},
        )
        ..bindUniformBlock(scene.pairStage, 'Tint', <String, Float32List>{
          'value': tinted(0.25, 0.25, 0.25, 1),
        })
        ..draw();
    }
    pass.submit();

    final unblended = await scene.device.readback(first);
    final blended = await scene.device.readback(second);
    expect(
      _texel(unblended, 4, 2, 2)[0],
      closeTo(64, 2),
      reason: 'blending off: the second draw replaced the first',
    );
    expect(
      _texel(blended, 4, 2, 2)[0],
      closeTo(128, 2),
      reason: 'additive on attachment one: the two draws summed',
    );
    expect(await scene.device.debugDrainErrors('two blends'), isNull);
    scene.device.dispose();
  });

  test('a multisampled pass resolves into the texture it names', () async {
    // **The half a translation drops.** `gpuStoreOp` maps
    // `StoreAction.multisampleResolve` to `"discard"`, which alone is a
    // multisampled attachment thrown away — the resolve is a separate field on
    // the attachment, and a backend that mapped the store action and stopped
    // there would leave whatever samples the resolve target reading what was in
    // it before.
    //
    // Mutation: use the plain colour-attachment constructor. The resolve target
    // comes back the zeros it was allocated with.
    final scene = await _scene();
    if (scene == null) return;
    final multisampled = scene.target(sampleCount: 4);
    final resolved = scene.target();

    final pass = scene.device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(
            texture: multisampled,
            resolveTexture: resolved,
            storeAction: StoreAction.multisampleResolve,
            clearValue: Vector4(0, 0, 0, 1),
          ),
        ],
      ),
    )..bindPipeline(scene.pipeline);
    scene.bindQuad(
      pass,
      where: placedAt(),
      sampler: SamplerOptions.nearestClamp,
    );
    pass
      ..draw()
      ..submit();

    final pixels = await scene.device.readback(resolved);
    expect(_texel(pixels, 4, 0, 1), _red);
    expect(_texel(pixels, 4, 3, 1), _green);
    expect(await scene.device.debugDrainErrors('the resolve'), isNull);
    scene.device.dispose();
  });

  test('a cube is sampled by direction, in the order the contract names', () async {
    // **The one cube-shaped question this iteration answers yes to.** Rendering
    // *into* a cube and into a mip level below the base both refuse, so a
    // reflection probe is skipped; a cube *texture* cannot refuse, because the
    // sky pass is a cube lookup and nothing else.
    //
    // The face order — +X, −X, +Y, −Y, +Z, −Z — has no natural check: a table
    // with two entries transposed is a sky that is complete, seamless and
    // wrong, and it reads as an asset somebody authored badly. Here the left
    // half of the quad looks down +X and the right half down −X, so a transpose
    // swaps the two colours.
    final scene = await _scene();
    if (scene == null) return;
    final cubeStage = scene.device.shaders['QuadFragmentCube']!;
    final cube = scene.device.createCubeTextureFromPixels(
      size: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      faces: <ByteData>[
        for (final colour in const <List<int>>[
          _red,
          _green,
          <int>[0, 0, 255, 255],
          <int>[255, 255, 0, 255],
          <int>[255, 0, 255, 255],
          <int>[0, 255, 255, 255],
        ])
          ByteData.sublistView(Uint8List.fromList(colour)),
      ],
    )!;
    final target = scene.target();

    final pass = scene.device.beginRenderPass(
      RenderPassDescriptor(colors: <ColorTarget>[_clearTo(target)]),
    )..bindPipeline(scene.device.createPipeline(scene.vertexStage, cubeStage));
    pass
      ..bindVertexBuffer(scene.vertices, 4)
      ..bindIndexBuffer(scene.indices, IndexType.int16, 6)
      ..bindUniformBlock(scene.vertexStage, 'Placement', <String, Float32List>{
        'value': placedAt(),
      })
      ..bindUniformBlock(cubeStage, 'Tint', <String, Float32List>{
        'value': tinted(1, 1, 1, 1),
      })
      ..bindTexture(cubeStage, 'sky', cube, sampler: SamplerOptions.linearClamp)
      ..draw()
      ..submit();

    final pixels = await scene.device.readback(target);
    expect(_texel(pixels, 4, 0, 1), _red, reason: 'the +X face is the first');
    expect(_texel(pixels, 4, 3, 1), _green, reason: 'and −X the second');
    expect(await scene.device.debugDrainErrors('the cube'), isNull);
    scene.device.dispose();
  });

  test('the depth test reaches the pipeline it is baked into', () async {
    final scene = await _scene();
    if (scene == null) return;
    final target = scene.target();
    final depth = scene.device.createTexture(
      const RenderTargetSpec(
        width: 4,
        height: 4,
        format: TextureFormat.d24UnormS8Uint,
      ),
    );

    final pass =
        scene.device.beginRenderPass(
            RenderPassDescriptor(
              colors: <ColorTarget>[_clearTo(target)],
              depth: DepthTarget(texture: depth),
            ),
          )
          ..bindPipeline(scene.pipeline)
          ..setDepthCompare(CompareFunction.less)
          ..setDepthWrite(true);
    scene.bindQuad(
      pass,
      where: placedAt(),
      sampler: SamplerOptions.nearestClamp,
    );
    pass.draw();
    // The same depth again, so `less` rejects every fragment of it: the cyan
    // tint must not reach the picture.
    scene.bindQuad(
      pass,
      where: placedAt(),
      tint: tinted(0, 1, 1, 1),
      sampler: SamplerOptions.nearestClamp,
    );
    pass
      ..draw()
      ..submit();

    final pixels = await scene.device.readback(target);
    expect(
      _texel(pixels, 4, 0, 1),
      _red,
      reason: 'the second draw was at an equal depth and `less` refused it',
    );
    expect(await scene.device.debugDrainErrors('the depth test'), isNull);
    scene.device.dispose();
  });

  group('what this backend refuses', () {
    test('a blend constant, from both ends', () async {
      final scene = await _scene();
      if (scene == null) return;
      expect(scene.device.supportsBlendColor, isFalse);
      final pass = scene.device.beginRenderPass(
        RenderPassDescriptor(colors: <ColorTarget>[_clearTo(scene.target())]),
      );
      expect(
        () => pass.setBlendColor(Vector4(1, 1, 1, 1)),
        throwsUnsupportedError,
      );
      expect(
        () => pass.setBlend(
          const BlendState(sourceColorFactor: BlendFactor.blendColor),
        ),
        throwsUnsupportedError,
      );
      pass.submit();
      scene.device.dispose();
    });

    test('a wireframe, which this API has no fill mode for', () async {
      final scene = await _scene();
      if (scene == null) return;
      expect(scene.device.supportsWireframe, isFalse);
      final pass = scene.device.beginRenderPass(
        RenderPassDescriptor(colors: <ColorTarget>[_clearTo(scene.target())]),
      );
      expect(
        () => pass.setPolygonMode(PolygonMode.line),
        throwsUnsupportedError,
      );
      pass
        ..setPolygonMode(PolygonMode.fill)
        ..submit();
      scene.device.dispose();
    });

    test('an attachment index this pass does not have', () async {
      final scene = await _scene();
      if (scene == null) return;
      final pass = scene.device.beginRenderPass(
        RenderPassDescriptor(colors: <ColorTarget>[_clearTo(scene.target())]),
      );
      expect(
        () => pass.setBlend(BlendState.additive, attachment: 1),
        throwsArgumentError,
      );
      pass.submit();
      scene.device.dispose();
    });

    test('a format WebGPU has no spelling for at all', () async {
      // Three of the engine's formats stay false whatever adapter this runs on,
      // and that is a property of the API rather than work left undone:
      // `a8UNormInt` was dropped in favour of `r8unorm` plus a swizzle, and no
      // WebGPU feature exposes the HDR profile of ASTC — `texture-compression-
      // astc` unlocks the LDR blocks and there is no second feature behind it.
      final scene = await _scene();
      if (scene == null) return;
      for (final format in const <TextureFormat>[
        TextureFormat.a8UNormInt,
        TextureFormat.astc4x4HDR,
        TextureFormat.astc8x8HDR,
      ]) {
        expect(
          scene.device.supportsTextureFormat(format),
          isFalse,
          reason: '${format.name} has no WebGPU spelling and never will',
        );
      }
      scene.device.dispose();
    });

    test('a compressed render target, whatever the adapter carries', () async {
      // A spelling is not permission to draw into one. Every compressed format
      // has a spelling now that the families are asked for, so the thing that
      // stops a compressed render target is this refusal rather than a missing
      // table entry — and `RENDER_ATTACHMENT` on a compressed format is a
      // browser message about a usage flag that names nothing a caller wrote.
      final scene = await _scene();
      if (scene == null) return;
      expect(
        () => scene.device.createTexture(
          const RenderTargetSpec(
            width: 8,
            height: 8,
            format: TextureFormat.bc1RGBAUNormInt,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        scene.device.createCubeRenderTarget(
          size: 8,
          format: TextureFormat.bc1RGBAUNormInt,
        ),
        isNull,
      );
      scene.device.dispose();
    });
  });

  group('the compression families', () {
    test('a format is supported exactly when its feature was granted', () async {
      // **The coupling, asked of the device rather than of a wish.** `create`
      // asks the adapter which families it carries and requests those, because
      // asking for one the adapter lacks rejects the promise outright — a game
      // that does not start. What came back may still be less than what was
      // asked for, so the capability reads `gpuDevice.features` and this asserts
      // that it does.
      //
      // Mutation: answer from the list of wants instead. On an adapter carrying
      // all three nothing moves; on one carrying none, every line below fails.
      final scene = await _scene();
      if (scene == null) return;
      final device = scene.device;
      for (final (format, feature) in <(TextureFormat, String)>[
        (TextureFormat.bc7RGBAUNormInt, GpuFeature.textureCompressionBc),
        (TextureFormat.etc2RGB8UNormInt, GpuFeature.textureCompressionEtc2),
        (TextureFormat.astc4x4LDR, GpuFeature.textureCompressionAstc),
      ]) {
        expect(
          device.supportsTextureFormat(format),
          device.gpuDevice.features.has(feature),
          reason:
              '${format.name} is reported as ${device.supportsTextureFormat(format)} '
              'while the device ${device.gpuDevice.features.has(feature) ? 'has' : 'has not'} '
              '"$feature"',
        );
      }
      device.dispose();
    });

    test('a BC1 chain uploads in blocks and samples the colour it holds', () async {
      // **What the conformance suite's one-block check cannot ask.** That one
      // uploads a single 4x4 block and samples it, which is the family working
      // at all; this one hands over a chain, and a chain is where the block
      // arithmetic goes wrong quietly. `writeTexture`'s `bytesPerRow` for a
      // compressed level is a row of *blocks* and `rowsPerImage` counts block
      // rows — an 8x8 BC1 level is two rows of sixteen bytes, not eight rows of
      // anything — and a level measured in texels is either a write the browser
      // refuses or, with the rounding done the other way, a lower level built
      // from a prefix that draws a plausible wrong picture the moment something
      // minifies.
      //
      // Mutation: multiply `bytesPerRow` by the block width in
      // `gpuBlockLayoutOf`. The upload is refused and this comes back black.
      final scene = await _scene();
      if (scene == null) return;
      final device = scene.device;
      if (!device.supportsTextureFormat(TextureFormat.bc1RGBAUNormInt)) {
        markTestSkipped('this adapter carries no texture-compression-bc');
        device.dispose();
        return;
      }

      // One 4x4 BC1 block of a single colour: both 565 endpoints the same, every
      // two-bit pick zero. Assembled from the bit layout rather than taken from
      // an encoder, so the colour that comes back is arithmetic.
      Uint8List block(int r, int g, int b) {
        final c = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
        return Uint8List.fromList(<int>[
          c & 0xFF,
          c >> 8,
          c & 0xFF,
          c >> 8,
          0,
          0,
          0,
          0,
        ]);
      }

      // 8x8 is two blocks by two, and its one level below is a single block.
      final base = Uint8List(4 * 8)
        ..setAll(0, block(136, 68, 204))
        ..setAll(8, block(136, 68, 204))
        ..setAll(16, block(136, 68, 204))
        ..setAll(24, block(136, 68, 204));
      final texture = device.createTextureFromPixels(
        width: 8,
        height: 8,
        format: TextureFormat.bc1RGBAUNormInt,
        pixels: ByteData.sublistView(base),
        mipLevels: <ByteData>[ByteData.sublistView(block(136, 68, 204))],
      );
      expect(
        texture,
        isNotNull,
        reason: 'an 8x8 BC1 texture with one level below it was refused',
      );

      // A level whose bytes are measured the wrong way is refused before a
      // texture exists, which is the other half of the same arithmetic.
      expect(
        device.createTextureFromPixels(
          width: 8,
          height: 8,
          format: TextureFormat.bc1RGBAUNormInt,
          pixels: ByteData.sublistView(base),
          mipLevels: <ByteData>[ByteData(32)],
        ),
        isNull,
        reason: 'a 4x4 BC1 level is one block, and 32 bytes is four',
      );

      final target = scene.target();
      final pass = device.beginRenderPass(
        RenderPassDescriptor(colors: <ColorTarget>[_clearTo(target)]),
      )..bindPipeline(scene.pipeline);
      scene.bindQuad(
        pass,
        where: placedAt(),
        sampler: SamplerOptions.nearestClamp,
      );
      pass
        ..bindTexture(
          scene.fragmentStage,
          'palette',
          texture!,
          sampler: SamplerOptions.nearestClamp,
        )
        ..draw()
        ..submit();

      final pixels = await device.readPixels(target);
      expect(await device.debugDrainErrors('the compressed draw'), isNull);
      final got = _texel(pixels!, 4, 1, 1);
      // BC1 stores 5:6:5, so the endpoint comes back as (140, 69, 206). Eight is
      // the same tolerance the conformance suite allows for the same reason.
      for (final (channel, read, want) in <(String, int, int)>[
        ('red', got[0], 136),
        ('green', got[1], 68),
        ('blue', got[2], 204),
      ]) {
        expect(
          (read - want).abs(),
          lessThanOrEqualTo(8),
          reason: 'the block encodes $channel $want and sampled as $read',
        );
      }
      device.dispose();
    });
  });

  group('readPixels of a float target', () {
    // **The contract names this method as the way to read a float target back,
    // and nothing in the conformance suite asks for it.** That suite reads back
    // twenty-odd targets and every one of them is `r8g8b8a8UNormInt`; the only
    // check that mentions a float format is the one asserting `readback`
    // *refuses* it, and the refusal's own message says the caller's move is
    // `readPixels`. So the promise had no witness on any backend — which is why
    // these are here and not in `flutter3d_conformance`: a check added there
    // would fail on WebGL2 today, where `readPixels(RGBA, UNSIGNED_BYTE)` of an
    // RGBA16F attachment is an INVALID_OPERATION that leaves a pack buffer of
    // zeros and a future that completes successfully with a black picture. That
    // is a finding about that backend rather than something this change may
    // quietly turn into a red build.
    //
    // Mutation: drop the conversion pass and copy the float bytes straight out.
    // Half-floats read as eight-bit RGBA are not the colour, and every
    // expectation below moves.
    Future<List<int>> read(
      WebGpuDevice device,
      TextureFormat format,
      Vector4 colour,
    ) async {
      final target = device.createTexture(
        RenderTargetSpec(width: 4, height: 4, format: format),
      );
      device
          .beginRenderPass(
            RenderPassDescriptor(
              colors: <ColorTarget>[
                ColorTarget(texture: target, clearValue: colour),
              ],
            ),
          )
          .submit();
      final pixels = await device.readPixels(target);
      expect(
        await device.debugDrainErrors('the ${format.name} conversion'),
        isNull,
      );
      expect(
        pixels,
        isNotNull,
        reason:
            '${format.name} came back null; the contract sends a float '
            'target here',
      );
      expect(
        pixels!.lengthInBytes,
        4 * 4 * 4,
        reason:
            'the answer is the region times four bytes, whatever the '
            'source format was',
      );
      return _texel(pixels, 4, 2, 2);
    }

    test('the half-float target the engine renders into', () async {
      final scene = await _scene();
      if (scene == null) return;
      final got = await read(
        scene.device,
        TextureFormat.r16g16b16a16Float,
        Vector4(0.25, 0.5, 0.75, 1.0),
      );
      // A quarter, a half and three quarters of 255, to a rounding.
      expect(got[0], closeTo(64, 2));
      expect(got[1], closeTo(128, 2));
      expect(got[2], closeTo(191, 2));
      expect(got[3], 255);
      scene.device.dispose();
    });

    test('the full-width float the morph path uploads', () async {
      final scene = await _scene();
      if (scene == null) return;
      final got = await read(
        scene.device,
        TextureFormat.r32g32b32a32Float,
        Vector4(1.0, 0.0, 0.5, 1.0),
      );
      expect(got[0], 255);
      expect(got[1], 0);
      expect(got[2], closeTo(128, 2));
      expect(got[3], 255);
      scene.device.dispose();
    });

    test('a value outside the range clamps rather than wrapping', () async {
      // What the software rasteriser's own float-to-byte does, and what a caller
      // comparing a tone-mapped frame against a PNG is asking for. A conversion
      // that let 2.0 wrap would come back near zero and read as a black frame.
      final scene = await _scene();
      if (scene == null) return;
      final got = await read(
        scene.device,
        TextureFormat.r16g16b16a16Float,
        Vector4(4.0, -1.0, 0.5, 1.0),
      );
      expect(got[0], 255);
      expect(got[1], 0);
      expect(got[2], closeTo(128, 2));
      scene.device.dispose();
    });

    test('what stays null, and why each is not a gap', () async {
      final scene = await _scene();
      if (scene == null) return;
      final device = scene.device;

      // Tile memory holds nothing after the pass, which here is an attachment
      // allocated without TEXTURE_BINDING — so the conversion could not sample
      // it either.
      expect(
        await device.readPixels(
          device.createTexture(
            const RenderTargetSpec(
              width: 4,
              height: 4,
              format: TextureFormat.r8g8b8a8UNormInt,
              storageMode: StorageMode.deviceTransient,
            ),
          ),
        ),
        isNull,
      );

      // Multisampled, which is the refusal `readbackRegionOf` states above every
      // backend: there are no pixels to copy until a pass resolves it. Read the
      // resolve target.
      expect(
        await device.readPixels(scene.target(sampleCount: 4)),
        isNull,
        reason: 'a multisampled target is refused on every backend',
      );

      // sRGB, and this one is a decision. A conversion pass samples, and
      // sampling decodes — so a picture from here would be a third answer beside
      // the two the other backends already give. Read the same texture through
      // its non-sRGB layout.
      expect(
        await device.readPixels(
          device.createTexture(
            const RenderTargetSpec(
              width: 4,
              height: 4,
              format: TextureFormat.r8g8b8a8UNormIntSRGB,
            ),
          ),
        ),
        isNull,
      );
      device.dispose();
    });
  });

  test(
    'a cube target holds a chain, and the device says a pass may fill it',
    () async {
      // Both halves `ReflectionProbeNode.supportedOn` asks for, in one place.
      // They were split for an iteration — the cube was made and the chain was
      // refused — and the split is what this guards against coming back: a cube
      // with levels nobody may draw into is a mirror at every roughness, and a
      // true beside a null cube is a probe that crashes instead of being skipped.
      // What the levels actually *do* is asked by the conformance suite, which
      // clears one and reads it back, and by `reflection_probe_test.dart`.
      final scene = await _scene();
      if (scene == null) return;
      expect(scene.device.supportsCubeTextures, isTrue);
      expect(scene.device.supportsRenderToMip, isTrue);
      final cube = scene.device.createCubeRenderTarget(
        size: 8,
        format: TextureFormat.r16g16b16a16Float,
        mipLevels: 4,
      );
      expect(cube, isNotNull);
      // Cleared through the level rather than merely allocated: a chain the
      // allocator accepted and the attachment path refused would pass every
      // assertion above.
      scene.device
          .beginRenderPass(
            RenderPassDescriptor(
              colors: <ColorTarget>[
                ColorTarget(
                  texture: cube!,
                  face: 5,
                  mipLevel: 3,
                  clearValue: Vector4(1, 1, 1, 1),
                ),
              ],
            ),
          )
          .submit();
      expect(await scene.device.debugDrainErrors('a cube chain'), isNull);
      scene.device.dispose();
    },
  );

  group('a uniform block', () {
    test('the stage does not declare comes back false', () async {
      final scene = await _scene();
      if (scene == null) return;
      final pass = scene.device.beginRenderPass(
        RenderPassDescriptor(colors: <ColorTarget>[_clearTo(scene.target())]),
      )..bindPipeline(scene.pipeline);
      expect(
        pass.bindUniformBlock(
          scene.vertexStage,
          'NotInThisShader',
          <String, Float32List>{'value': tinted(1, 1, 1, 1)},
        ),
        isFalse,
      );
      pass.submit();
      scene.device.dispose();
    });

    test('missing a member the caller named throws instead', () async {
      // The distinction the contract draws, and it is load-bearing: a whole
      // block nobody read is ordinary, and a block without a member the caller
      // wrote means the two ends disagree about its shape — where zeros are a
      // plausible value and silence is indistinguishable from working.
      final scene = await _scene();
      if (scene == null) return;
      final pass = scene.device.beginRenderPass(
        RenderPassDescriptor(colors: <ColorTarget>[_clearTo(scene.target())]),
      )..bindPipeline(scene.pipeline);
      expect(
        () => pass.bindUniformBlock(
          scene.vertexStage,
          'Placement',
          <String, Float32List>{'nowhere': tinted(1, 1, 1, 1)},
        ),
        throwsStateError,
      );
      pass.submit();
      scene.device.dispose();
    });
  });

  test('presenting copies the frame into the canvas', () async {
    // The canvas is configured with the engine's own colour format rather than
    // the machine's preferred one, because presenting is a texture-to-texture
    // copy and a copy demands the formats match. A mismatch is a validation
    // error and nothing else — which is exactly what the error scope catches.
    final scene = await _scene();
    if (scene == null) return;
    final frame = scene.target(size: 32);
    expect(scene.device.present(frame), isNotNull);
    expect(await scene.device.debugDrainErrors('present'), isNull);
    scene.device.dispose();
  });
}
