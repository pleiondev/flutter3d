// Every kind of trace event survives the file — `H3`.
//
// One of each, written and read back, and written again: the second file has
// to be the first byte for byte. That catches the two ways a codec of this
// shape goes wrong without a picture to show it — a field written and not
// read, which reads back as a default, and a kind written under one name and
// decoded under another, which throws on the first trace that has it.

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

ByteData _bytes(List<int> values) =>
    ByteData.sublistView(Uint8List.fromList(values));

const ScreenRect _rect = ScreenRect(x: 1, y: 2, width: 30, height: 40);
const TraceGeometryRange _range = (buffer: 0, offset: 16, length: 48);

/// One of every event, with every optional field filled, so nothing a
/// decoder forgets can hide behind a default.
List<TraceEvent> _everyEvent() => <TraceEvent>[
  const TraceBeginFrame(),
  TraceUploadGeometry(
    id: 0,
    usage: GeometryUsage.vertices,
    bytes: _bytes(<int>[1, 2, 3, 4]),
  ),
  TraceOverwriteGeometry(target: _range, offset: 4, bytes: _bytes(<int>[9, 9])),
  const TraceReleaseGeometry(0),
  const TraceCreateTexture(
    id: 1,
    spec: RenderTargetSpec(
      width: 8,
      height: 4,
      format: TextureFormat.r16g16b16a16Float,
      sampleCount: 4,
      storageMode: StorageMode.deviceTransient,
    ),
  ),
  TraceCreateTextureFromPixels(
    id: 2,
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: _bytes(<int>[255, 0, 0, 255]),
    mipLevels: <ByteData>[
      _bytes(<int>[1, 1, 1, 1]),
    ],
  ),
  TraceCreateCubeTextureFromPixels(
    id: 3,
    size: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    faces: <ByteData>[
      for (var f = 0; f < 6; f++) _bytes(<int>[f, f, f, 255]),
    ],
    mipLevels: <List<ByteData>>[
      <ByteData>[
        _bytes(<int>[7]),
      ],
    ],
  ),
  const TraceCreateCubeRenderTarget(
    id: 4,
    size: 16,
    format: TextureFormat.r16g16b16a16Float,
    mipLevels: 3,
  ),
  TraceOverwriteTexture(
    texture: 2,
    rgba: _bytes(<int>[0, 0, 0, 0]),
    region: _rect,
    mipLevel: 1,
  ),
  const TraceReleaseTexture(4),
  TraceLoadShaders(_bytes(<int>[5, 6])),
  const TraceCreatePipeline(
    id: 5,
    vertex: 'MeshVertex',
    fragment: 'Pbr',
    layout: VertexLayoutSpec(<BufferLayout>[
      BufferLayout(
        strideInBytes: 12,
        stepMode: VertexStepMode.instance,
        attributes: <InputAttribute>[
          InputAttribute(
            name: 'position',
            format: VertexFormat.float32x3,
            offsetInBytes: 0,
          ),
        ],
      ),
    ]),
  ),
  TraceBeginRenderPass(
    pass: 0,
    label: 'scene',
    colors: <TraceColorTarget>[
      (
        texture: 1,
        resolveTexture: 2,
        loadAction: LoadAction.load,
        storeAction: StoreAction.multisampleResolve,
        clearValue: Vector4(0.1, 0.2, 0.3, 1.0),
        face: 2,
        mipLevel: 1,
      ),
    ],
    depth: (
      texture: 1,
      clearValue: 0.5,
      loadAction: LoadAction.load,
      storeAction: StoreAction.store,
      stencilLoadAction: LoadAction.load,
      stencilStoreAction: StoreAction.store,
      stencilClearValue: 7,
    ),
  ),
  const TraceSetViewport(0, _rect),
  const TraceSetScissor(0, _rect),
  const TraceSetPrimitiveType(0, PrimitiveType.lineStrip),
  const TraceSetPolygonMode(0, PolygonMode.line),
  const TraceSetCullMode(0, CullMode.frontFace),
  const TraceSetWindingOrder(0, WindingOrder.clockwise),
  const TraceSetDepthWrite(0, false),
  const TraceSetDepthCompare(0, CompareFunction.greaterEqual),
  const TraceSetStencil(
    0,
    StencilState(
      compare: CompareFunction.notEqual,
      passOp: StencilOperation.setToReferenceValue,
      readMask: 3,
      writeMask: 5,
    ),
    StencilState(depthFailOp: StencilOperation.invert),
  ),
  const TraceSetStencilReference(0, 9),
  const TraceSetBlend(
    0,
    BlendState(
      colorOperation: BlendOperation.subtract,
      sourceColorFactor: BlendFactor.sourceAlpha,
      destinationColorFactor: BlendFactor.oneMinusSourceAlpha,
    ),
    1,
  ),
  TraceSetBlendColor(0, Vector4(1.0, 0.5, 0.25, 0.125)),
  const TraceBindPipeline(0, 5),
  const TraceBindVertexBuffer(pass: 0, buffer: _range, vertexCount: 3, slot: 1),
  TraceBindVertexData(
    pass: 0,
    bytes: _bytes(<int>[1, 2]),
    vertexCount: 1,
    slot: 1,
  ),
  const TraceBindIndexBuffer(
    pass: 0,
    buffer: _range,
    type: IndexType.int16,
    indexCount: 6,
  ),
  TraceBindIndexData(
    pass: 0,
    bytes: _bytes(<int>[0, 0, 1, 0]),
    type: IndexType.int16,
    indexCount: 2,
  ),
  TraceBindUniformBlock(
    pass: 0,
    shader: 'Pbr',
    block: 'FragInfo',
    members: <String, Float32List>{
      'base_color': Float32List.fromList(<double>[0.5, 0.25, 0.125, 1.0]),
    },
  ),
  const TraceBindTexture(
    pass: 0,
    shader: 'Pbr',
    slot: 'base_color_texture',
    texture: 2,
    sampler: SamplerOptions.nearestClamp,
  ),
  const TraceClearBindings(0),
  const TraceDraw(0, 4),
  const TraceSubmit(0),
  const TraceReadPixels(1),
  const TraceReadback(texture: 1, region: _rect),
  TraceCreateStorageBuffer(
    id: 6,
    bytes: _bytes(<int>[1, 2, 3, 4]),
    hostReadable: true,
  ),
  const TraceCreateComputePipeline(7, 'PrefixSum'),
  const TraceBeginComputePass(1, 'sum'),
  const TraceComputeBindPipeline(1, 7),
  const TraceComputeBindStorageBuffer(
    pass: 1,
    shader: 'PrefixSum',
    name: 'values',
    buffer: 6,
  ),
  TraceComputeBindUniformBlock(
    pass: 1,
    shader: 'PrefixSum',
    block: 'SumInfo',
    members: <String, Float32List>{
      'count': Float32List.fromList(<double>[1024.0]),
    },
  ),
  const TraceDispatch(1, 4, 2, 1),
  const TraceComputeSubmit(1),
  const TraceReadBuffer(6),
  const TraceReleaseStorageBuffer(6),
];

void main() {
  test('every kind of event is here once', () {
    // A kind added to the hierarchy and not to this list would be a kind the
    // round trip below never tries.
    final kinds = _everyEvent().map((e) => e.kind).toList();
    expect(kinds.toSet(), hasLength(kinds.length));
    expect(kinds, hasLength(47));
  });

  test('a file read back writes the same file', () {
    final first = Trace(
      _everyEvent(),
      metadata: <String, Object?>{'backend': 'test'},
    ).encode();
    final read = Trace.decode(first);
    expect(read.metadata, <String, Object?>{'backend': 'test'});
    expect(read.events.map((e) => e.kind), _everyEvent().map((e) => e.kind));
    expect(Trace(read.events, metadata: read.metadata).encode(), first);
  });

  test('a trace from another format version is refused by name', () {
    final bytes = Trace(const <TraceEvent>[]).encode();
    ByteData.sublistView(bytes).setUint32(8, 99, Endian.little);
    expect(
      () => Trace.decode(bytes),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('format 99'),
        ),
      ),
    );
  });
}
