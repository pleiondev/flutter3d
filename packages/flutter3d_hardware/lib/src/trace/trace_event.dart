/// One call a device or an encoder received, as a value — `H3`.
///
/// **Its own hierarchy, not `Recorded`'s.** `Recorded` is what a test asserts
/// against, and it is lossy on purpose: a vertex binding says how many
/// vertices, not which buffer. A trace has to be replayed, so every event here
/// carries everything its call took, with resources named by the order they
/// were created in rather than by handles that die with the process.
///
/// **Open, not sealed, since 1.0**, so a call the HAL gains in a 1.x minor
/// adds an event without breaking anybody: a `switch` over these ends in a
/// `default` (or `_`) branch. What that branch does is the documented
/// default — the replay throws a [StateError] naming the event's [kind],
/// because an event it cannot replay is a frame it cannot reproduce, and a
/// reader meeting a kind it does not know refuses the whole trace with a
/// `TraceFormatException` rather than dropping the event. The events are
/// `final` themselves: a new call is a new event, never a subclass of an old
/// one.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor;

import '../formats.dart';
import '../geometry_buffer.dart';
import '../render_pass_descriptor.dart';
import '../resources.dart';
import '../sampler.dart';
import '../vertex_layout_spec.dart';
import 'trace_format_exception.dart';
import 'trace_values.dart';
import 'trace_wire_names.dart';

/// A slice of a geometry buffer: which buffer, and which bytes of it.
typedef TraceGeometryRange = ({int buffer, int offset, int length});

/// One colour attachment, with its textures named by id: a `ColorTarget`
/// as a trace writes it.
///
/// **A class, not a record, since 1.0**, so a field `ColorTarget` gains in
/// a minor is a field here with the same default, and a trace written
/// before it reads as what it was. The defaults are `ColorTarget`'s.
final class TraceColorTarget {
  /// Creates an attachment of texture id [texture], with `ColorTarget`'s
  /// defaults for everything else.
  const TraceColorTarget({
    required this.texture,
    this.resolveTexture,
    this.loadAction = LoadAction.clear,
    this.storeAction = StoreAction.store,
    this.clearValue,
    this.face = 0,
    this.mipLevel = 0,
    this.layer = 0,
  });

  /// The attachment, by the id the trace created it under.
  final int texture;

  /// Where a multisampled attachment resolves, by id; null for none.
  final int? resolveTexture;

  /// What the attachment holds when the pass begins; clears by default.
  final LoadAction loadAction;

  /// What happens to the attachment's contents when the pass ends; kept by
  /// default.
  final StoreAction storeAction;

  /// The colour a clear writes, linear RGBA, unitless; null clears to
  /// transparent black.
  final ClearColor? clearValue;

  /// The cube face, mip level and array layer the pass draws into.
  final int face;

  /// The mip level the pass draws into, zero for the base level.
  final int mipLevel;

  /// The array layer the pass draws into, zero for the first. Not written
  /// to the file when zero.
  final int layer;
}

/// The depth attachment, with its texture named by id: a `DepthTarget` as
/// a trace writes it. A class for [TraceColorTarget]'s reason, with
/// `DepthTarget`'s defaults.
final class TraceDepthTarget {
  /// Creates a depth attachment of texture id [texture], with
  /// `DepthTarget`'s defaults for everything else.
  const TraceDepthTarget({
    required this.texture,
    this.clearValue = 1.0,
    this.loadAction = LoadAction.clear,
    this.storeAction = StoreAction.dontCare,
    this.stencilLoadAction = LoadAction.clear,
    this.stencilStoreAction = StoreAction.dontCare,
    this.stencilClearValue = 0,
    this.mipLevel = 0,
    this.layer = 0,
    this.face = 0,
    this.depthReadOnly = false,
    this.stencilReadOnly = false,
  });

  /// The attachment, by the id the trace created it under.
  final int texture;

  /// The depth a clear writes. A depth from 0 to 1, unitless.
  final double clearValue;

  /// What the depth plane holds when the pass begins; clears by default.
  /// Absent from a trace written before passes could load depth, and read
  /// back as a clear.
  final LoadAction loadAction;

  /// What happens to the depth plane when the pass ends; discarded by
  /// default.
  final StoreAction storeAction;

  /// What the stencil plane holds when the pass begins; clears by default.
  final LoadAction stencilLoadAction;

  /// What happens to the stencil plane when the pass ends; discarded by
  /// default.
  final StoreAction stencilStoreAction;

  /// The stencil value a clear writes, eight bits; zero by default.
  final int stencilClearValue;

  /// The mip level, array layer and cube face the pass draws into.
  final int mipLevel;

  /// The array layer the pass draws into, zero for the first. Not written
  /// to the file when zero.
  final int layer;

  /// The cube face the pass draws into, zero for +X or a 2D texture. Not
  /// written to the file when zero.
  final int face;

  /// Whether the pass only reads depth, or stencil, from the attachment.
  final bool depthReadOnly;

  /// Whether the pass only reads the stencil plane, leaving it unwritten.
  /// Not written to the file when false.
  final bool stencilReadOnly;
}

/// The base of every recorded call; see the library comment for why it is
/// open and what a `switch` over it owes.
abstract base class TraceEvent {
  /// Lets a subclass be a `const` value.
  const TraceEvent();

  /// The event's name in a trace file.
  String get kind;

  /// Returns the event as the JSON object a trace file holds, without its
  /// `kind` key, with every byte payload handed to [blob] and written as
  /// the reference it returns.
  Map<String, Object?> toJson(TraceBlobWriter blob);

  /// Reads one event back from its JSON object [j], resolving byte payloads
  /// through [blob].
  ///
  /// Throws a [TraceFormatException] for a `kind` this build does not know,
  /// rather than dropping the event, and for a value of the wrong shape.
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
      format: textureFormatWire.read(j['format']),
      pixels: blob.read(j['pixels']),
      mipLevels: (j['mipLevels'] as List<Object?>?)?.map(blob.read).toList(),
    ),
    'createCubeTextureFromPixels' => TraceCreateCubeTextureFromPixels(
      id: asInt(j['id']),
      size: asInt(j['size']),
      format: textureFormatWire.read(j['format']),
      faces: (j['faces']! as List<Object?>).map(blob.read).toList(),
      mipLevels: (j['mipLevels'] as List<Object?>?)
          ?.map((f) => (f! as List<Object?>).map(blob.read).toList())
          .toList(),
    ),
    'createCubeRenderTarget' => TraceCreateCubeRenderTarget(
      id: asInt(j['id']),
      size: asInt(j['size']),
      format: textureFormatWire.read(j['format']),
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
          TraceColorTarget(
            texture: asInt(c['texture']),
            resolveTexture: c['resolveTexture'] == null
                ? null
                : asInt(c['resolveTexture']),
            loadAction: loadActionWire.read(c['loadAction']),
            storeAction: storeActionWire.read(c['storeAction']),
            clearValue: c['clearValue'] == null
                ? null
                : clearColorFromJson(c['clearValue']),
            face: asInt(c['face']),
            mipLevel: asInt(c['mipLevel']),
            // Absent from a trace written before 1.0 recorded layers, and
            // from any attachment at layer zero.
            layer: c['layer'] == null ? 0 : asInt(c['layer']),
          ),
      ],
      depth: switch (j['depth']) {
        null => null,
        final Object d => _depthTarget(asMap(d)),
      },
    ),
    'readPixels' => TraceReadPixels(asInt(j['texture'])),
    'readback' => TraceReadback(
      texture: asInt(j['texture']),
      region: j['region'] == null ? null : screenRectFromJson(j['region']),
    ),
    'setViewport' => TraceSetViewport(
      asInt(j['pass']),
      viewportFromJson(j['rect']),
    ),
    'setScissor' => TraceSetScissor(
      asInt(j['pass']),
      screenRectFromJson(j['rect']),
    ),
    'setPrimitiveType' => TraceSetPrimitiveType(
      asInt(j['pass']),
      primitiveTypeWire.read(j['value']),
    ),
    'setPolygonMode' => TraceSetPolygonMode(
      asInt(j['pass']),
      polygonModeWire.read(j['value']),
    ),
    'setCullMode' => TraceSetCullMode(
      asInt(j['pass']),
      cullModeWire.read(j['value']),
    ),
    'setWindingOrder' => TraceSetWindingOrder(
      asInt(j['pass']),
      windingOrderWire.read(j['value']),
    ),
    'setDepthWrite' => TraceSetDepthWrite(
      asInt(j['pass']),
      j['value']! as bool,
    ),
    'setAlphaToCoverage' => TraceSetAlphaToCoverage(
      asInt(j['pass']),
      j['value']! as bool,
    ),
    'setDepthCompare' => TraceSetDepthCompare(
      asInt(j['pass']),
      compareFunctionWire.read(j['value']),
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
      linearColorFromJson(j['color']),
    ),
    'pushDebugGroup' => TracePushDebugGroup(
      asInt(j['pass']),
      j['label']! as String,
    ),
    'popDebugGroup' => TracePopDebugGroup(asInt(j['pass'])),
    'insertDebugMarker' => TraceInsertDebugMarker(
      asInt(j['pass']),
      j['label']! as String,
    ),
    'setLabel' => TraceSetLabel(
      resource: TraceLabeled.fromWire(j['resource']),
      id: asInt(j['id']),
      label: j['label']! as String,
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
      type: indexTypeWire.read(j['type']),
      indexCount: asInt(j['indexCount']),
    ),
    'bindIndexData' => TraceBindIndexData(
      pass: asInt(j['pass']),
      bytes: blob.read(j['bytes']),
      type: indexTypeWire.read(j['type']),
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
    'draw' => TraceDraw(
      asInt(j['pass']),
      instanceCount: asInt(j['instanceCount']),
      firstIndex: j['firstIndex'] == null ? 0 : asInt(j['firstIndex']),
      indexCount: j['indexCount'] == null ? null : asInt(j['indexCount']),
    ),
    'submit' => TraceSubmit(asInt(j['pass'])),
    'createStorageBuffer' => TraceCreateStorageBuffer(
      id: asInt(j['id']),
      bytes: blob.read(j['bytes']),
      hostReadable: j['hostReadable']! as bool,
      indices: j['indices'] == null ? null : asInt(j['indices']),
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
    final other => throw TraceFormatException(
      'a trace event of kind $other, which this build does not know',
    ),
  };
}

/// A depth attachment read back. Every key 1.0 added is written only when
/// it is not its default, so a trace without them reads as the pass it was.
TraceDepthTarget _depthTarget(Map<String, Object?> d) => TraceDepthTarget(
  texture: asInt(d['texture']),
  clearValue: asDouble(d['clearValue']),
  // Absent from a trace written before `R8` let a pass load depth, and
  // absent means what every pass did then.
  loadAction: d['loadAction'] == null
      ? LoadAction.clear
      : loadActionWire.read(d['loadAction']),
  storeAction: d['storeAction'] == null
      ? StoreAction.dontCare
      : storeActionWire.read(d['storeAction']),
  stencilLoadAction: loadActionWire.read(d['stencilLoadAction']),
  stencilStoreAction: storeActionWire.read(d['stencilStoreAction']),
  stencilClearValue: asInt(d['stencilClearValue']),
  mipLevel: d['mipLevel'] == null ? 0 : asInt(d['mipLevel']),
  layer: d['layer'] == null ? 0 : asInt(d['layer']),
  face: d['face'] == null ? 0 : asInt(d['face']),
  depthReadOnly: d['depthReadOnly'] == true,
  stencilReadOnly: d['stencilReadOnly'] == true,
);

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

/// `GraphicsDevice.beginFrame`: the start of a frame. Carries nothing.
final class TraceBeginFrame extends TraceEvent {
  /// Creates the event; every one is the same value.
  const TraceBeginFrame();
  @override
  String get kind => 'beginFrame';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{};
}

/// `GraphicsDevice.uploadGeometry`: a geometry buffer made from [bytes].
final class TraceUploadGeometry extends TraceEvent {
  /// Records an upload of [bytes] as buffer [id] with [usage].
  const TraceUploadGeometry({
    required this.id,
    required this.usage,
    required this.bytes,
  });

  /// The id later events name this buffer by, counted among geometry
  /// buffers in the order they were created.
  final int id;

  /// Whether the buffer holds vertices or indices, which a backend that
  /// binds a buffer to one target for good needs at creation.
  final GeometryUsage usage;

  /// The buffer's whole contents, copied when recorded.
  final ByteData bytes;
  @override
  String get kind => 'uploadGeometry';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'usage': geometryUsageWire.write(usage),
    'bytes': blob.add(bytes),
  };
}

/// `GraphicsDevice.overwriteGeometry`: [bytes] written into a buffer the trace
/// uploaded.
final class TraceOverwriteGeometry extends TraceEvent {
  /// Records [bytes] written at [offset] into the range [target].
  const TraceOverwriteGeometry({
    required this.target,
    required this.offset,
    required this.bytes,
  });

  /// The range the call named: the buffer's id, and the slice's offset from the
  /// start of that upload and its length, both in bytes.
  final TraceGeometryRange target;

  /// Where the write starts, in bytes from the start of [target].
  final int offset;

  /// The bytes written, copied when recorded.
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

/// `GraphicsDevice.releaseGeometry`: a geometry buffer given back.
final class TraceReleaseGeometry extends TraceEvent {
  /// Records the release of geometry buffer id [buffer].
  const TraceReleaseGeometry(this.buffer);

  /// The id of the upload released, among geometry buffers.
  final int buffer;
  @override
  String get kind => 'releaseGeometry';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'buffer': buffer,
  };
}

/// `GraphicsDevice.createTexture`, or a render target a pool made: an empty
/// texture.
final class TraceCreateTexture extends TraceEvent {
  /// Records a texture made from [spec] under id [id].
  const TraceCreateTexture({required this.id, required this.spec});

  /// The id later events name this texture by, counted among textures in the
  /// order they were created.
  final int id;

  /// Everything the texture was made from: its shape, layers, levels,
  /// samples, usage and label. A `RenderTargetDescriptor` (a pool's
  /// target) reads back as one, since a backend makes those its own way.
  final TextureDescriptor spec;
  @override
  String get kind => 'createTexture';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'spec': specToJson(spec),
  };
}

/// `GraphicsDevice.createTextureFromPixels`: a 2D texture made holding
/// [pixels].
final class TraceCreateTextureFromPixels extends TraceEvent {
  /// Records a [width] by [height] texture of [format] made from [pixels] and,
  /// when given, [mipLevels].
  const TraceCreateTextureFromPixels({
    required this.id,
    required this.width,
    required this.height,
    required this.format,
    required this.pixels,
    this.mipLevels,
  });

  /// The id later events name this texture by, among textures.
  final int id;

  /// Width of the base level in texels.
  final int width;

  /// Height of the base level in texels.
  final int height;

  /// The layout of [pixels] and of every level in [mipLevels].
  final TextureFormat format;

  /// The base level's bytes, row-major from the top, as the call took them.
  final ByteData pixels;

  /// The smaller levels, from half size downwards, as the caller supplied them;
  /// null for a texture with only its base level.
  final List<ByteData>? mipLevels;
  @override
  String get kind => 'createTextureFromPixels';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'width': width,
    'height': height,
    'format': textureFormatWire.write(format),
    'pixels': blob.add(pixels),
    'mipLevels': mipLevels?.map(blob.add).toList(),
  };
}

/// `GraphicsDevice.createCubeTextureFromPixels`: a cube texture made from six
/// square faces.
final class TraceCreateCubeTextureFromPixels extends TraceEvent {
  /// Records a cube of [size] by [size] faces of [format] made from [faces]
  /// and, when given, [mipLevels].
  const TraceCreateCubeTextureFromPixels({
    required this.id,
    required this.size,
    required this.format,
    required this.faces,
    this.mipLevels,
  });

  /// The id later events name this texture by, among textures.
  final int id;

  /// Width and height of each face's base level, in texels.
  final int size;

  /// The layout of every face and every level.
  final TextureFormat format;

  /// The six base-level faces in the order +X, −X, +Y, −Y, +Z, −Z.
  final List<ByteData> faces;

  /// The smaller levels: one list per face, in [faces]' order, each from half
  /// size downwards; null for a cube with only its base level.
  final List<List<ByteData>>? mipLevels;
  @override
  String get kind => 'createCubeTextureFromPixels';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'size': size,
    'format': textureFormatWire.write(format),
    'faces': faces.map(blob.add).toList(),
    'mipLevels': mipLevels?.map((face) => face.map(blob.add).toList()).toList(),
  };
}

/// `GraphicsDevice.createCubeRenderTarget`: an empty cube a pass can draw into.
final class TraceCreateCubeRenderTarget extends TraceEvent {
  /// Records a cube of [size] by [size] faces of [format] with [mipLevels]
  /// levels.
  const TraceCreateCubeRenderTarget({
    required this.id,
    required this.size,
    required this.format,
    required this.mipLevels,
  });

  /// The id later events name this texture by, among textures.
  final int id;

  /// Width and height of each face's base level, in texels.
  final int size;

  /// The format of every face.
  final TextureFormat format;

  /// How many levels the call asked for, the base level included; a device that
  /// allocates fewer trims the chain on replay.
  final int mipLevels;
  @override
  String get kind => 'createCubeRenderTarget';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'size': size,
    'format': textureFormatWire.write(format),
    'mipLevels': mipLevels,
  };
}

/// `GraphicsDevice.overwriteTexture`: a region of a texture written from RGBA8
/// bytes.
final class TraceOverwriteTexture extends TraceEvent {
  /// Records [rgba] written into [region] of texture id [texture].
  const TraceOverwriteTexture({
    required this.texture,
    required this.rgba,
    this.region,
    this.mipLevel = 0,
  });

  /// The id of the texture written, among textures.
  final int texture;

  /// Raw RGBA8 bytes, four per texel, row-major from the top, covering
  /// [region].
  final ByteData rgba;

  /// The rectangle written, in texels; null for the whole texture.
  final ScreenRect? region;

  /// The level the call named. The device refuses any but zero, and a trace
  /// records what was asked.
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

/// `TextureHandle.dispose` or `GraphicsDevice.releaseTexture`: a texture given
/// back.
final class TraceReleaseTexture extends TraceEvent {
  /// Records the release of texture id [texture].
  const TraceReleaseTexture(this.texture);

  /// The id of the texture released, among textures.
  final int texture;
  @override
  String get kind => 'releaseTexture';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'texture': texture,
  };
}

/// `GraphicsDevice.loadShaders`: a shader bundle loaded. Pipelines name their
/// stages by name, looked up in the libraries loaded so far.
final class TraceLoadShaders extends TraceEvent {
  /// Records the load of the bundle [bytes].
  const TraceLoadShaders(this.bytes);

  /// The bundle's bytes exactly as loaded, copied when recorded.
  final ByteData bytes;
  @override
  String get kind => 'loadShaders';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'bytes': blob.add(bytes),
  };
}

/// `GraphicsDevice.createPipeline`: a render pipeline from two stages and an
/// optional vertex layout.
final class TraceCreatePipeline extends TraceEvent {
  /// Records the pipeline [id] built from [vertex] and [fragment] with
  /// [layout].
  const TraceCreatePipeline({
    required this.id,
    required this.vertex,
    required this.fragment,
    this.layout,
  });

  /// The id later events name this pipeline by, among render pipelines.
  final int id;

  /// Stage names, looked up again on the device a trace is replayed on.
  final String vertex;

  /// The fragment stage's name in the loaded libraries.
  final String fragment;

  /// The vertex layout the call gave; null when the backend reflected it from
  /// the vertex stage.
  final VertexLayoutDescriptor? layout;
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

/// `GraphicsDevice.beginRenderPass`: a render pass opened on textures the trace
/// made.
final class TraceBeginRenderPass extends TraceEvent {
  /// Records pass [pass] opened on [colors] and [depth].
  const TraceBeginRenderPass({
    required this.pass,
    required this.colors,
    this.depth,
    this.label,
  });

  /// Numbered in the order passes were opened; every pass event names it.
  final int pass;

  /// The colour attachments, in attachment order.
  final List<TraceColorTarget> colors;

  /// The depth attachment; null for a pass without one.
  final TraceDepthTarget? depth;

  /// The name given to a debugger and to GPU timings; null for none.
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
          'loadAction': loadActionWire.write(c.loadAction),
          'storeAction': storeActionWire.write(c.storeAction),
          'clearValue': c.clearValue == null
              ? null
              : clearColorToJson(c.clearValue!),
          'face': c.face,
          'mipLevel': c.mipLevel,
          // Since 1.0, written only when set, so a trace of a pass at layer
          // zero is byte for byte what it was.
          if (c.layer != 0) 'layer': c.layer,
        },
    ],
    'depth': switch (depth) {
      null => null,
      final d => <String, Object?>{
        'texture': d.texture,
        'clearValue': d.clearValue,
        'loadAction': loadActionWire.write(d.loadAction),
        'storeAction': storeActionWire.write(d.storeAction),
        'stencilLoadAction': loadActionWire.write(d.stencilLoadAction),
        'stencilStoreAction': storeActionWire.write(d.stencilStoreAction),
        'stencilClearValue': d.stencilClearValue,
        if (d.mipLevel != 0) 'mipLevel': d.mipLevel,
        if (d.layer != 0) 'layer': d.layer,
        if (d.face != 0) 'face': d.face,
        if (d.depthReadOnly) 'depthReadOnly': true,
        if (d.stencilReadOnly) 'stencilReadOnly': true,
      },
    },
  };
}

/// A read of a whole texture written by a trace from before 1.0, when
/// `readPixels` was its own call. Nothing records it now; a replay answers it
/// with `GraphicsDevice.readback`.
final class TraceReadPixels extends TraceEvent {
  /// Records a read of the whole of texture id [texture].
  const TraceReadPixels(this.texture);

  /// The id of the texture read, among textures.
  final int texture;
  @override
  String get kind => 'readPixels';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'texture': texture,
  };
}

/// `GraphicsDevice.readback`: a texture's pixels read back at this point in the
/// queue.
final class TraceReadback extends TraceEvent {
  /// Records a read of [region] of texture id [texture].
  const TraceReadback({required this.texture, this.region});

  /// The id of the texture read, among textures.
  final int texture;

  /// The rectangle read, in texels; null for the whole texture.
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
abstract base class TracePassEvent extends TraceEvent {
  /// Records an event in pass [pass].
  const TracePassEvent(this.pass);

  /// The pass the event belongs to, by the number its `beginRenderPass` was
  /// recorded under.
  final int pass;
}

/// `PassEncoder.setViewport`: a [PassViewport] since 1.0.0-rc.1, written as
/// the four whole numbers a `ScreenRect` was whenever it covers whole pixels
/// and the whole depth range, so older traces read and newer ones of such a
/// pass are byte for byte what they were.
final class TraceSetViewport extends TracePassEvent {
  /// Records [viewport] set on pass [pass].
  const TraceSetViewport(super.pass, this.viewport);

  /// The rectangle in pixels of the attachment, with its depth range.
  final PassViewport viewport;
  @override
  String get kind => 'setViewport';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'rect': viewportToJson(viewport),
  };
}

/// `PassEncoder.setScissor`: the rectangle draws are clipped to.
final class TraceSetScissor extends TracePassEvent {
  /// Records the scissor [rect] set on pass [pass].
  const TraceSetScissor(super.pass, this.rect);

  /// The scissor rectangle, in pixels of the attachment.
  final ScreenRect rect;
  @override
  String get kind => 'setScissor';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'rect': screenRectToJson(rect),
  };
}

/// `PassEncoder.setPrimitiveType`: how the following draws assemble vertices.
final class TraceSetPrimitiveType extends TracePassEvent {
  /// Records [value] set on pass [pass].
  const TraceSetPrimitiveType(super.pass, this.value);

  /// The primitive the following draws assemble.
  final PrimitiveType value;
  @override
  String get kind => 'setPrimitiveType';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': primitiveTypeWire.write(value),
  };
}

/// `PassEncoder.setPolygonMode`: whether triangles fill or draw as lines.
final class TraceSetPolygonMode extends TracePassEvent {
  /// Records [value] set on pass [pass].
  const TraceSetPolygonMode(super.pass, this.value);

  /// How the following draws rasterise triangles.
  final PolygonMode value;
  @override
  String get kind => 'setPolygonMode';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': polygonModeWire.write(value),
  };
}

/// `PassEncoder.setCullMode`: which faces the following draws discard.
final class TraceSetCullMode extends TracePassEvent {
  /// Records [value] set on pass [pass].
  const TraceSetCullMode(super.pass, this.value);

  /// The faces discarded.
  final CullMode value;
  @override
  String get kind => 'setCullMode';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': cullModeWire.write(value),
  };
}

/// `PassEncoder.setWindingOrder`: which winding counts as front-facing.
final class TraceSetWindingOrder extends TracePassEvent {
  /// Records [value] set on pass [pass].
  const TraceSetWindingOrder(super.pass, this.value);

  /// The winding treated as the front face.
  final WindingOrder value;
  @override
  String get kind => 'setWindingOrder';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': windingOrderWire.write(value),
  };
}

/// `PassEncoder.setAlphaToCoverage` — `P7`. A trace recorded before it had
/// none, which replays as it was recorded: off.
final class TraceSetAlphaToCoverage extends TracePassEvent {
  /// Records alpha to coverage turned on or off in pass [pass].
  const TraceSetAlphaToCoverage(super.pass, this.value);

  /// Whether fragment alpha drives the sample coverage mask.
  final bool value;
  @override
  String get kind => 'setAlphaToCoverage';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': value,
  };
}

/// `PassEncoder.setDepthWrite`: whether the following draws write depth.
final class TraceSetDepthWrite extends TracePassEvent {
  /// Records depth writes turned on or off in pass [pass].
  const TraceSetDepthWrite(super.pass, this.value);

  /// Whether passing fragments write their depth.
  final bool value;
  @override
  String get kind => 'setDepthWrite';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': value,
  };
}

/// `PassEncoder.setDepthCompare`: the depth test of the following draws.
final class TraceSetDepthCompare extends TracePassEvent {
  /// Records [value] set on pass [pass].
  const TraceSetDepthCompare(super.pass, this.value);

  /// How a fragment's depth is compared with the stored one.
  final CompareFunction value;
  @override
  String get kind => 'setDepthCompare';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': compareFunctionWire.write(value),
  };
}

/// `PassEncoder.setStencil`: the stencil test of the following draws.
final class TraceSetStencil extends TracePassEvent {
  /// Records the stencil states [front] and [back] set on pass [pass].
  const TraceSetStencil(super.pass, this.front, this.back);

  /// The state for front-facing triangles, and for back-facing ones when [back]
  /// is null.
  final StencilState front;

  /// The state for back-facing triangles; null when [front] applies to both.
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

/// `PassEncoder.setStencilReference`: the value the stencil test compares
/// against.
final class TraceSetStencilReference extends TracePassEvent {
  /// Records the reference [value] set on pass [pass].
  const TraceSetStencilReference(super.pass, this.value);

  /// The reference as the call gave it; the device keeps its low eight bits.
  final int value;
  @override
  String get kind => 'setStencilReference';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'value': value,
  };
}

/// `PassEncoder.setBlend`: the blend state of one colour attachment.
final class TraceSetBlend extends TracePassEvent {
  /// Records [state] set on colour attachment [attachment] of pass [pass].
  const TraceSetBlend(super.pass, this.state, this.attachment);

  /// The blend state; null turns blending off.
  final BlendState? state;

  /// The colour attachment index, zero for the first.
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

/// `PassEncoder.setBlendColor`: the constant the blend-constant factors read.
final class TraceSetBlendColor extends TracePassEvent {
  /// Records the blend constant [color] set on pass [pass].
  const TraceSetBlendColor(super.pass, this.color);

  /// The constant, linear RGBA, unitless.
  final LinearColor color;
  @override
  String get kind => 'setBlendColor';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'color': linearColorToJson(color),
  };
}

/// `PassEncoder.pushDebugGroup`: a named group opened in pass [pass].
final class TracePushDebugGroup extends TracePassEvent {
  /// Records the group [label] opened in pass [pass].
  const TracePushDebugGroup(super.pass, this.label);

  /// The group's name, as a debugger shows it.
  final String label;
  @override
  String get kind => 'pushDebugGroup';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'label': label,
  };
}

/// `PassEncoder.popDebugGroup`.
final class TracePopDebugGroup extends TracePassEvent {
  /// Records the innermost open group of pass [pass] closed.
  const TracePopDebugGroup(super.pass);
  @override
  String get kind => 'popDebugGroup';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
  };
}

/// `PassEncoder.insertDebugMarker`.
final class TraceInsertDebugMarker extends TracePassEvent {
  /// Records the marker [label] inserted in pass [pass].
  const TraceInsertDebugMarker(super.pass, this.label);

  /// The marker's text, as a debugger shows it.
  final String label;
  @override
  String get kind => 'insertDebugMarker';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'label': label,
  };
}

/// What kind of resource a [TraceSetLabel] names, which says whose ids its
/// number is among.
final class TraceLabeled {
  const TraceLabeled._(this.wire);

  /// A texture, by the id its creation was recorded under.
  static const TraceLabeled texture = TraceLabeled._('texture');

  /// A geometry buffer, by its upload's id.
  static const TraceLabeled geometry = TraceLabeled._('geometry');

  /// A render pipeline, by its creation's id.
  static const TraceLabeled pipeline = TraceLabeled._('pipeline');

  /// A storage buffer, by its creation's id.
  static const TraceLabeled storage = TraceLabeled._('storage');

  /// The value whose [wire] is [name], or null for a name this
  /// version does not know, which is what a file written by a later
  /// version can carry.
  static TraceLabeled? byName(String name) {
    for (final value in values) {
      if (value.wire == name) return value;
    }
    return null;
  }

  /// Every kind this build knows, in declaration order.
  static const List<TraceLabeled> values = <TraceLabeled>[
    texture,
    geometry,
    pipeline,
    storage,
  ];

  /// The word written to a trace file.
  final String wire;

  /// The kind [value] names, or a [TraceFormatException] for a word this
  /// build does not know.
  static TraceLabeled fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    throw TraceFormatException('a label on an unknown resource kind: $value');
  }

  @override
  String toString() => 'TraceLabeled.$wire';
}

/// `GraphicsDevice.setLabel`: [label] given to a resource the trace made.
final class TraceSetLabel extends TraceEvent {
  /// Records [label] given to the resource [id] of kind [resource].
  const TraceSetLabel({
    required this.resource,
    required this.id,
    required this.label,
  });

  /// The kind of resource named, which says whose ids [id] counts among.
  final TraceLabeled resource;

  /// The resource's id among those of its kind.
  final int id;

  /// The name given, as a debugger shows it.
  final String label;
  @override
  String get kind => 'setLabel';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'resource': resource.wire,
    'id': id,
    'label': label,
  };
}

/// `PassEncoder.bindPipeline`: the render pipeline the following draws use.
final class TraceBindPipeline extends TracePassEvent {
  /// Records pipeline id [pipeline] bound in pass [pass].
  const TraceBindPipeline(super.pass, this.pipeline);

  /// The pipeline's id, among render pipelines.
  final int pipeline;
  @override
  String get kind => 'bindPipeline';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'pipeline': pipeline,
  };
}

/// `PassEncoder.bindVertexBuffer`: vertices the device already holds.
final class TraceBindVertexBuffer extends TracePassEvent {
  /// Records [vertexCount] vertices of [buffer] bound to [slot] in pass [pass].
  const TraceBindVertexBuffer({
    required int pass,
    required this.buffer,
    required this.vertexCount,
    this.slot = 0,
  }) : super(pass);

  /// The range bound: a geometry buffer's id, and the offset from the start of
  /// its upload and the length, in bytes.
  final TraceGeometryRange buffer;

  /// How many vertices the following draws read, a count.
  final int vertexCount;

  /// Which of the pipeline's vertex buffers this fills, zero for the first.
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

/// `PassEncoder.bindVertexData`: vertices built this frame, bound as bytes.
final class TraceBindVertexData extends TracePassEvent {
  /// Records [vertexCount] vertices in [bytes] bound to [slot] in pass [pass].
  const TraceBindVertexData({
    required int pass,
    required this.bytes,
    required this.vertexCount,
    this.slot = 0,
  }) : super(pass);

  /// The vertices, copied when recorded.
  final ByteData bytes;

  /// How many vertices the following draws read, a count.
  final int vertexCount;

  /// Which of the pipeline's vertex buffers this fills, zero for the first.
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

/// `PassEncoder.bindIndexBuffer`: indices the device already holds.
final class TraceBindIndexBuffer extends TracePassEvent {
  /// Records [indexCount] indices of [type] in [buffer] bound in pass [pass].
  const TraceBindIndexBuffer({
    required int pass,
    required this.buffer,
    required this.type,
    required this.indexCount,
  }) : super(pass);

  /// The range bound: a geometry buffer's id, and the offset from the start of
  /// its upload and the length, in bytes.
  final TraceGeometryRange buffer;

  /// The width of each index.
  final IndexType type;

  /// How many indices the binding holds, a count.
  final int indexCount;
  @override
  String get kind => 'bindIndexBuffer';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'buffer': _rangeToJson(buffer),
    'type': indexTypeWire.write(type),
    'indexCount': indexCount,
  };
}

/// `PassEncoder.bindIndexData`: indices built this frame, bound as bytes.
final class TraceBindIndexData extends TracePassEvent {
  /// Records [indexCount] indices of [type] in [bytes] bound in pass [pass].
  const TraceBindIndexData({
    required int pass,
    required this.bytes,
    required this.type,
    required this.indexCount,
  }) : super(pass);

  /// The indices, copied when recorded.
  final ByteData bytes;

  /// The width of each index.
  final IndexType type;

  /// How many indices the binding holds, a count.
  final int indexCount;
  @override
  String get kind => 'bindIndexData';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'bytes': blob.add(bytes),
    'type': indexTypeWire.write(type),
    'indexCount': indexCount,
  };
}

/// `PassEncoder.bindUniformBlock`: a uniform block's members, by name.
final class TraceBindUniformBlock extends TracePassEvent {
  /// Records the block [block] of stage [shader] filled with [members] in pass
  /// [pass].
  const TraceBindUniformBlock({
    required int pass,
    required this.shader,
    required this.block,
    required this.members,
  }) : super(pass);

  /// The stage's name in the loaded libraries.
  final String shader;

  /// The block's name as the stage declares it.
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

/// `PassEncoder.bindTexture`: a texture and sampler bound to a stage's slot.
final class TraceBindTexture extends TracePassEvent {
  /// Records texture id [texture] bound to [slot] of stage [shader] with
  /// [sampler] in pass [pass].
  const TraceBindTexture({
    required int pass,
    required this.shader,
    required this.slot,
    required this.texture,
    this.sampler,
  }) : super(pass);

  /// The stage's name in the loaded libraries.
  final String shader;

  /// The sampled-texture binding's name as the stage declares it.
  final String slot;

  /// The texture's id, among textures.
  final int texture;

  /// How the texture is sampled; null means `SamplerDescriptor.linearRepeat`.
  final SamplerDescriptor? sampler;
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

/// `PassEncoder.clearBindings`: every binding of the pass forgotten.
final class TraceClearBindings extends TracePassEvent {
  /// Records the bindings of pass [pass] cleared.
  const TraceClearBindings(super.pass);
  @override
  String get kind => 'clearBindings';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
  };
}

/// `PassEncoder.draw`: a draw with what is bound.
final class TraceDraw extends TracePassEvent {
  /// Records a draw of [instanceCount] instances over the window of indices
  /// from [firstIndex] in pass [pass].
  const TraceDraw(
    super.pass, {
    this.instanceCount = 1,
    this.firstIndex = 0,
    this.indexCount,
  });

  /// How many instances the draw makes, a count; one by default.
  final int instanceCount;

  /// The window of the bound indices — `P7`. Written only when it is not the
  /// whole binding, so a trace recorded before windows existed reads as it
  /// was recorded and needs no new format version.
  final int firstIndex;

  /// How many indices the window covers, a count; null for the rest of the
  /// binding from [firstIndex].
  final int? indexCount;
  @override
  String get kind => 'draw';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'instanceCount': instanceCount,
    if (firstIndex != 0) 'firstIndex': firstIndex,
    if (indexCount != null) 'indexCount': indexCount,
  };
}

/// `CommandEncoder.submit`: a render pass closed and queued.
final class TraceSubmit extends TracePassEvent {
  /// Records pass [pass] submitted.
  const TraceSubmit(super.pass);
  @override
  String get kind => 'submit';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
  };
}

// --------------------------------------------------------------- compute

/// `GraphicsDevice.createBuffer` for a storage buffer, or the older
/// `createStorageBuffer`: a buffer compute passes read and write.
final class TraceCreateStorageBuffer extends TraceEvent {
  /// Records the storage buffer [id] made holding [bytes].
  const TraceCreateStorageBuffer({
    required this.id,
    required this.bytes,
    required this.hostReadable,
    this.indices,
  });

  /// The id later events name this buffer by, among storage buffers.
  final int id;

  /// The buffer's initial contents, copied when recorded; zeros of the buffer's
  /// length when it was made empty.
  final ByteData bytes;

  /// Whether the buffer may be read back with `GraphicsDevice.readBuffer`.
  final bool hostReadable;

  /// The geometry id its `asIndices` is recorded under, or null when it was
  /// not asked to be bindable as indices — `H11`.
  final int? indices;
  @override
  String get kind => 'createStorageBuffer';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'bytes': blob.add(bytes),
    'hostReadable': hostReadable,
    if (indices != null) 'indices': indices,
  };
}

/// `GraphicsDevice.releaseStorageBuffer`: a storage buffer given back.
final class TraceReleaseStorageBuffer extends TraceEvent {
  /// Records the release of storage buffer id [buffer].
  const TraceReleaseStorageBuffer(this.buffer);

  /// The id of the buffer released, among storage buffers.
  final int buffer;
  @override
  String get kind => 'releaseStorageBuffer';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'buffer': buffer,
  };
}

/// `GraphicsDevice.createComputePipeline`: a pipeline from a compute stage.
final class TraceCreateComputePipeline extends TraceEvent {
  /// Records the compute pipeline [id] built from stage [shader].
  const TraceCreateComputePipeline(this.id, this.shader);

  /// The id later events name this pipeline by, among compute pipelines.
  final int id;

  /// The compute stage's name in the loaded libraries.
  final String shader;
  @override
  String get kind => 'createComputePipeline';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'id': id,
    'shader': shader,
  };
}

/// `GraphicsDevice.beginComputePass`: a compute pass opened.
final class TraceBeginComputePass extends TraceEvent {
  /// Records compute pass [pass] opened with [label].
  const TraceBeginComputePass(this.pass, this.label);

  /// Numbered in the order compute passes were opened; every compute pass event
  /// names it.
  final int pass;

  /// The name given to a debugger and to GPU timings; null for none.
  final String? label;
  @override
  String get kind => 'beginComputePass';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'label': label,
  };
}

/// `ComputeEncoder.bindPipeline`: the pipeline the following dispatches run.
final class TraceComputeBindPipeline extends TraceEvent {
  /// Records compute pipeline id [pipeline] bound in compute pass [pass].
  const TraceComputeBindPipeline(this.pass, this.pipeline);

  /// The compute pass, by the number its `beginComputePass` was recorded under.
  final int pass;

  /// The pipeline's id, among compute pipelines.
  final int pipeline;
  @override
  String get kind => 'computeBindPipeline';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
    'pipeline': pipeline,
  };
}

/// `ComputeEncoder.bindStorageBuffer`: a storage buffer bound to a stage's
/// binding, whole.
final class TraceComputeBindStorageBuffer extends TraceEvent {
  /// Records storage buffer id [buffer] bound to [name] of stage [shader] in
  /// compute pass [pass].
  const TraceComputeBindStorageBuffer({
    required this.pass,
    required this.shader,
    required this.name,
    required this.buffer,
  });

  /// The compute pass, by the number its `beginComputePass` was recorded under.
  final int pass;

  /// The compute stage's name in the loaded libraries.
  final String shader;

  /// The storage binding's name as the stage declares it.
  final String name;

  /// The buffer's id, among storage buffers.
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

/// `ComputeEncoder.bindUniformBlock`: a compute stage's uniform block, by
/// member name.
final class TraceComputeBindUniformBlock extends TraceEvent {
  /// Records the block [block] of stage [shader] filled with [members] in
  /// compute pass [pass].
  const TraceComputeBindUniformBlock({
    required this.pass,
    required this.shader,
    required this.block,
    required this.members,
  });

  /// The compute pass, by the number its `beginComputePass` was recorded under.
  final int pass;

  /// The compute stage's name in the loaded libraries.
  final String shader;

  /// The block's name as the stage declares it.
  final String block;

  /// Each member's floats by name, copied when recorded.
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

/// `ComputeEncoder.dispatch`: the bound pipeline run over a grid of workgroups.
final class TraceDispatch extends TraceEvent {
  /// Records a dispatch of [x] by [y] by [z] workgroups in compute pass [pass].
  const TraceDispatch(this.pass, this.x, this.y, this.z);

  /// The compute pass, by the number its `beginComputePass` was recorded under.
  final int pass;

  /// Workgroups along x, a count.
  final int x;

  /// Workgroups along y, a count; one for a one-dimensional grid.
  final int y;

  /// Workgroups along z, a count; one for a grid of fewer dimensions.
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

/// `ComputeEncoder.submit`: a compute pass closed and queued.
final class TraceComputeSubmit extends TraceEvent {
  /// Records compute pass [pass] submitted.
  const TraceComputeSubmit(this.pass);

  /// The compute pass, by the number its `beginComputePass` was recorded under.
  final int pass;
  @override
  String get kind => 'computeSubmit';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'pass': pass,
  };
}

/// `GraphicsDevice.readBuffer`: a host-readable storage buffer read back.
final class TraceReadBuffer extends TraceEvent {
  /// Records a read of storage buffer id [buffer].
  const TraceReadBuffer(this.buffer);

  /// The buffer's id, among storage buffers.
  final int buffer;
  @override
  String get kind => 'readBuffer';
  @override
  Map<String, Object?> toJson(TraceBlobWriter blob) => <String, Object?>{
    'buffer': buffer,
  };
}
