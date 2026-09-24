/// One call a device or an encoder received, as a value — `H3`.
///
/// **Its own hierarchy, not `Recorded`'s.** `Recorded` is what a test asserts
/// against, and it is lossy on purpose: a vertex binding says how many
/// vertices, not which buffer. A trace has to be replayed, so every event here
/// carries everything its call took, with resources named by the order they
/// were created in rather than by handles that die with the process.
///
/// Sealed, and complete for the whole contract in 0.8.0 — compute included,
/// though no backend runs it yet — because a variant added in a patch would
/// break every exhaustive switch over it, the replay's among them.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' show Vector4;

import '../formats.dart';
import '../geometry_buffer.dart';
import '../render_pass_descriptor.dart';
import '../render_target_pool.dart';
import '../sampler.dart';
import '../vertex_layout_spec.dart';
import 'trace_values.dart';

/// A slice of a geometry buffer: which buffer, and which bytes of it.
typedef TraceGeometryRange = ({int buffer, int offset, int length});

/// One colour attachment, with its textures named by id.
typedef TraceColorTarget = ({
  int texture,
  int? resolveTexture,
  LoadAction loadAction,
  StoreAction storeAction,
  Vector4? clearValue,
  int face,
  int mipLevel,
});

/// The depth attachment, with its texture named by id.
typedef TraceDepthTarget = ({
  int texture,
  double clearValue,
  LoadAction loadAction,
  StoreAction storeAction,
  LoadAction stencilLoadAction,
  StoreAction stencilStoreAction,
  int stencilClearValue,
});

sealed class TraceEvent {
  const TraceEvent();

  /// The event's name in a trace file.
  String get kind;

  Map<String, Object?> toJson(TraceBlobWriter blob);

  static TraceEvent fromJson(
    Map<String, Object?> j,
    TraceBlobReader blob,
  ) => switch (j['kind']) {
    'beginFrame' => const TraceBeginFrame(),
    'uploadGeometry' => TraceUploadGeometry(
      id: asInt(j['id']),
      usage: usageFromJson(j['usage']),
      bytes: blob.read(j['bytes']),
    ),
    'overwriteGeometry' => TraceOverwriteGeometry(
      target: _range(j['target']),
      offset: asInt(j['offset']),
      bytes: blob.read(j['bytes']),
    ),
    'releaseGeometry' => TraceReleaseGeometry(asInt(j['buffer'])),
    'createTexture' => TraceCreateTexture(
      id: asInt(j['id']),
      spec: specFromJson(j['spec']),
    ),
    'createTextureFromPixels' => TraceCreateTextureFromPixels(
      id: asInt(j['id']),
      width: asInt(j['width']),
      height: asInt(j['height']),
      format: byName(TextureFormat.values, j['format']),
      pixels: blob.read(j['pixels']),
      mipLevels: (j['mipLevels'] as List<Object?>?)?.map(blob.read).toList(),
    ),
    'createCubeTextureFromPixels' => TraceCreateCubeTextureFromPixels(
      id: asInt(j['id']),
      size: asInt(j['size']),
      format: byName(TextureFormat.values, j['format']),
      faces: (j['faces']! as List<Object?>).map(blob.read).toList(),
      mipLevels: (j['mipLevels'] as List<Object?>?)
          ?.map((f) => (f! as List<Object?>).map(blob.read).toList())
          .toList(),
    ),
    'createCubeRenderTarget' => TraceCreateCubeRenderTarget(
      id: asInt(j['id']),
      size: asInt(j['size']),
      format: byName(TextureFormat.values, j['format']),
      mipLevels: asInt(j['mipLevels']),
    ),
    'overwriteTexture' => TraceOverwriteTexture(
      texture: asInt(j['texture']),
      rgba: blob.read(j['rgba']),
      region: j['region'] == null ? null : screenRectFromJson(j['region']),
      mipLevel: asInt(j['mipLevel']),
    ),
    'releaseTexture' => TraceReleaseTexture(asInt(j['texture'])),
    'loadShaders' => TraceLoadShaders(blob.read(j['bytes'])),
    'createPipeline' => TraceCreatePipeline(
      id: asInt(j['id']),
      vertex: j['vertex']! as String,
      fragment: j['fragment']! as String,
      layout: j['layout'] == null ? null : layoutFromJson(j['layout']),
    ),
    'beginRenderPass' => TraceBeginRenderPass(
      pass: asInt(j['pass']),
      label: j['label'] as String?,
      colors: <TraceColorTarget>[
        for (final c in (j['colors']! as List<Object?>).map(asMap))
          (
            texture: asInt(c['texture']),
            resolveTexture: c['resolveTexture'] == null
                ? null
                : asInt(c['resolveTexture']),
            loadAction: byName(LoadAction.values, c['loadAction']),
            storeAction: byName(StoreAction.values, c['storeAction']),
            clearValue: c['clearValue'] == null
                ? null
                : vector4FromJson(c['clearValue']),
            face: asInt(c['face']),
            mipLevel: asInt(c['mipLevel']),
          ),
      ],
      depth: switch (j['depth']) {
        null => null,
        final Object d => (
          texture: asInt(asMap(d)['texture']),
          clearValue: asDouble(asMap(d)['clearValue']),
          // Absent from a trace written before `R8` let a pass load depth,
          // and absent means what every pass did then.
          loadAction: asMap(d)['loadAction'] == null
              ? LoadAction.clear
              : byName(LoadAction.values, asMap(d)['loadAction']),
          storeAction: asMap(d)['storeAction'] == null
              ? StoreAction.dontCare
              : byName(StoreAction.values, asMap(d)['storeAction']),
          stencilLoadAction: byName(
            LoadAction.values,
            asMap(d)['stencilLoadAction'],
          ),
          stencilStoreAction: byName(
            StoreAction.values,
            asMap(d)['stencilStoreAction'],
          ),
          stencilClearValue: asInt(asMap(d)['stencilClearValue']),
        ),
      },
    ),
    'readPixels' => TraceReadPixels(asInt(j['texture'])),
    'readback' => TraceReadback(
      texture: asInt(j['texture']),
      region: j['region'] == null ? null : screenRectFromJson(j['region']),
    ),
    'setViewport' => TraceSetViewport(
      asInt(j['pass']),
      screenRectFromJson(j['rect']),
    ),
    'setScissor' => TraceSetScissor(
      asInt(j['pass']),
      screenRectFromJson(j['rect']),
    ),
    'setPrimitiveType' => TraceSetPrimitiveType(
      asInt(j['pass']),
      byName(PrimitiveType.values, j['value']),
    ),
    'setPolygonMode' => TraceSetPolygonMode(
      asInt(j['pass']),
      byName(PolygonMode.values, j['value']),
    ),
    'setCullMode' => TraceSetCullMode(
      asInt(j['pass']),
      byName(CullMode.values, j['value']),
    ),
    'setWindingOrder' => TraceSetWindingOrder(
      asInt(j['pass']),
      byName(WindingOrder.values, j['value']),
    ),
    'setDepthWrite' => TraceSetDepthWrite(
      asInt(j['pass']),
      j['value']! as bool,
    ),
    'setDepthCompare' => TraceSetDepthCompare(
      asInt(j['pass']),
      byName(CompareFunction.values, j['value']),
    ),
    'setStencil' => TraceSetStencil(
      asInt(j['pass']),
      stencilFromJson(j['front']),
      j['back'] == null ? null : stencilFromJson(j['back']),
    ),
    'setStencilReference' => TraceSetStencilReference(
      asInt(j['pass']),
      asInt(j['value']),
    ),
    'setBlend' => TraceSetBlend(
      asInt(j['pass']),
      j['state'] == null ? null : blendFromJson(j['state']),
      asInt(j['attachment']),
    ),
    'setBlendColor' => TraceSetBlendColor(
      asInt(j['pass']),
      vector4FromJson(j['color']),
    ),
    'bindPipeline' => TraceBindPipeline(asInt(j['pass']), asInt(j['pipeline'])),
    'bindVertexBuffer' => TraceBindVertexBuffer(
      pass: asInt(j['pass']),
      buffer: _range(j['buffer']),
      vertexCount: asInt(j['vertexCount']),
      slot: asInt(j['slot']),
    ),
    'bindVertexData' => TraceBindVertexData(
      pass: asInt(j['pass']),
      bytes: blob.read(j['bytes']),
      vertexCount: asInt(j['vertexCount']),
      slot: asInt(j['slot']),
    ),
    'bindIndexBuffer' => TraceBindIndexBuffer(
      pass: asInt(j['pass']),
      buffer: _range(j['buffer']),
      type: byName(IndexType.values, j['type']),
      indexCount: asInt(j['indexCount']),
    ),
    'bindIndexData' => TraceBindIndexData(
      pass: asInt(j['pass']),
      bytes: blob.read(j['bytes']),
      type: byName(IndexType.values, j['type']),
      indexCount: asInt(j['indexCount']),
    ),
    'bindUniformBlock' => TraceBindUniformBlock(
      pass: asInt(j['pass']),
      shader: j['shader']! as String,
      block: j['block']! as String,
      members: _members(j['members'], blob),
    ),
    'bindTexture' => TraceBindTexture(
      pass: asInt(j['pass']),
      shader: j['shader']! as String,
      slot: j['slot']! as String,
      texture: asInt(j['texture']),
      sampler: j['sampler'] == null ? null : samplerFromJson(j['sampler']),
    ),
    'clearBindings' => TraceClearBindings(asInt(j['pass'])),
    'draw' => TraceDraw(asInt(j['pass']), asInt(j['instanceCount'])),
    'submit' => TraceSubmit(asInt(j['pass'])),
    'createStorageBuffer' => TraceCreateStorageBuffer(
      id: asInt(j['id']),
      bytes: blob.read(j['bytes']),
      hostReadable: j['hostReadable']! as bool,
    ),
    'releaseStorageBuffer' => TraceReleaseStorageBuffer(asInt(j['buffer'])),
    'createComputePipeline' => TraceCreateComputePipeline(
      asInt(j['id']),
      j['shader']! as String,
    ),
    'beginComputePass' => TraceBeginComputePass(
      asInt(j['pass']),
      j['label'] as String?,
    ),
    'computeBindPipeline' => TraceComputeBindPipeline(
      asInt(j['pass']),
      asInt(j['pipeline']),
    ),
    'computeBindStorageBuffer' => TraceComputeBindStorageBuffer(
      pass: asInt(j['pass']),
      shader: j['shader']! as String,
      name: j['name']! as String,
      buffer: asInt(j['buffer']),
    ),
    'computeBindUniformBlock' => TraceComputeBindUniformBlock(
      pass: asInt(j['pass']),
      shader: j['shader']! as String,
      block: j['block']! as String,
      members: _members(j['members'], blob),
    ),
    'dispatch' => TraceDispatch(
      asInt(j['pass']),
      asInt(j['x']),
      asInt(j['y']),
      asInt(j['z']),
    ),
    'computeSubmit' => TraceComputeSubmit(asInt(j['pass'])),
    'readBuffer' => TraceReadBuffer(asInt(j['buffer'])),
    final other => throw FormatException(
      'a trace event of kind $other, which this build does not know',
    ),
  };
}

TraceGeometryRange _range(Object? json) {
  final m = asMap(json);
  return (
    buffer: asInt(m['buffer']),
    offset: asInt(m['offset']),
    length: asInt(m['length']),
  );
}

Map<String, Object?> _rangeToJson(TraceGeometryRange r) => <String, Object?>{
  'buffer': r.buffer,
  'offset': r.offset,
  'length': r.length,
};

Map<String, Float32List> _members(Object? json, TraceBlobReader blob) =>
    <String, Float32List>{
      for (final MapEntry(:key, :value) in asMap(json).entries)
        key: Float32List.sublistView(blob.read(value)),
    };

Map<String, Object?> _membersToJson(
  Map<String, Float32List> members,
  TraceBlobWriter blob,
) => <String, Object?>{
  for (final MapEntry(:key, :value) in members.entries)
    key: blob.add(ByteData.sublistView(value)),
};

// ---------------------------------------------------------------- device

final class TraceBeginFrame extends TraceEvent {
  const TraceBeginFrame();
  @override
  String get kind => 'beginFrame';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{};
}

final class TraceUploadGeometry extends TraceEvent {
  const TraceUploadGeometry({
    required this.id,
    required this.usage,
    required this.bytes,
  });
  final int id;
  final GeometryUsage usage;
  final ByteData bytes;
  @override
  String get kind => 'uploadGeometry';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'usage': usage.name,
    'bytes': blob.add(bytes),
  };
}

final class TraceOverwriteGeometry extends TraceEvent {
  const TraceOverwriteGeometry({
    required this.target,
    required this.offset,
    required this.bytes,
  });
  final TraceGeometryRange target;
  final int offset;
  final ByteData bytes;
  @override
  String get kind => 'overwriteGeometry';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'target': _rangeToJson(target),
    'offset': offset,
    'bytes': blob.add(bytes),
  };
}

final class TraceReleaseGeometry extends TraceEvent {
  const TraceReleaseGeometry(this.buffer);
  final int buffer;
  @override
  String get kind => 'releaseGeometry';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'buffer': buffer,
  };
}

final class TraceCreateTexture extends TraceEvent {
  const TraceCreateTexture({required this.id, required this.spec});
  final int id;
  final RenderTargetSpec spec;
  @override
  String get kind => 'createTexture';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'spec': specToJson(spec),
  };
}

final class TraceCreateTextureFromPixels extends TraceEvent {
  const TraceCreateTextureFromPixels({
    required this.id,
    required this.width,
    required this.height,
    required this.format,
    required this.pixels,
    this.mipLevels,
  });
  final int id;
  final int width;
  final int height;
  final TextureFormat format;
  final ByteData pixels;
  final List<ByteData>? mipLevels;
  @override
  String get kind => 'createTextureFromPixels';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'width': width,
    'height': height,
    'format': format.name,
    'pixels': blob.add(pixels),
    'mipLevels': mipLevels?.map(blob.add).toList(),
  };
}

final class TraceCreateCubeTextureFromPixels extends TraceEvent {
  const TraceCreateCubeTextureFromPixels({
    required this.id,
    required this.size,
    required this.format,
    required this.faces,
    this.mipLevels,
  });
  final int id;
  final int size;
  final TextureFormat format;
  final List<ByteData> faces;
  final List<List<ByteData>>? mipLevels;
  @override
  String get kind => 'createCubeTextureFromPixels';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'size': size,
    'format': format.name,
    'faces': faces.map(blob.add).toList(),
    'mipLevels': mipLevels?.map((face) => face.map(blob.add).toList()).toList(),
  };
}

final class TraceCreateCubeRenderTarget extends TraceEvent {
  const TraceCreateCubeRenderTarget({
    required this.id,
    required this.size,
    required this.format,
    required this.mipLevels,
  });
  final int id;
  final int size;
  final TextureFormat format;
  final int mipLevels;
  @override
  String get kind => 'createCubeRenderTarget';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'size': size,
    'format': format.name,
    'mipLevels': mipLevels,
  };
}

final class TraceOverwriteTexture extends TraceEvent {
  const TraceOverwriteTexture({
    required this.texture,
    required this.rgba,
    this.region,
    this.mipLevel = 0,
  });
  final int texture;
  final ByteData rgba;
  final ScreenRect? region;
  final int mipLevel;
  @override
  String get kind => 'overwriteTexture';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'texture': texture,
    'rgba': blob.add(rgba),
    'region': region == null ? null : screenRectToJson(region!),
    'mipLevel': mipLevel,
  };
}

final class TraceReleaseTexture extends TraceEvent {
  const TraceReleaseTexture(this.texture);
  final int texture;
  @override
  String get kind => 'releaseTexture';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'texture': texture,
  };
}

final class TraceLoadShaders extends TraceEvent {
  const TraceLoadShaders(this.bytes);
  final ByteData bytes;
  @override
  String get kind => 'loadShaders';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'bytes': blob.add(bytes),
  };
}

final class TraceCreatePipeline extends TraceEvent {
  const TraceCreatePipeline({
    required this.id,
    required this.vertex,
    required this.fragment,
    this.layout,
  });
  final int id;

  /// Stage names, looked up again on the device a trace is replayed on.
  final String vertex;
  final String fragment;
  final VertexLayoutSpec? layout;
  @override
  String get kind => 'createPipeline';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'vertex': vertex,
    'fragment': fragment,
    'layout': layout == null ? null : layoutToJson(layout!),
  };
}

final class TraceBeginRenderPass extends TraceEvent {
  const TraceBeginRenderPass({
    required this.pass,
    required this.colors,
    this.depth,
    this.label,
  });

  /// Numbered in the order passes were opened; every pass event names it.
  final int pass;
  final List<TraceColorTarget> colors;
  final TraceDepthTarget? depth;
  final String? label;
  @override
  String get kind => 'beginRenderPass';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'label': label,
    'colors': <Object?>[
      for (final c in colors)
        <String, Object?>{
          'texture': c.texture,
          'resolveTexture': c.resolveTexture,
          'loadAction': c.loadAction.name,
          'storeAction': c.storeAction.name,
          'clearValue': c.clearValue == null
              ? null
              : vector4ToJson(c.clearValue!),
          'face': c.face,
          'mipLevel': c.mipLevel,
        },
    ],
    'depth': switch (depth) {
      null => null,
      final d => <String, Object?>{
        'texture': d.texture,
        'clearValue': d.clearValue,
        'loadAction': d.loadAction.name,
        'storeAction': d.storeAction.name,
        'stencilLoadAction': d.stencilLoadAction.name,
        'stencilStoreAction': d.stencilStoreAction.name,
        'stencilClearValue': d.stencilClearValue,
      },
    },
  };
}

final class TraceReadPixels extends TraceEvent {
  const TraceReadPixels(this.texture);
  final int texture;
  @override
  String get kind => 'readPixels';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'texture': texture,
  };
}

final class TraceReadback extends TraceEvent {
  const TraceReadback({required this.texture, this.region});
  final int texture;
  final ScreenRect? region;
  @override
  String get kind => 'readback';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'texture': texture,
    'region': region == null ? null : screenRectToJson(region!),
  };
}

// ------------------------------------------------------------------ pass

/// An event recorded into an open render pass.
sealed class TracePassEvent extends TraceEvent {
  const TracePassEvent(this.pass);
  final int pass;
}

final class TraceSetViewport extends TracePassEvent {
  const TraceSetViewport(super.pass, this.rect);
  final ScreenRect rect;
  @override
  String get kind => 'setViewport';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'rect': screenRectToJson(rect),
  };
}

final class TraceSetScissor extends TracePassEvent {
  const TraceSetScissor(super.pass, this.rect);
  final ScreenRect rect;
  @override
  String get kind => 'setScissor';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'rect': screenRectToJson(rect),
  };
}

final class TraceSetPrimitiveType extends TracePassEvent {
  const TraceSetPrimitiveType(super.pass, this.value);
  final PrimitiveType value;
  @override
  String get kind => 'setPrimitiveType';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': value.name,
  };
}

final class TraceSetPolygonMode extends TracePassEvent {
  const TraceSetPolygonMode(super.pass, this.value);
  final PolygonMode value;
  @override
  String get kind => 'setPolygonMode';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': value.name,
  };
}

final class TraceSetCullMode extends TracePassEvent {
  const TraceSetCullMode(super.pass, this.value);
  final CullMode value;
  @override
  String get kind => 'setCullMode';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': value.name,
  };
}

final class TraceSetWindingOrder extends TracePassEvent {
  const TraceSetWindingOrder(super.pass, this.value);
  final WindingOrder value;
  @override
  String get kind => 'setWindingOrder';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': value.name,
  };
}

final class TraceSetDepthWrite extends TracePassEvent {
  const TraceSetDepthWrite(super.pass, this.value);
  final bool value;
  @override
  String get kind => 'setDepthWrite';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': value,
  };
}

final class TraceSetDepthCompare extends TracePassEvent {
  const TraceSetDepthCompare(super.pass, this.value);
  final CompareFunction value;
  @override
  String get kind => 'setDepthCompare';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': value.name,
  };
}

final class TraceSetStencil extends TracePassEvent {
  const TraceSetStencil(super.pass, this.front, this.back);
  final StencilState front;
  final StencilState? back;
  @override
  String get kind => 'setStencil';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'front': stencilToJson(front),
    'back': back == null ? null : stencilToJson(back!),
  };
}

final class TraceSetStencilReference extends TracePassEvent {
  const TraceSetStencilReference(super.pass, this.value);
  final int value;
  @override
  String get kind => 'setStencilReference';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': value,
  };
}

final class TraceSetBlend extends TracePassEvent {
  const TraceSetBlend(super.pass, this.state, this.attachment);
  final BlendState? state;
  final int attachment;
  @override
  String get kind => 'setBlend';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'state': state == null ? null : blendToJson(state!),
    'attachment': attachment,
  };
}

final class TraceSetBlendColor extends TracePassEvent {
  const TraceSetBlendColor(super.pass, this.color);
  final Vector4 color;
  @override
  String get kind => 'setBlendColor';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'color': vector4ToJson(color),
  };
}

final class TraceBindPipeline extends TracePassEvent {
  const TraceBindPipeline(super.pass, this.pipeline);
  final int pipeline;
  @override
  String get kind => 'bindPipeline';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'pipeline': pipeline,
  };
}

final class TraceBindVertexBuffer extends TracePassEvent {
  const TraceBindVertexBuffer({
    required int pass,
    required this.buffer,
    required this.vertexCount,
    this.slot = 0,
  }) : super(pass);
  final TraceGeometryRange buffer;
  final int vertexCount;
  final int slot;
  @override
  String get kind => 'bindVertexBuffer';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'buffer': _rangeToJson(buffer),
    'vertexCount': vertexCount,
    'slot': slot,
  };
}

final class TraceBindVertexData extends TracePassEvent {
  const TraceBindVertexData({
    required int pass,
    required this.bytes,
    required this.vertexCount,
    this.slot = 0,
  }) : super(pass);
  final ByteData bytes;
  final int vertexCount;
  final int slot;
  @override
  String get kind => 'bindVertexData';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'bytes': blob.add(bytes),
    'vertexCount': vertexCount,
    'slot': slot,
  };
}

final class TraceBindIndexBuffer extends TracePassEvent {
  const TraceBindIndexBuffer({
    required int pass,
    required this.buffer,
    required this.type,
    required this.indexCount,
  }) : super(pass);
  final TraceGeometryRange buffer;
  final IndexType type;
  final int indexCount;
  @override
  String get kind => 'bindIndexBuffer';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'buffer': _rangeToJson(buffer),
    'type': type.name,
    'indexCount': indexCount,
  };
}

final class TraceBindIndexData extends TracePassEvent {
  const TraceBindIndexData({
    required int pass,
    required this.bytes,
    required this.type,
    required this.indexCount,
  }) : super(pass);
  final ByteData bytes;
  final IndexType type;
  final int indexCount;
  @override
  String get kind => 'bindIndexData';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'bytes': blob.add(bytes),
    'type': type.name,
    'indexCount': indexCount,
  };
}

final class TraceBindUniformBlock extends TracePassEvent {
  const TraceBindUniformBlock({
    required int pass,
    required this.shader,
    required this.block,
    required this.members,
  }) : super(pass);
  final String shader;
  final String block;

  /// Copied when recorded: the renderer refills its scratch arrays for the
  /// next draw, and a reference would record the last draw's values for all.
  final Map<String, Float32List> members;
  @override
  String get kind => 'bindUniformBlock';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'shader': shader,
    'block': block,
    'members': _membersToJson(members, blob),
  };
}

final class TraceBindTexture extends TracePassEvent {
  const TraceBindTexture({
    required int pass,
    required this.shader,
    required this.slot,
    required this.texture,
    this.sampler,
  }) : super(pass);
  final String shader;
  final String slot;
  final int texture;
  final SamplerOptions? sampler;
  @override
  String get kind => 'bindTexture';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'shader': shader,
    'slot': slot,
    'texture': texture,
    'sampler': sampler == null ? null : samplerToJson(sampler!),
  };
}

final class TraceClearBindings extends TracePassEvent {
  const TraceClearBindings(super.pass);
  @override
  String get kind => 'clearBindings';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
  };
}

final class TraceDraw extends TracePassEvent {
  const TraceDraw(super.pass, [this.instanceCount = 1]);
  final int instanceCount;
  @override
  String get kind => 'draw';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'instanceCount': instanceCount,
  };
}

final class TraceSubmit extends TracePassEvent {
  const TraceSubmit(super.pass);
  @override
  String get kind => 'submit';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
  };
}

// --------------------------------------------------------------- compute

final class TraceCreateStorageBuffer extends TraceEvent {
  const TraceCreateStorageBuffer({
    required this.id,
    required this.bytes,
    required this.hostReadable,
  });
  final int id;
  final ByteData bytes;
  final bool hostReadable;
  @override
  String get kind => 'createStorageBuffer';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'bytes': blob.add(bytes),
    'hostReadable': hostReadable,
  };
}

final class TraceReleaseStorageBuffer extends TraceEvent {
  const TraceReleaseStorageBuffer(this.buffer);
  final int buffer;
  @override
  String get kind => 'releaseStorageBuffer';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'buffer': buffer,
  };
}

final class TraceCreateComputePipeline extends TraceEvent {
  const TraceCreateComputePipeline(this.id, this.shader);
  final int id;
  final String shader;
  @override
  String get kind => 'createComputePipeline';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'shader': shader,
  };
}

final class TraceBeginComputePass extends TraceEvent {
  const TraceBeginComputePass(this.pass, this.label);
  final int pass;
  final String? label;
  @override
  String get kind => 'beginComputePass';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'label': label,
  };
}

final class TraceComputeBindPipeline extends TraceEvent {
  const TraceComputeBindPipeline(this.pass, this.pipeline);
  final int pass;
  final int pipeline;
  @override
  String get kind => 'computeBindPipeline';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'pipeline': pipeline,
  };
}

final class TraceComputeBindStorageBuffer extends TraceEvent {
  const TraceComputeBindStorageBuffer({
    required this.pass,
    required this.shader,
    required this.name,
    required this.buffer,
  });
  final int pass;
  final String shader;
  final String name;
  final int buffer;
  @override
  String get kind => 'computeBindStorageBuffer';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'shader': shader,
    'name': name,
    'buffer': buffer,
  };
}

final class TraceComputeBindUniformBlock extends TraceEvent {
  const TraceComputeBindUniformBlock({
    required this.pass,
    required this.shader,
    required this.block,
    required this.members,
  });
  final int pass;
  final String shader;
  final String block;
  final Map<String, Float32List> members;
  @override
  String get kind => 'computeBindUniformBlock';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'shader': shader,
    'block': block,
    'members': _membersToJson(members, blob),
  };
}

final class TraceDispatch extends TraceEvent {
  const TraceDispatch(this.pass, this.x, this.y, this.z);
  final int pass;
  final int x;
  final int y;
  final int z;
  @override
  String get kind => 'dispatch';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'x': x,
    'y': y,
    'z': z,
  };
}

final class TraceComputeSubmit extends TraceEvent {
  const TraceComputeSubmit(this.pass);
  final int pass;
  @override
  String get kind => 'computeSubmit';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
  };
}

final class TraceReadBuffer extends TraceEvent {
  const TraceReadBuffer(this.buffer);
  final int buffer;
  @override
  String get kind => 'readBuffer';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'buffer': buffer,
  };
}
