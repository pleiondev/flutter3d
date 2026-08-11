/// Drives the HAL against WebGL2 and checks what came out.
///
/// Not a demo. This is the harness that answers the question a fake backend
/// cannot: is `flutter3d_hal` *implementable*, or only callable? Everything
/// here goes through `GraphicsDevice` and `CommandEncoder` — no WebGL call is
/// made by this file — so what it exercises is the seam itself.
///
/// It checks four things that would each be silent if wrong:
///
///  1. **Vertex layout from shader reflection.** The HAL's `bindVertexBuffer`
///     carries no layout, because flutter_gpu takes one from the vertex
///     shader's `in` declarations. Two interleaved attributes here — position
///     and texcoord, as the engine's own meshes have — prove the backend can
///     reconstruct the packing. A wrong stride draws a scrambled triangle,
///     which on a full-screen triangle still fills the screen.
///  2. **std140 uniform blocks by member name.** `bindUniformBlock` fills
///     members by name; the offsets come from reflection.
///  3. **The vertical flip in `readPixels`.** GL's origin is bottom-left and
///     the HAL says row-major from the top. The fragment colour is a gradient
///     in Y, so a frame read upside down is off by the whole image rather than
///     by a subtlety.
///  4. **Presentation without a round trip.** The canvas is composited by the
///     browser; nothing here decodes an image.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' show Vector4;
import 'package:flutter3d_hal/flutter3d_hal.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';

const int kWidth = 256;
const int kHeight = 192;

/// Position (xyz) then texcoord (uv), interleaved — the engine's own shape.
///
/// A full-screen triangle, so every pixel of the target is written and a
/// readback has something definite to say about every row.
final Float32List kVertices = Float32List.fromList(<double>[
  -1.0, -1.0, 0.0, 0.0, 0.0, //
  3.0, -1.0, 0.0, 2.0, 0.0, //
  -1.0, 3.0, 0.0, 0.0, 2.0, //
]);

final Uint32List kIndices = Uint32List.fromList(<int>[0, 1, 2]);

/// Locations are explicit and ascending, which is what lets the backend read
/// the interleaved packing back off the program. `VertexLayout` in the engine
/// documents the same convention for the other backend.
const String kVertexSource = '''#version 300 es
layout(location = 0) in vec3 position;
layout(location = 1) in vec2 texcoord;
out vec2 v_uv;
void main() {
  v_uv = texcoord;
  gl_Position = vec4(position, 1.0);
}
''';

const String kFragmentSource = '''#version 300 es
precision highp float;
in vec2 v_uv;
uniform FragInfo {
  vec4 base_color;
  vec4 unused_second_member;
} frag_info;
uniform sampler2D base_color_texture;
out vec4 frag_color;
void main() {
  // A gradient in Y, so reading the frame upside down is unmistakable.
  vec3 tint = texture(base_color_texture, v_uv).rgb;
  frag_color = vec4(frag_info.base_color.rgb * tint * clamp(v_uv.y, 0.0, 1.0),
                    1.0);
}
''';

void main() => runApp(const HarnessApp());

class HarnessApp extends StatefulWidget {
  const HarnessApp({super.key});

  @override
  State<HarnessApp> createState() => _HarnessAppState();
}

class _HarnessAppState extends State<HarnessApp> {
  final List<String> _log = <String>[];
  Widget? _frame;
  bool _failed = false;

  void _say(String line) {
    _log.add(line);
    // ignore: avoid_print
    print(line);
  }

  void _check(bool ok, String what) {
    _say('${ok ? 'PASS' : 'FAIL'}  $what');
    if (!ok) _failed = true;
  }

  @override
  void initState() {
    super.initState();
    try {
      _run();
    } catch (error, stack) {
      _say('THREW: $error');
      _say('$stack');
      _failed = true;
    }
    if (mounted) setState(() {});
  }

  void _run() {
    final device = WebGlDevice.create(
      width: kWidth,
      height: kHeight,
      sources: const ShaderSources(
        <String, String>{'Triangle': kVertexSource},
        <String, String>{'TriangleFragment': kFragmentSource},
      ),
    );
    if (device == null) {
      _check(false, 'WebGL2 context');
      return;
    }
    _check(true, 'WebGL2 context');

    // --- shaders and reflection -------------------------------------------
    final vertex = device.shaders['Triangle'];
    final fragment = device.shaders['TriangleFragment'];
    _check(vertex != null && fragment != null, 'both stages found by name');
    _check(device.shaders['NoSuchStage'] == null,
        'a missing name comes back null rather than throwing');
    if (vertex == null || fragment == null) return;

    final pipeline = device.createPipeline(vertex, fragment);
    final program = pipeline.backend as WebGlProgram;
    _check(program.attributes.length == 2, 'reflected two vertex attributes');
    _check(program.vertexFloats == 5,
        'reconstructed a 5-float vertex (3 position + 2 texcoord)');
    _check(program.blocks.containsKey('FragInfo'), 'reflected the FragInfo block');
    _check(program.blocks['FragInfo']!.offsets.containsKey('base_color'),
        'reflected base_color by member name');
    _check(program.samplers.containsKey('base_color_texture'),
        'reflected the sampler slot');

    // --- resources ---------------------------------------------------------
    final vertices = device.uploadGeometry(
        ByteData.sublistView(kVertices), GeometryUsage.vertices);
    final indices = device.uploadGeometry(
        ByteData.sublistView(kIndices), GeometryUsage.indices);

    // 2x2 opaque white, so the sampled tint multiplies by one and the expected
    // pixel value stays arithmetic anybody can check by hand.
    final white = Uint8List(2 * 2 * 4)..fillRange(0, 2 * 2 * 4, 255);
    final texture = device.createTextureFromPixels(
      width: 2,
      height: 2,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(white),
    );
    _check(texture != null, 'created a texture from pixels');

    final wrongSize = device.createTextureFromPixels(
      width: 2,
      height: 2,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(Uint8List(3)),
    );
    _check(wrongSize == null, 'pixels of the wrong size come back null');

    final colour = device.createTexture(const RenderTargetSpec(
      width: kWidth,
      height: kHeight,
      format: TextureFormat.r8g8b8a8UNormInt,
    ));
    final depth = device.createTexture(const RenderTargetSpec(
      width: kWidth,
      height: kHeight,
      format: TextureFormat.d24UnormS8Uint,
      storageMode: StorageMode.deviceTransient,
    ));

    // --- one pass, entirely through the HAL --------------------------------
    device.beginFrame();
    final pass = device.beginRenderPass(RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(texture: colour, clearValue: Vector4(0.0, 0.0, 0.0, 1.0)),
      ],
      depth: DepthTarget(texture: depth),
    ));

    _say('framebuffer: ${device.debugFramebufferStatus()}');
    _say(device.debugDrainErrors('after beginRenderPass') ?? 'no gl error after beginRenderPass');

    const full = ScreenRect(width: kWidth, height: kHeight);
    pass
      ..setViewport(full)
      ..setScissor(full)
      ..setPrimitiveType(PrimitiveType.triangle)
      ..setPolygonMode(PolygonMode.fill)
      ..setCullMode(CullMode.none)
      ..setWindingOrder(WindingOrder.counterClockwise)
      ..setDepthWrite(true)
      ..setDepthCompare(CompareFunction.less)
      ..setBlend(null)
      ..bindPipeline(pipeline)
      ..bindVertexBuffer(vertices, 3);
    _say(device.debugDrainErrors('after bindVertexBuffer') ?? 'no gl error after vertices');
    pass.bindIndexBuffer(indices, IndexType.int32, 3);
    _say(device.debugDrainErrors('after bindIndexBuffer') ?? 'no gl error after indices');

    final bound = pass.bindUniformBlock(vertex, 'FragInfo', <String, Float32List>{
      'base_color': Float32List.fromList(<double>[0.25, 0.5, 1.0, 1.0]),
    });
    _check(bound, 'bound FragInfo by member name');
    _check(
      !pass.bindUniformBlock(vertex, 'NoSuchBlock', <String, Float32List>{}),
      'a block the shader does not have comes back false, not a crash',
    );

    pass.bindTexture(fragment, 'base_color_texture', texture!,
        sampler: SamplerOptions.linearClamp);
    _say(device.debugDrainErrors('after bindings') ?? 'no gl error after bindings');
    pass.draw();
    _say(device.debugDrainErrors('after draw') ?? 'no gl error after draw');
    pass.submit();
    _say('pass submitted');

    // --- what came out -----------------------------------------------------
    unawaited(_verify(device, colour));
    _frame = device.present(colour, fit: BoxFit.contain);
  }

  Future<void> _verify(WebGlDevice device, TextureHandle colour) async {
    final pixels = await device.readPixels(colour);
    if (pixels == null) {
      _check(false, 'readPixels returned bytes');
      if (mounted) setState(() {});
      return;
    }
    final bytes = pixels.buffer.asUint8List();
    _check(bytes.length == kWidth * kHeight * 4, 'readPixels returned a frame');

    int at(int x, int y, int channel) => bytes[(y * kWidth + x) * 4 + channel];

    // Row 0 is the TOP after the flip, where the gradient is at its maximum:
    // base_color (0.25, 0.5, 1.0) x white x 1.0 = (64, 128, 255).
    final top = <int>[at(0, 0, 0), at(0, 0, 1), at(0, 0, 2)];
    final bottom = <int>[
      at(0, kHeight - 1, 0),
      at(0, kHeight - 1, 1),
      at(0, kHeight - 1, 2),
    ];
    _say('top row    $top   (expected about [64, 128, 255])');
    _say('bottom row $bottom   (expected about [0, 0, 0])');

    _check(
      (top[0] - 64).abs() <= 2 && (top[1] - 128).abs() <= 2 &&
          (top[2] - 255).abs() <= 2,
      'the uniform block reached the shader and the top row is the bright end',
    );
    _check(
      bottom[0] <= 2 && bottom[1] <= 2 && bottom[2] <= 2,
      'the frame is the right way up — row 0 is the top, not GL bottom-left',
    );

    _say(_failed ? '=== SOME CHECKS FAILED ===' : '=== ALL CHECKS PASSED ===');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF16181D),
          body: Row(
            children: <Widget>[
              SizedBox(
                width: kWidth.toDouble(),
                height: kHeight.toDouble(),
                child: _frame ?? const SizedBox.shrink(),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    for (final line in _log)
                      Text(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: line.startsWith('FAIL') || line.contains('THREW')
                              ? const Color(0xFFFF6B6B)
                              : Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
