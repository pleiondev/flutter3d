/// Instanced draws on the software backend, and what makes them instanced.
///
/// The property under test is the only one that distinguishes an instanced
/// draw from the same geometry drawn twice: a buffer marked
/// [VertexStepMode.instance] is read at the *instance* index and stays there
/// for every vertex of it. Get that wrong in the obvious way — read it at the
/// vertex index like everything else — and two instances still draw, still
/// blend, and still look like a plausible picture.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A full-screen triangle, positions only, for slot zero.
final Float32List _positions = Float32List.fromList(<double>[
  -1, -1, 0.5, //
  3, -1, 0.5,
  -1, 3, 0.5,
]);

/// Three vertices' worth of colours, so a per-vertex misread has something
/// wrong to find rather than running off the end of the buffer.
///
/// The values are deliberately far apart: instance zero is a tenth, instance
/// one is a half. Reading them per vertex instead gives a tenth for every
/// instance, which is a different number and not merely a different picture.
final Float32List _perInstance = Float32List.fromList(<double>[
  0.10, 0, 0, 1, //
  0.50, 0, 0, 1,
  0.90, 0, 0, 1,
]);

final Uint16List _indices = Uint16List.fromList(<int>[0, 1, 2]);

const VertexLayoutSpec _layout = VertexLayoutSpec(<BufferLayout>[
  BufferLayout(
    strideInBytes: 12,
    attributes: <InputAttribute>[
      InputAttribute(name: 'position', format: VertexFormat.float32x3),
    ],
  ),
  BufferLayout(
    strideInBytes: 16,
    stepMode: VertexStepMode.instance,
    attributes: <InputAttribute>[
      InputAttribute(name: 'color', format: VertexFormat.float32x4),
    ],
  ),
]);

/// Draws [instances] of the triangle and reports the red channel of pixel zero.
double _draw(int instances) {
  final device = CpuDevice(
    width: 8,
    height: 8,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final colour = device.createTexture(const RenderTargetSpec(
    width: 8,
    height: 8,
    format: TextureFormat.r16g16b16a16Float,
  ));

  final vertex = device.shaders['DebugLineVertex']!;
  final fragment = device.shaders['DebugLine']!;
  final pass = device.beginRenderPass(RenderPassDescriptor(
    colors: <ColorTarget>[
      ColorTarget(
        texture: colour,
        loadAction: LoadAction.clear,
        clearValue: Vector4.zero(),
      ),
    ],
  ));
  pass
    ..bindPipeline(device.createPipeline(vertex, fragment, layout: _layout))
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..setBlend(BlendState.additive)
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(ByteData.sublistView(_positions), 3)
    ..bindVertexData(ByteData.sublistView(_perInstance), 3, slot: 1)
    ..bindIndexData(ByteData.sublistView(_indices), IndexType.int16, 3)
    ..draw(instanceCount: instances)
    ..submit();

  return (colour.backend as CpuTexture).pixels[0];
}

void main() {
  test('each instance reads its own element of the per-instance buffer', () {
    // One instance is instance zero's colour, and nothing else.
    expect(_draw(1), closeTo(0.10, 1e-5));

    // Two instances add the first two colours. A backend that read the
    // per-instance buffer at the vertex index would give two tenths here —
    // the same triangle twice — which is why the colours are far apart.
    expect(_draw(2), closeTo(0.60, 1e-5),
        reason: 'the second instance did not read the second colour');

    // And three, which also proves the first two were not a coincidence of
    // two numbers that happen to sum like that.
    expect(_draw(3), closeTo(1.50, 1e-5));
  });

  test('a slot the layout names must be bound', () {
    final device = CpuDevice(
      width: 4,
      height: 4,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final colour = device.createTexture(const RenderTargetSpec(
      width: 4,
      height: 4,
      format: TextureFormat.r16g16b16a16Float,
    ));
    final vertex = device.shaders['DebugLineVertex']!;
    final fragment = device.shaders['DebugLine']!;
    final pass = device.beginRenderPass(RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(texture: colour, loadAction: LoadAction.clear),
      ],
    ));
    pass
      ..bindPipeline(device.createPipeline(vertex, fragment, layout: _layout))
      ..setPrimitiveType(PrimitiveType.triangle)
      ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
        'view_projection': Float32List.fromList(Matrix4.identity().storage),
      })
      // Slot one is never bound.
      ..bindVertexData(ByteData.sublistView(_positions), 3)
      ..bindIndexData(ByteData.sublistView(_indices), IndexType.int16, 3);

    expect(() => pass.draw(), throwsA(isA<StateError>()),
        reason: 'a missing slot has to say so; reading whatever slot zero '
            'holds instead is how a colour becomes a position');
  });

  test('an integer attribute is refused rather than reinterpreted', () {
    final device = CpuDevice(
      width: 4,
      height: 4,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    expect(
      () => device.createPipeline(
        device.shaders['DebugLineVertex']!,
        device.shaders['DebugLine']!,
        layout: const VertexLayoutSpec(<BufferLayout>[
          BufferLayout(
            strideInBytes: 4,
            attributes: <InputAttribute>[
              InputAttribute(name: 'joints', format: VertexFormat.uint32),
            ],
          ),
        ]),
      ),
      throwsA(isA<UnsupportedError>()),
      reason: 'a stage here receives floats, and reinterpreting an integer as '
          'one turns a joint index into 1.4e-45',
    );
  });
}
