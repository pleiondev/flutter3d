/// The 1.0 features that change what a draw writes, each held by the pixels
/// it leaves: pass state (depth bias and its clamp, depth clamp, the colour
/// write mask, min and max blending, the viewport's fractions and its reach
/// past the target, a reversed depth range), the draw calls (non-indexed,
/// base vertex and first instance, several at once, indirect, a bundle, wide
/// indices), the uniform paths and the queries.
///
/// **Each check declines on a device without its feature**, because the
/// refusal half is the honesty check's, and each compares what the device
/// drew against what the contract says it draws. A probe that only made the
/// call passed every backend that had the call, whichever way round it
/// applied it: a bias with its sign flipped, a mask on the wrong channel and
/// a query in another unit all return normally. The arithmetic is what the
/// software rasteriser computes, so the CPU backend is the reference every
/// other is held to.
///
/// Everything draws through the debug-line stages: a position, a flat colour
/// and one matrix, which is the least a draw can be and still say which
/// triangle landed where.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

const int _size = 8;

const List<double> _red = <double>[1, 0, 0, 1];
const List<double> _green = <double>[0, 1, 0, 1];

/// A triangle over the whole target.
const List<List<double>> _whole = <List<double>>[
  <double>[-1, -1],
  <double>[3, -1],
  <double>[-1, 3],
];

/// A triangle in the left half only: pixel (1, 4) is inside it, the right
/// half is not.
const List<List<double>> _left = <List<double>>[
  <double>[-1, -1],
  <double>[0, -1],
  <double>[-1, 3],
];

/// Its mirror, in the right half: pixel (6, 4) is inside it.
const List<List<double>> _right = <List<double>>[
  <double>[1, -1],
  <double>[0, -1],
  <double>[1, 3],
];

/// The debug-line pair, or a failure naming what is missing.
(ShaderHandle, ShaderHandle) _stages(GraphicsDevice device) {
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  if (vertex == null || fragment == null) {
    decline(
      device,
      'has no debug-line stages yet, so nothing here can draw a flat colour',
    );
  }
  return (vertex, fragment);
}

TextureHandle _target(
  GraphicsDevice device, [
  TextureFormat format = TextureFormat.r8g8b8a8UNormInt,
]) => device.createTexture(
  RenderTargetDescriptor(width: _size, height: _size, format: format),
);

TextureHandle _depth(GraphicsDevice device) => device.createTexture(
  RenderTargetDescriptor(
    width: _size,
    height: _size,
    format: device.defaultDepthStencilFormat,
    storageMode: StorageMode.deviceTransient,
  ),
);

/// The bytes of [shape] at depth [z] in [colour]: position then colour, the
/// debug-line layout.
Float32List _vertices(
  List<List<double>> shape,
  List<double> colour, {
  /// Depth in clip space, NDC.
  double z = 0.5,
}) => Float32List.fromList(<double>[
  for (final corner in shape) ...<double>[corner[0], corner[1], z, ...colour],
]);

/// A pass over [target] (and [depth]) with the debug-line pipeline bound and
/// nothing culled.
CommandEncoder _pass(
  GraphicsDevice device,
  TextureHandle target, {
  TextureHandle? depth,
  /// A fraction of the depth range.
  double depthClear = 1.0,
  ClearColor clear = ClearColor.transparentBlack,
  RenderPassDescriptor Function(RenderPassDescriptor plain)? reshape,
}) {
  final (vertex, fragment) = _stages(device);
  final plain = RenderPassDescriptor(
    colors: <ColorTarget>[
      ColorTarget(
        texture: target,
        loadAction: LoadAction.clear,
        clearValue: clear,
      ),
    ],
    depth: depth == null
        ? null
        : DepthTarget(texture: depth, clearValue: depthClear),
  );
  return device.beginRenderPass(reshape == null ? plain : reshape(plain))
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(
      device.createPipelineFrom(
        PipelineDescriptor(vertex: vertex, fragment: fragment),
      ),
    );
}

/// Binds the identity matrix and [vertices] with indices `0, 1, 2, …`.
void _bind(GraphicsDevice device, PassEncoder pass, Float32List vertices) {
  final (vertex, _) = _stages(device);
  final count = vertices.length ~/ 7;
  pass
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(ByteData.sublistView(vertices), count)
    ..bindIndexData(
      ByteData.sublistView(
        Uint16List.fromList(<int>[for (var i = 0; i < count; i++) i]),
      ),
      IndexType.int16,
      count,
    );
}

/// Draws [shape] in [colour] at [z] into [pass].
void _draw(
  GraphicsDevice device,
  PassEncoder pass,
  List<List<double>> shape,
  List<double> colour, {
  /// Depth in clip space, NDC.
  double z = 0.5,
}) {
  _bind(device, pass, _vertices(shape, colour, z: z));
  pass.draw();
}

/// The six vertices of [_left] in red then [_right] in green.
Float32List _halves() => Float32List.fromList(<double>[
  ..._vertices(_left, _red),
  ..._vertices(_right, _green),
]);

/// Pixel ([x], [y]) of [target], counted from the top left, as RGBA bytes.
Future<List<int>> _pixel(
  GraphicsDevice device,
  TextureHandle target,
  int x,
  int y,
) async {
  final bytes = (await device.readback(target)).buffer.asUint8List();
  final at = (y * _size + x) * 4;
  return bytes.sublist(at, at + 4);
}

/// Whether [rgba] is [colour] (0–1 channels) within [tolerance] bytes, red,
/// green and blue.
bool _is(List<int> rgba, List<double> colour, {int tolerance = 4}) => <int>[
  0,
  1,
  2,
].every((int c) => (rgba[c] - (colour[c] * 255).round()).abs() <= tolerance);

const List<double> _clear = <double>[0, 0, 0, 0];

/// Holds the left half of [target] to [left] and the right to [right].
Future<void> _requireHalves(
  GraphicsDevice device,
  TextureHandle target, {
  required List<double> left,
  required List<double> right,
  required String what,
}) async {
  final l = await _pixel(device, target, 1, 4);
  final r = await _pixel(device, target, 6, 4);
  require(
    _is(l, left) && _is(r, right),
    '$what: the left half came back $l and the right $r, where '
    '${_name(left)} and ${_name(right)} belong',
  );
}

String _name(List<double> colour) => switch (colour) {
  _red => 'red',
  _green => 'green',
  _clear => 'the clear colour',
  _ => '$colour',
};

void _needs(GraphicsDevice device, List<DeviceFeature> features, String why) {
  final missing = features.where((DeviceFeature f) => !device.features.has(f));
  if (missing.isNotEmpty) {
    decline(
      device,
      'has no ${missing.map((f) => f.name).join(' or ')}, so $why',
    );
  }
}

// ---------------------------------------------------------------- state

/// A depth bias moves the depth that is tested, in the direction its sign
/// says, and a pass starts without one.
///
/// Red is drawn at 0.5 with depth writes on and `less`. Green then comes a
/// hair behind it with a bias pulling it forward, which has to land; a hair
/// in front of it with a bias pushing it back, which has to be rejected; and
/// the same hair in front in a new pass with no bias, which lands because the
/// last pass's bias did not follow. 4096 steps of the format's resolution is
/// at least 2.4e-4 in every depth format, against hairs of 1e-4.
///
/// Mutations: flip the sign in `CpuEncoder._biasOf`, and the first green is
/// rejected and the second lands; leave `_depthBias` set across passes, and
/// the last one is rejected.
Future<void> checkDepthBiasMovesTheDepth(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[DeviceFeature.depthBias], 'no bias is drawn');
  Future<List<int>> drawn({
    required double greenZ,
    required DepthBias? bias,
  }) async {
    final target = _target(device);
    final pass = _pass(device, target, depth: _depth(device))
      ..setDepthCompare(CompareFunction.less)
      ..setDepthWrite(enabled: true);
    _draw(device, pass, _whole, _red);
    if (bias != null) pass.setDepthBias(bias);
    _draw(device, pass, _whole, _green, z: greenZ);
    pass.submit();
    return _pixel(device, target, 4, 4);
  }

  final forward = await drawn(
    greenZ: 0.5 + 1e-4,
    bias: const DepthBias(constant: -4096),
  );
  require(
    _is(forward, _green),
    'a draw 1e-4 behind another, biased forward by 4096 steps, was '
    'rejected: the centre is $forward, not green. The bias was ignored, or '
    'applied with its sign flipped.',
  );
  final back = await drawn(
    greenZ: 0.5 - 1e-4,
    bias: const DepthBias(constant: 4096),
  );
  require(
    _is(back, _red),
    'a draw 1e-4 in front of another, biased back by 4096 steps, landed: '
    'the centre is $back, not red. The bias was ignored, or applied with '
    'its sign flipped.',
  );
  final none = await drawn(greenZ: 0.5 - 1e-4, bias: null);
  require(
    _is(none, _green),
    'a draw 1e-4 in front of another, with no bias in its pass, was '
    'rejected: the centre is $none. A pass starts at DepthBias.none.',
  );
}

/// A depth bias's clamp bounds it: the same forward pull as above, clamped
/// to 1e-5, no longer carries a draw 1e-4 behind.
Future<void> checkDepthBiasClampBoundsTheBias(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.depthBias,
    DeviceFeature.depthBiasClamp,
  ], 'no clamped bias is drawn');
  final target = _target(device);
  final pass = _pass(device, target, depth: _depth(device))
    ..setDepthCompare(CompareFunction.less)
    ..setDepthWrite(enabled: true);
  _draw(device, pass, _whole, _red);
  pass.setDepthBias(const DepthBias(constant: -4096, clamp: -1e-5));
  _draw(device, pass, _whole, _green, z: 0.5 + 1e-4);
  pass.submit();
  final centre = await _pixel(device, target, 4, 4);
  require(
    _is(centre, _red),
    'a forward bias of 4096 steps clamped to 1e-5 carried a draw 1e-4 '
    'behind another through: the centre is $centre, not red. The clamp was '
    'ignored.',
  );
}

/// With depth clamp on, a triangle past the far plane is kept with its depth
/// clamped; with it off, the same triangle is clipped away.
Future<void> checkDepthClampKeepsWhatClipCuts(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.depthClamp,
  ], 'nothing is clamped');
  Future<List<int>> drawn({required bool clamp}) async {
    final target = _target(device);
    final pass = _pass(device, target)..setDepthClamp(enabled: clamp);
    _draw(device, pass, _whole, _green, z: 1.5);
    pass.submit();
    return _pixel(device, target, 4, 4);
  }

  final clamped = await drawn(clamp: true);
  require(
    _is(clamped, _green),
    'a triangle at depth 1.5 with depth clamp on came back $clamped: it was '
    'clipped at the far plane rather than clamped to it',
  );
  final clipped = await drawn(clamp: false);
  require(
    _is(clipped, _clear),
    'a triangle at depth 1.5 with depth clamp off came back $clipped: it '
    'was drawn rather than clipped at the far plane, so the clamp is on by '
    'default or the depth clip is missing',
  );
}

/// The colour write mask keeps the channels it leaves out, and a pass starts
/// writing every channel.
Future<void> checkColorWriteMaskKeepsChannels(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.colorWriteMask,
  ], 'no channel is masked');
  final masked = _target(device);
  final pass = _pass(device, masked)
    ..setColorWriteMask(ColorWriteMask.red | ColorWriteMask.alpha);
  _draw(device, pass, _whole, const <double>[1, 1, 1, 1]);
  pass.submit();
  final red = await _pixel(device, masked, 4, 4);
  require(
    red[0] > 250 && red[1] < 4 && red[2] < 4 && red[3] > 250,
    'white drawn through a red-and-alpha mask came back $red, not '
    '(255, 0, 0, 255): the mask was ignored or applied to the wrong '
    'channels',
  );
  final fresh = _target(device);
  final next = _pass(device, fresh);
  _draw(device, next, _whole, const <double>[1, 1, 1, 1]);
  next.submit();
  final white = await _pixel(device, fresh, 4, 4);
  require(
    white.every((int c) => c > 250),
    'white drawn in a pass after a masked one came back $white: the mask '
    'followed into the next pass, which starts at ColorWriteMask.all',
  );
}

/// `BlendOperation.max` and `.min` take the larger and the smaller of source
/// and destination, channel by channel.
Future<void> checkMinMaxBlendPicksAChannel(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.minMaxBlend,
  ], 'no min or max blend is drawn');
  Future<List<int>> blended(BlendOperation operation) async {
    final target = _target(device);
    final pass =
        _pass(device, target, clear: const ClearColor(0.5, 0.5, 0.5, 1.0))
          ..setBlend(
            BlendState(
              colorOperation: operation,
              sourceColorFactor: BlendFactor.one,
              destinationColorFactor: BlendFactor.one,
              alphaOperation: operation,
              sourceAlphaFactor: BlendFactor.one,
              destinationAlphaFactor: BlendFactor.one,
            ),
          );
    _draw(device, pass, _whole, const <double>[1, 0.2, 0.6, 1]);
    pass.submit();
    return _pixel(device, target, 4, 4);
  }

  final max = await blended(BlendOperation.max);
  require(
    _is(max, const <double>[1, 0.5, 0.6]),
    '(1, 0.2, 0.6) blended by max over (0.5, 0.5, 0.5) came back $max, not '
    '(255, 128, 153)',
  );
  final min = await blended(BlendOperation.min);
  require(
    _is(min, const <double>[0.5, 0.2, 0.5]),
    '(1, 0.2, 0.6) blended by min over (0.5, 0.5, 0.5) came back $min, not '
    '(128, 51, 128)',
  );
}

/// A viewport a fifth of a pixel wide, over the centre of the first column,
/// covers that column's centre and nothing else; rounded to whole pixels it
/// would cover nothing, or a whole pixel's neighbour.
Future<void> checkFractionalViewportIsNotRounded(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.fractionalViewport,
  ], 'a viewport is whole pixels');
  final target = _target(device);
  final pass = _pass(device, target)
    ..setViewport(const PassViewport(x: 0.4, width: 0.2, height: _size * 1.0));
  _draw(device, pass, _whole, _green);
  pass.submit();
  final first = await _pixel(device, target, 0, 4);
  final second = await _pixel(device, target, 1, 4);
  require(
    _is(first, _green) && _is(second, _clear),
    'a viewport from x = 0.4 to 0.6 drew the first column as $first and the '
    'second as $second: only the first column\'s centre, at 0.5, lies in it',
  );
}

/// A viewport twice the target's width, starting a target's width to its
/// left, puts the right half of clip space over the whole target.
Future<void> checkViewportBeyondTheTarget(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.viewportBeyondTarget,
  ], 'a viewport stays inside its target');
  final target = _target(device);
  final pass = _pass(device, target)
    ..setViewport(
      const PassViewport(
        x: -_size * 1.0,
        width: _size * 2.0,
        height: _size * 1.0,
      ),
    );
  // Clip x from 0 to 1 at every height: the right half of the viewport.
  _draw(device, pass, const <List<double>>[
    <double>[0, -1],
    <double>[2, -1],
    <double>[0, 3],
  ], _green);
  pass.submit();
  final left = await _pixel(device, target, 1, 4);
  final right = await _pixel(device, target, 6, 4);
  require(
    _is(left, _green) && _is(right, _green),
    'the right half of a viewport from x = -8 to 8 should cover the whole '
    '8-pixel target; it drew $left on the left and $right on the right. A '
    'viewport clamped into the target puts it in the right half only.',
  );
}

/// With a reversed depth range, two draws 1e-9 apart near zero are told
/// apart: what a float depth keeps and a 24-bit one rounds to the same step.
Future<void> checkReversedDepthKeepsPrecision(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.reversedDepth,
  ], 'its depth near zero is not promised to be a float');
  final target = _target(device);
  final pass = _pass(device, target, depth: _depth(device), depthClear: 0)
    ..setDepthCompare(CompareFunction.greater)
    ..setDepthWrite(enabled: true);
  _draw(device, pass, _whole, _red, z: 2e-9);
  _draw(device, pass, _whole, _green, z: 1e-9);
  pass.submit();
  final centre = await _pixel(device, target, 4, 4);
  require(
    _is(centre, _red),
    'red at depth 2e-9 then green at 1e-9, compared `greater` over a depth '
    'cleared to 0, came back $centre, not red: the depth buffer rounded '
    'both to the same step, which a reversed range is promised not to do',
  );
}

// ---------------------------------------------------------------- draws

/// `drawNonIndexed` draws the vertices in order and ignores the bound index
/// buffer, which here names the other triangle.
Future<void> checkNonIndexedDrawIgnoresIndices(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.nonIndexedDraw,
  ], 'no draw goes without indices');
  final target = _target(device);
  final pass = _pass(device, target);
  final (vertex, _) = _stages(device);
  pass
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(ByteData.sublistView(_halves()), 6)
    ..bindIndexData(
      ByteData.sublistView(Uint16List.fromList(<int>[3, 4, 5])),
      IndexType.int16,
      3,
    )
    ..drawNonIndexed(vertexCount: 3)
    ..submit();
  await _requireHalves(
    device,
    target,
    left: _red,
    right: _clear,
    what: 'the first three vertices drawn without indices',
  );
}

/// A base vertex shifts every index, and a first instance other than zero
/// still draws.
Future<void> checkBaseVertexAndFirstInstanceDraw(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.baseVertexBaseInstance,
  ], 'every index is read as written');
  final target = _target(device);
  final pass = _pass(device, target);
  final (vertex, _) = _stages(device);
  pass
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(ByteData.sublistView(_halves()), 6)
    ..bindIndexData(
      ByteData.sublistView(Uint16List.fromList(<int>[0, 1, 2])),
      IndexType.int16,
      3,
    )
    ..drawIndexed(const IndexedDraw(indexCount: 3, baseVertex: 3))
    ..submit();
  await _requireHalves(
    device,
    target,
    left: _clear,
    right: _green,
    what: 'indices 0, 1, 2 with a base vertex of 3',
  );
  final second = _target(device);
  final again = _pass(device, second);
  _bind(device, again, _halves());
  again
    ..drawIndexed(const IndexedDraw(indexCount: 3, firstInstance: 2))
    ..submit();
  await _requireHalves(
    device,
    second,
    left: _red,
    right: _clear,
    what: 'the first triangle with a first instance of 2',
  );
}

/// `multiDraw` draws every window it is handed, and only those.
Future<void> checkMultiDrawDrawsEachWindow(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.multiDraw,
  ], 'no draws are batched');
  final both = _target(device);
  final pass = _pass(device, both);
  _bind(device, pass, _halves());
  pass
    ..multiDraw(const <IndexedDraw>[
      IndexedDraw(indexCount: 3),
      IndexedDraw(firstIndex: 3, indexCount: 3),
    ])
    ..submit();
  await _requireHalves(
    device,
    both,
    left: _red,
    right: _green,
    what: 'two windows in one multiDraw',
  );
  final one = _target(device);
  final second = _pass(device, one);
  _bind(device, second, _halves());
  second
    ..multiDraw(const <IndexedDraw>[IndexedDraw(firstIndex: 3, indexCount: 3)])
    ..submit();
  await _requireHalves(
    device,
    one,
    left: _clear,
    right: _green,
    what: 'the second window alone in a multiDraw',
  );
}

StorageBuffer _arguments(GraphicsDevice device, List<ByteData> draws) {
  final bytes = Uint8List(draws.length * 20);
  for (var i = 0; i < draws.length; i++) {
    bytes.setAll(i * 20, Uint8List.sublistView(draws[i]));
  }
  return device.createBuffer(
    BufferDescriptor(lengthInBytes: bytes.length, usage: BufferUsage.indirect),
    contents: ByteData.sublistView(bytes),
  );
}

/// `drawIndirect` draws the window its arguments name.
Future<void> checkIndirectDrawReadsItsArguments(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.indirectDraw,
    DeviceFeature.buffers,
  ], 'no draw reads its counts from a buffer');
  final target = _target(device);
  final pass = _pass(device, target);
  _bind(device, pass, _halves());
  pass
    ..drawIndirect(
      _arguments(device, <ByteData>[
        drawIndexedIndirectArguments(indexCount: 3, firstIndex: 3),
      ]),
    )
    ..submit();
  await _requireHalves(
    device,
    target,
    left: _clear,
    right: _green,
    what: 'an indirect draw of the second window',
  );
}

/// `multiDrawIndirect` draws every record, or as many as the count buffer
/// says.
Future<void> checkMultiDrawIndirectCounts(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.multiDrawIndirect,
    DeviceFeature.buffers,
  ], 'no batch of draws is read from a buffer');
  final records = <ByteData>[
    drawIndexedIndirectArguments(indexCount: 3),
    drawIndexedIndirectArguments(indexCount: 3, firstIndex: 3),
  ];
  final both = _target(device);
  final pass = _pass(device, both);
  _bind(device, pass, _halves());
  pass
    ..multiDrawIndirect(_arguments(device, records), 2)
    ..submit();
  await _requireHalves(
    device,
    both,
    left: _red,
    right: _green,
    what: 'two indirect records',
  );
  final counted = _target(device);
  final second = _pass(device, counted);
  _bind(device, second, _halves());
  second
    ..multiDrawIndirect(
      _arguments(device, records),
      2,
      countBuffer: device.createBuffer(
        const BufferDescriptor(lengthInBytes: 4, usage: BufferUsage.indirect),
        contents: ByteData(4)..setUint32(0, 1, Endian.little),
      ),
    )
    ..submit();
  await _requireHalves(
    device,
    counted,
    left: _red,
    right: _clear,
    what: 'two indirect records with a count buffer holding 1',
  );
}

/// An indirect draw whose arguments name a first instance draws every
/// instance from it: two instances of a quarter-bright red, added, are half.
Future<void> checkIndirectFirstInstanceDraws(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.indirectDraw,
    DeviceFeature.indirectFirstInstance,
    DeviceFeature.buffers,
  ], 'no indirect draw may name a first instance');
  final target = _target(device);
  final pass = _pass(device, target)..setBlend(BlendState.additive);
  _bind(device, pass, _vertices(_whole, const <double>[0.25, 0, 0, 1]));
  pass
    ..drawIndirect(
      _arguments(device, <ByteData>[
        drawIndexedIndirectArguments(
          indexCount: 3,
          instanceCount: 2,
          firstInstance: 1,
        ),
      ]),
    )
    ..submit();
  final centre = await _pixel(device, target, 4, 4);
  require(
    (centre[0] - 128).abs() <= 6,
    'two instances from instance 1 of a quarter-bright red, added, came back '
    '$centre: red should be 128. A draw naming a first instance was skipped '
    'or drawn once.',
  );
}

/// A bundle draws what it recorded, each time it is replayed.
Future<void> checkRenderBundleReplays(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.renderBundles,
  ], 'nothing is recorded to replay');
  final (vertex, fragment) = _stages(device);
  final recorder =
      device.createRenderBundleEncoder(
          const RenderBundleDescriptor(
            colorFormats: <TextureFormat>[TextureFormat.r8g8b8a8UNormInt],
          ),
        )
        ..setPrimitiveType(PrimitiveType.triangle)
        ..setCullMode(CullMode.none)
        ..bindPipeline(
          device.createPipelineFrom(
            PipelineDescriptor(vertex: vertex, fragment: fragment),
          ),
        );
  _bind(device, recorder, _vertices(_right, _green));
  recorder.draw();
  final bundle = recorder.finish(label: 'the right half');
  for (final round in <String>['first', 'second']) {
    final target = _target(device);
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(texture: target, clearValue: ClearColor.transparentBlack),
        ],
      ),
    )..executeBundles(<RenderBundle>[bundle]);
    pass.submit();
    await _requireHalves(
      device,
      target,
      left: _clear,
      right: _green,
      what: 'the $round replay of a bundle that draws the right half',
    );
  }
}

/// A 32-bit index above 65535 reaches the vertex it names, not the one its
/// low sixteen bits name.
Future<void> checkUint32IndicesReachFar(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.indexUint32,
  ], 'no index is wider than 16 bits');
  const far = 65536;
  final vertices = Float32List((far + 3) * 7)
    ..setAll(0, _vertices(_left, _red))
    ..setAll(far * 7, _vertices(_right, _green));
  final target = _target(device);
  final (vertex, _) = _stages(device);
  _pass(device, target)
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(ByteData.sublistView(vertices), far + 3)
    ..bindIndexData(
      ByteData.sublistView(Uint32List.fromList(<int>[far, far + 1, far + 2])),
      IndexType.int32,
      3,
    )
    ..draw()
    ..submit();
  await _requireHalves(
    device,
    target,
    left: _clear,
    right: _green,
    what: 'indices 65536 to 65538 as 32 bits',
  );
}

// ------------------------------------------------------------- uniforms

/// A matrix that squeezes clip x from `[-1, 1]` into `[0, 1]`: a triangle
/// over the whole target lands in the right half only.
ByteData _squeezeRight() => ByteData.sublistView(
  Float32List.fromList(
    (Matrix4.identity()
          ..setEntry(0, 0, 0.5)
          ..setEntry(0, 3, 0.5))
        .storage,
  ),
);

Future<void> _requireSqueezed(
  GraphicsDevice device,
  void Function(PassEncoder pass, ShaderHandle vertex) bindMatrix,
  String how,
) async {
  final target = _target(device);
  final (vertex, _) = _stages(device);
  final pass = _pass(device, target);
  final vertices = _vertices(_whole, _green);
  bindMatrix(pass, vertex);
  pass
    ..bindVertexData(ByteData.sublistView(vertices), 3)
    ..bindIndexData(
      ByteData.sublistView(Uint16List.fromList(<int>[0, 1, 2])),
      IndexType.int16,
      3,
    )
    ..draw()
    ..submit();
  await _requireHalves(
    device,
    target,
    left: _clear,
    right: _green,
    what: 'a triangle over the target, its matrix $how, squeezed right',
  );
}

/// Laid-out bytes reach the block they are bound to.
Future<void> checkUniformBytesReachTheStage(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.uniformBytes,
  ], 'no block is filled from bytes');
  await _requireSqueezed(device, (PassEncoder pass, ShaderHandle vertex) {
    require(
      pass.bindUniformBytes(vertex, 'LineInfo', _squeezeRight()),
      'bindUniformBytes answered false for LineInfo, which the stage has',
    );
  }, 'bound from bytes');
}

/// A uniform buffer's range reaches the block it is bound to.
Future<void> checkUniformBufferReachesTheStage(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.uniformBuffers,
    DeviceFeature.buffers,
  ], 'no block is bound from a buffer');
  final buffer = device.createBuffer(
    const BufferDescriptor(lengthInBytes: 64, usage: BufferUsage.uniform),
    contents: _squeezeRight(),
  );
  await _requireSqueezed(device, (PassEncoder pass, ShaderHandle vertex) {
    require(
      pass.bindUniformBuffer(vertex, 'LineInfo', buffer, 0, 64),
      'bindUniformBuffer answered false for LineInfo, which the stage has',
    );
  }, 'bound from a buffer');
}

// --------------------------------------------------------------- queries

/// An occlusion query counts nothing around no draw, something around a
/// draw that lands, and nothing around a draw the depth test rejects.
Future<void> checkOcclusionQueryCountsSamples(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.occlusionQuery,
  ], 'no samples are counted');
  final set = device.createQuerySet(QueryType.occlusion, 3);
  final target = _target(device);
  final pass = _pass(
    device,
    target,
    depth: _depth(device),
    reshape: (RenderPassDescriptor plain) => RenderPassDescriptor(
      colors: plain.colors,
      depth: plain.depth,
      occlusionQuerySet: set,
    ),
  )..setDepthCompare(CompareFunction.always);
  pass
    ..beginOcclusionQuery(0)
    ..endOcclusionQuery()
    ..beginOcclusionQuery(1);
  _draw(device, pass, _whole, _green);
  pass
    ..endOcclusionQuery()
    ..setDepthCompare(CompareFunction.never)
    ..beginOcclusionQuery(2);
  _draw(device, pass, _whole, _red);
  pass
    ..endOcclusionQuery()
    ..submit();
  final results = await device.readQueryResults(set);
  device.releaseQuerySet(set);
  require(
    results.length == 3 && results[0] == 0 && results[1] > 0 && results[2] == 0,
    'occlusion queries around no draw, a draw that lands and a draw the '
    'depth test rejects answered $results, not [0, more than 0, 0]',
  );
}

/// A pass's two timestamps are a time each, the end not before the start.
Future<void> checkTimestampsAdvance(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.timestampQuery,
  ], 'no time is written');
  final set = device.createQuerySet(QueryType.timestamp, 2);
  final target = _target(device);
  final pass = _pass(
    device,
    target,
    reshape: (RenderPassDescriptor plain) => RenderPassDescriptor(
      colors: plain.colors,
      timestampWrites: PassTimestampWrites(
        querySet: set,
        beginningOfPassIndex: 0,
        endOfPassIndex: 1,
      ),
    ),
  );
  _draw(device, pass, _whole, _green);
  pass.submit();
  final results = await device.readQueryResults(set);
  device.releaseQuerySet(set);
  require(
    results.length == 2 && results[1] >= results[0] && results[1] > 0,
    'a pass\'s beginning and end timestamps answered $results: two times, '
    'the end not before the beginning, were expected',
  );
  require(
    _is(await _pixel(device, target, 4, 4), _green),
    'a pass with timestamp writes did not draw',
  );
}

/// A pipeline statistics query around one triangle counts its three
/// vertices, its primitive, its fragments, and no compute.
Future<void> checkPipelineStatisticsCount(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.pipelineStatisticsQuery,
  ], 'nothing is counted');
  final set = device.createQuerySet(QueryType.pipelineStatistics, 1);
  final target = _target(device);
  final pass = _pass(device, target)..beginPipelineStatisticsQuery(set, 0);
  _draw(device, pass, _whole, _green);
  pass
    ..endPipelineStatisticsQuery()
    ..submit();
  final results = await device.readQueryResults(set);
  device.releaseQuerySet(set);
  final counted = <PipelineStatistic, int>{
    for (var i = 0; i < PipelineStatistic.values.length; i++)
      PipelineStatistic.values[i]: i < results.length ? results[i] : -1,
  };
  require(
    results.length == PipelineStatistic.values.length &&
        counted[PipelineStatistic.vertexShaderInvocations]! >= 3 &&
        counted[PipelineStatistic.clipperPrimitivesOut]! >= 1 &&
        counted[PipelineStatistic.fragmentShaderInvocations]! > 0 &&
        counted[PipelineStatistic.computeShaderInvocations] == 0,
    'a pipeline statistics query around one triangle over the target '
    'counted $counted: at least three vertices, a primitive out of the '
    'clipper, some fragments and no compute were expected',
  );
}

/// The checks above, each declining on a device without its feature.
List<ConformanceCheck> get drawOutputChecks => <ConformanceCheck>[
  ConformanceCheck(
    name: 'a depth bias moves the depth the way its sign says',
    run: checkDepthBiasMovesTheDepth,
  ),
  ConformanceCheck(
    name: 'a depth bias clamp bounds the bias',
    run: checkDepthBiasClampBoundsTheBias,
  ),
  ConformanceCheck(
    name: 'depth clamp keeps what the depth clip cuts',
    run: checkDepthClampKeepsWhatClipCuts,
  ),
  ConformanceCheck(
    name: 'a colour write mask keeps the channels it leaves out',
    run: checkColorWriteMaskKeepsChannels,
  ),
  ConformanceCheck(
    name: 'min and max blending pick a channel each',
    run: checkMinMaxBlendPicksAChannel,
  ),
  ConformanceCheck(
    name: 'a fractional viewport is not rounded',
    run: checkFractionalViewportIsNotRounded,
  ),
  ConformanceCheck(
    name: 'a viewport past the target draws its window of the frame',
    run: checkViewportBeyondTheTarget,
  ),
  ConformanceCheck(
    name: 'a reversed depth range keeps its precision near zero',
    run: checkReversedDepthKeepsPrecision,
  ),
  ConformanceCheck(
    name: 'a non-indexed draw ignores the bound indices',
    run: checkNonIndexedDrawIgnoresIndices,
  ),
  ConformanceCheck(
    name: 'a base vertex shifts the indices and a first instance draws',
    run: checkBaseVertexAndFirstInstanceDraw,
  ),
  ConformanceCheck(
    name: 'a multi-draw draws each window it is handed',
    run: checkMultiDrawDrawsEachWindow,
  ),
  ConformanceCheck(
    name: 'an indirect draw reads its arguments',
    run: checkIndirectDrawReadsItsArguments,
  ),
  ConformanceCheck(
    name: 'a multi-draw-indirect draws its records or its count',
    run: checkMultiDrawIndirectCounts,
  ),
  ConformanceCheck(
    name: 'an indirect draw from a first instance draws every instance',
    run: checkIndirectFirstInstanceDraws,
  ),
  ConformanceCheck(
    name: 'a render bundle draws what it recorded at every replay',
    run: checkRenderBundleReplays,
  ),
  ConformanceCheck(
    name: 'a 32-bit index reaches past 65535',
    run: checkUint32IndicesReachFar,
  ),
  ConformanceCheck(
    name: 'uniform bytes reach the block they are bound to',
    run: checkUniformBytesReachTheStage,
  ),
  ConformanceCheck(
    name: 'a uniform buffer reaches the block it is bound to',
    run: checkUniformBufferReachesTheStage,
  ),
  ConformanceCheck(
    name: 'an occlusion query counts the samples that land',
    run: checkOcclusionQueryCountsSamples,
  ),
  ConformanceCheck(
    name: 'a pass\'s timestamps advance',
    run: checkTimestampsAdvance,
  ),
  ConformanceCheck(
    name: 'a pipeline statistics query counts one triangle',
    run: checkPipelineStatisticsCount,
  ),
];
