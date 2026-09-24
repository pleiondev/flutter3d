/// A field stepped in a float target and read back through a vertex stage —
/// `H5`.
///
/// What `FieldPass` stands on, asked of the backend rather than assumed: that
/// a pass can render into a float target and keep values above one, that the
/// next pass can sample it, and that a vertex stage can read the result. The
/// existing float check covers upload only; this is the render-to-float half.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

const int _size = 4;

/// Three steps of `FieldDecay` (times one half, plus a tenth) from a start of
/// two, read through `VertexTextureProbeVertex` in each float format the
/// device supports.
///
/// Closed form: `2·0.5³ + 0.1·(1 − 0.5³)/(1 − 0.5)` = 0.425, byte 108. A
/// target that clamped the start to one lands at 0.3, byte 77, which is how
/// "renders into a float target" is told apart from "renders into something".
Future<void> checkFloatFieldSteps(GraphicsDevice device) async {
  final fullscreen = device.shaders['FullscreenVertex'];
  final kernel = device.shaders['FieldDecay'];
  final probeVertex = device.shaders['VertexTextureProbeVertex'];
  final probeFragment = device.shaders['VertexTextureProbe'];
  require(
    fullscreen != null &&
        kernel != null &&
        probeVertex != null &&
        probeFragment != null,
    'the field kernel or the vertex-texture probe is missing from the bundle',
  );

  final formats = <TextureFormat>[
    TextureFormat.r16g16b16a16Float,
    TextureFormat.r32g32b32a32Float,
  ].where(device.supportsTextureFormat).toList();
  if (formats.isEmpty) {
    throw const ConformanceDeclined(
      'this device supports neither float format as a render target, so a '
      'field has nowhere to live here',
    );
  }

  final triangle = Float32List.fromList(<double>[
    -1, -1, 0, 1, //
    3, -1, 2, 1,
    -1, 3, 0, -1,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  for (final format in formats) {
    final spec = RenderTargetSpec(width: _size, height: _size, format: format);
    var current = device.createTexture(spec);
    var next = device.createTexture(spec);

    // The start: a clear to two, above what an eight-bit target can hold.
    device
        .beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[
              ColorTarget(
                texture: current,
                clearValue: Vector4(2.0, 2.0, 2.0, 2.0),
              ),
            ],
          ),
        )
        .submit();

    final pipeline = device.createPipeline(fullscreen!, kernel!);
    for (var step = 0; step < 3; step++) {
      device.beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[
              ColorTarget(texture: next, loadAction: LoadAction.dontCare),
            ],
          ),
        )
        ..setPrimitiveType(PrimitiveType.triangle)
        ..setCullMode(CullMode.none)
        ..bindPipeline(pipeline)
        ..bindTexture(
          kernel,
          'field_texture',
          current,
          sampler: SamplerOptions.nearestClamp,
        )
        ..bindUniformBlock(kernel, 'FieldDecayInfo', <String, Float32List>{
          'params': Float32List.fromList(<double>[0.5, 0.1, 0.0, 0.0]),
        })
        ..bindVertexData(ByteData.sublistView(triangle), 3)
        ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
        ..draw()
        ..submit();
      final written = next;
      next = current;
      current = written;
    }

    // Read back through a vertex stage, into a target anything can read.
    final target = device.createTexture(
      const RenderTargetSpec(
        width: _size,
        height: _size,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    device.beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[
            ColorTarget(
              texture: target,
              clearValue: Vector4(0.0, 1.0, 0.0, 1.0),
            ),
          ],
        ),
      )
      ..setPrimitiveType(PrimitiveType.triangle)
      ..setCullMode(CullMode.none)
      ..bindPipeline(device.createPipeline(probeVertex!, probeFragment!))
      ..bindUniformBlock(probeVertex, 'ProbeInfo', <String, Float32List>{
        'at': Float32List.fromList(<double>[0.5, 0.5, 0.0, 0.0]),
      })
      ..bindTexture(
        probeVertex,
        'probe_texture',
        current,
        sampler: SamplerOptions.nearestClamp,
      )
      ..bindVertexData(
        ByteData.sublistView(
          Float32List.fromList(<double>[
            -1, -1, 0.5, //
            3, -1, 0.5,
            -1, 3, 0.5,
          ]),
        ),
        3,
      )
      ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
      ..draw()
      ..submit();

    final read = await device.readPixels(target);
    require(read != null, 'the probe target could not be read back');
    final red = read!.getUint8(0);
    require(
      (red - 108).abs() <= 2,
      'three steps of the decay kernel in $format read back $red where 108 '
      '(0.425) was the answer. 77 means the start was clamped to one: the '
      'target is not keeping floats. Anything else means a step read or wrote '
      'the wrong texels, or the vertex stage could not sample the result.',
    );
    for (final t in <TextureHandle>[current, next, target]) {
      device.releaseTexture(t);
    }
  }
}
