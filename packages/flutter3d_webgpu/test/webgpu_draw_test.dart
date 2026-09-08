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
    // A four-pixel row samples the two-texel palette at 0.125, 0.375, 0.625 and
    // 0.875, so the left half is the left texel and the right half the right.
    expect(_texel(pixels, 4, 0, 1), _red);
    expect(_texel(pixels, 4, 3, 1), _green);
    expect(await scene.device.debugDrainErrors('the draw'), isNull);
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

    test('a mip level to draw into, but not a cube to draw into', () async {
      // The mip answers no in this iteration so that a reflection probe is
      // skipped rather than crashed — `ReflectionProbeNode.supportedOn` asks
      // for cube textures *and* render-to-mip, so one no is enough. The cube
      // render target used to answer no beside it and no longer does: the
      // conformance suite reads `supportsCubeTextures` as a promise that a pass
      // can name a face, and a backend that answered true and handed back no
      // cube failed that check rather than declining it.
      final scene = await _scene();
      if (scene == null) return;
      expect(scene.device.supportsCubeTextures, isTrue);
      expect(scene.device.supportsRenderToMip, isFalse);
      expect(
        scene.device.createCubeRenderTarget(
          size: 4,
          format: TextureFormat.r16g16b16a16Float,
        ),
        isNotNull,
      );
      expect(
        scene.device.supportsTextureFormat(TextureFormat.bc7RGBAUNormInt),
        isFalse,
        reason: 'this device requests none of the compression features',
      );
      expect(await scene.device.debugDrainErrors('a cube target'), isNull);
      scene.device.dispose();
    });
  });

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
