/// Strips, points and the viewport's depth range on the software
/// rasteriser.
///
///     dart test test/strip_point_test.dart
///
/// The rasteriser drew triangle and line lists and refused the other three
/// topologies with an untyped error from the draw, which made strips and
/// points something no backend could be asked about: every other backend
/// assembled them, and the one the others are compared against could not.
/// It draws all five now, and the contract's two promises about strips are
/// held here with pixels: a strip faces one way all along, and an all-ones
/// index restarts it.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 16;

const VertexLayoutDescriptor _layout = VertexLayoutDescriptor(<BufferLayout>[
  BufferLayout(
    strideInBytes: 12,
    attributes: <InputAttribute>[
      InputAttribute(name: 'position', format: VertexFormat.float32x3),
    ],
  ),
  BufferLayout(
    strideInBytes: 16,
    attributes: <InputAttribute>[
      InputAttribute(name: 'color', format: VertexFormat.float32x4),
    ],
  ),
]);

/// What one draw left: the colour and the depth, a float each per pixel.
typedef _Frame = ({Float32List colour, Float32List depth});

/// Draws [positions] (clip x, y, z per vertex) in white as [type], indexed
/// by [indices] when given, and reads the frame back.
_Frame _draw(
  PrimitiveType type,
  List<double> positions, {
  List<int>? indices,
  CullMode cull = CullMode.none,
  PassViewport? viewport,
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final color = device.createTexture(
    const RenderTargetDescriptor(
      width: _size,
      height: _size,
      format: TextureFormat.r16g16b16a16Float,
    ),
  );
  final depth = device.createTexture(
    const RenderTargetDescriptor(
      width: _size,
      height: _size,
      format: TextureFormat.d32Float,
    ),
  );
  final count = positions.length ~/ 3;
  final vertex = device.shaders['DebugLineVertex']!;
  final fragment = device.shaders['DebugLine']!;
  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(texture: color, clearValue: ClearColor.transparentBlack),
      ],
      depth: DepthTarget(texture: depth),
    ),
  );
  pass
    ..bindPipeline(device.createPipeline(vertex, fragment, layout: _layout))
    ..setPrimitiveType(type)
    ..setCullMode(cull)
    ..setWindingOrder(WindingOrder.counterClockwise)
    ..setDepthWrite(enabled: true)
    ..setDepthCompare(CompareFunction.always)
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(
      ByteData.sublistView(Float32List.fromList(positions)),
      count,
    )
    ..bindVertexData(
      ByteData.sublistView(
        Float32List.fromList(List<double>.filled(count * 4, 1)),
      ),
      count,
      slot: 1,
    );
  if (viewport != null) pass.setViewport(viewport);
  if (indices != null) {
    pass.bindIndexData(
      ByteData.sublistView(Uint16List.fromList(indices)),
      IndexType.int16,
      indices.length,
    );
  }
  pass
    ..draw()
    ..submit();
  return (
    colour: (color.backend as CpuTexture).pixels,
    depth: (depth.backend as CpuTexture).plane().depthBuffer(),
  );
}

bool _lit(_Frame frame, int x, int y) =>
    frame.colour[(y * _size + x) * 4] > 0.5;

int _litCount(_Frame frame) => <int>[
  for (var i = 0; i < _size * _size; i++)
    if (frame.colour[i * 4] > 0.5) i,
].length;

/// A quad from [left] to [right] across, -0.5 to 0.5 up, as a strip: bottom
/// left, bottom right, top left, top right.
List<double> _quad(double left, double right) => <double>[
  left, -0.5, 0.5, //
  right, -0.5, 0.5,
  left, 0.5, 0.5,
  right, 0.5, 0.5,
];

/// The pixel centre [x], [y] (row zero at the top) in clip space.
List<double> _at(int x, int y) => <double>[
  (x + 0.5) / _size * 2 - 1,
  1 - (y + 0.5) / _size * 2,
  0.5,
];

void main() {
  test('a triangle strip faces one way all along', () {
    // Mutation: drop the corner swap on the odd triangles in
    // `_assembleStrip`. The second triangle of the quad is then wound the
    // other way, culled as a back face, and half the quad goes missing.
    final frame = _draw(
      PrimitiveType.triangleStrip,
      _quad(-0.5, 0.5),
      cull: CullMode.backFace,
    );
    expect(_litCount(frame), 64, reason: 'an 8 by 8 quad, both halves');
    expect(
      _lit(frame, 10, 5),
      isTrue,
      reason: 'above the diagonal: the second',
    );
    expect(_lit(frame, 5, 10), isTrue, reason: 'below it: the first');
  });

  test('an all-ones index ends a strip and starts the next', () {
    // Mutation: treat 0xFFFF as an index. The strip runs on into a vertex
    // that does not exist, and the second quad is never drawn.
    final frame = _draw(
      PrimitiveType.triangleStrip,
      <double>[..._quad(-0.875, -0.125), ..._quad(0.125, 0.875)],
      indices: <int>[0, 1, 2, 3, 0xFFFF, 4, 5, 6, 7],
    );
    expect(_lit(frame, 3, 8), isTrue, reason: 'the first quad');
    expect(_lit(frame, 12, 8), isTrue, reason: 'the second quad');
    expect(
      _lit(frame, 8, 8),
      isFalse,
      reason: 'no triangle joins the two across the restart',
    );
    expect(_litCount(frame), 2 * 6 * 8);
  });

  test('a line strip joins its vertices in order', () {
    final frame = _draw(PrimitiveType.lineStrip, <double>[
      ..._at(2, 8),
      ..._at(13, 8),
      ..._at(13, 2),
    ]);
    expect(_lit(frame, 7, 8), isTrue, reason: 'the first segment');
    expect(_lit(frame, 13, 5), isTrue, reason: 'the second segment');
    expect(_lit(frame, 7, 4), isFalse, reason: 'and nothing closes it');
  });

  test('a point is the one pixel its vertex lands in', () {
    // Mutation: assemble points as a list of triangles. Three vertices
    // become one triangle of some forty pixels where three belong.
    final frame = _draw(PrimitiveType.point, <double>[
      ..._at(2, 3),
      ..._at(8, 8),
      ..._at(13, 1),
    ]);
    expect(_litCount(frame), 3);
    expect(
      _lit(frame, 2, 3) && _lit(frame, 8, 8) && _lit(frame, 13, 1),
      isTrue,
    );
  });

  test("the viewport's depth range is where clip depth lands", () {
    // Mutation: ignore `minDepth` and `maxDepth` in `_Window.depthOf`. The
    // depth written is the clip depth, 0.5, and not 0.375.
    final frame = _draw(
      PrimitiveType.triangleStrip,
      _quad(-1, 1),
      viewport: const PassViewport(
        width: _size * 1.0,
        height: _size * 1.0,
        minDepth: 0.25,
        maxDepth: 0.5,
      ),
    );
    expect(frame.depth[8 * _size + 8], closeTo(0.375, 1e-6));
  });

  test('a fractional viewport moves the picture by the fraction', () {
    // A viewport half a pixel to the right of the target's corner: a point
    // three quarters of the way across pixel 3 lands a quarter into pixel 4.
    // Mutation: drop `fractionX` from the window position, and it stays in
    // pixel 3.
    final frame = _draw(
      PrimitiveType.point,
      <double>[(3.75 / _size) * 2 - 1, 1 - (8.5 / _size) * 2, 0.5],
      viewport: const PassViewport(
        x: 0.5,
        width: _size * 1.0,
        height: _size * 1.0,
      ),
    );
    expect(_lit(frame, 4, 8), isTrue);
    expect(_litCount(frame), 1);
  });
}
