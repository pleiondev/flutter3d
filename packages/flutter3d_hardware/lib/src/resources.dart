/// The resource vocabulary of the 1.0 contract: texture shapes and usages,
/// general buffers and how they are mapped, query sets, indexed draws, render
/// bundles, and the small value types the pass state takes.
///
/// **Added to make the contract whole, not because a pass of this engine
/// asked.** The rule at the top of `command_encoder.dart` — every member has
/// a caller — built the pre-1.0 interface; the 1.0 one is held to a different
/// rule: everything WebGPU or WebGL2 can do is expressible, so a backend that
/// gains a capability changes and the API does not. Each piece is gated by a
/// `DeviceFeature`, and a backend without it refuses by name. Value types are
/// descriptors with optional fields, so a later minor release can add a field
/// without breaking a caller.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'capabilities.dart';
import 'formats.dart';
import 'graphics_device.dart';

/// The shape of a texture, as a view of it is bound.
///
/// WebGPU's view dimensions. Separate from [TextureType], which mirrors
/// flutter_gpu value for value and so cannot grow a value flutter_gpu does not
/// have.
enum TextureDimension {
  /// One row of texels.
  ///
  /// Gated by `DeviceFeature.textureWrites` alone in 1.0, with no feature of
  /// its own: WebGPU has it and WebGL2 does not, and a backend without it
  /// refuses the descriptor with an [UnsupportedError] naming the dimension.
  /// A `texture-1d` feature can be added later without breaking anything.
  d1,

  /// A plain 2D image — what every texture before 0.9 was, cubes aside.
  d2,

  /// Several 2D images of one size, addressed by layer.
  d2Array,

  /// A volume of texels.
  d3,

  /// Six square faces sampled by direction.
  cube,

  /// Several cubes, addressed by cube index.
  cubeArray,
}

/// What a texture may be used for, fixed when it is made.
///
/// Flags combined with `|`. A final class rather than an enum, because a set
/// of usages is a value and an enum value is one usage.
@immutable
final class TextureUsage {
  const TextureUsage._(this.bits);

  final int bits;

  /// Bound to a stage and sampled.
  static const TextureUsage sampled = TextureUsage._(1);

  /// A colour or depth attachment of a pass.
  static const TextureUsage renderTarget = TextureUsage._(2);

  /// Bound as a storage texture —
  /// `DeviceFeature.storageTextures`.
  static const TextureUsage storage = TextureUsage._(4);

  /// The source of a copy, or of a readback.
  static const TextureUsage copySource = TextureUsage._(8);

  /// The destination of a copy or a write.
  static const TextureUsage copyDestination = TextureUsage._(16);

  /// Sampled, drawn into and copied either way: what a texture made by
  /// `createTexture` has always been.
  static const TextureUsage standard = TextureUsage._(1 | 2 | 8 | 16);

  TextureUsage operator |(TextureUsage other) =>
      TextureUsage._(bits | other.bits);

  /// Whether every usage in [other] is in this one.
  bool contains(TextureUsage other) => bits & other.bits == other.bits;

  @override
  bool operator ==(Object other) => other is TextureUsage && other.bits == bits;

  @override
  int get hashCode => bits.hashCode;

  @override
  String toString() =>
      'TextureUsage(${<String>[if (contains(sampled)) 'sampled', if (contains(renderTarget)) 'renderTarget', if (contains(storage)) 'storage', if (contains(copySource)) 'copySource', if (contains(copyDestination)) 'copyDestination'].join(' | ')})';
}

/// Everything a texture is made from — `TextureAllocator.createTexture`.
///
/// The general form of the four creators the contract had before 0.9, which
/// each made one shape: a 2D target, a 2D upload, a cube upload and a cube
/// target. [dimension] picks the shape; [depthOrArrayLayers] is the layer
/// count of an array (six per cube of a cube array, and six for a cube) or
/// the depth of a 3D texture.
///
/// **Extended by `RenderTargetDescriptor`**, the 2D target the render target
/// pool keys on, which is why this is a `base` class: `createTexture` takes
/// either, and a pool's target is one shape of this.
@immutable
base class TextureDescriptor {
  const TextureDescriptor({
    required this.width,
    required this.height,
    required this.format,
    this.dimension = TextureDimension.d2,
    this.depthOrArrayLayers = 1,
    this.mipLevelCount = 1,
    this.sampleCount = 1,
    this.usage = TextureUsage.standard,
    this.storageMode = StorageMode.devicePrivate,
    this.label,
  }) : assert(width > 0 && height > 0, 'a texture has at least one texel'),
       assert(depthOrArrayLayers > 0, 'a texture has at least one layer'),
       assert(mipLevelCount > 0, 'a texture has at least its base level'),
       assert(sampleCount > 0, 'a texture has at least one sample');

  final int width;
  final int height;
  final TextureFormat format;
  final TextureDimension dimension;

  /// Layers of an array or cube (a multiple of six for cubes), or depth of a
  /// 3D texture. One otherwise.
  final int depthOrArrayLayers;

  /// Levels counting the base.
  final int mipLevelCount;

  /// Above one makes a multisampled texture, which is 2D with one level.
  final int sampleCount;
  final TextureUsage usage;
  final StorageMode storageMode;

  /// What a GPU debugger calls it.
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is TextureDescriptor &&
      other.runtimeType == runtimeType &&
      other.width == width &&
      other.height == height &&
      other.format == format &&
      other.dimension == dimension &&
      other.depthOrArrayLayers == depthOrArrayLayers &&
      other.mipLevelCount == mipLevelCount &&
      other.sampleCount == sampleCount &&
      other.usage == usage &&
      other.storageMode == storageMode &&
      other.label == label;

  @override
  int get hashCode => Object.hash(
    width,
    height,
    format,
    dimension,
    depthOrArrayLayers,
    mipLevelCount,
    sampleCount,
    usage,
    storageMode,
    label,
  );

  @override
  String toString() =>
      'TextureDescriptor(${width}x${height}x$depthOrArrayLayers '
      '${dimension.name}, ${format.name}, $mipLevelCount levels, '
      'x$sampleCount, $usage)';
}

/// A box of texels in one mip level: a rectangle of [width] by [height] from
/// ([x], [y]) at the top left, across [depthOrArrayLayers] layers (or 3D
/// slices) from [z].
@immutable
final class TextureRegion {
  const TextureRegion({
    this.x = 0,
    this.y = 0,
    this.z = 0,
    required this.width,
    required this.height,
    this.depthOrArrayLayers = 1,
  });

  final int x;
  final int y;

  /// The first layer, cube face (layer index × 6 + face in a cube array) or
  /// 3D slice.
  final int z;
  final int width;
  final int height;
  final int depthOrArrayLayers;

  @override
  bool operator ==(Object other) =>
      other is TextureRegion &&
      other.x == x &&
      other.y == y &&
      other.z == z &&
      other.width == width &&
      other.height == height &&
      other.depthOrArrayLayers == depthOrArrayLayers;

  @override
  int get hashCode => Object.hash(x, y, z, width, height, depthOrArrayLayers);

  @override
  String toString() =>
      'TextureRegion($x, $y, $z, ${width}x${height}x$depthOrArrayLayers)';
}

/// How texel rows sit in a buffer on either side of a buffer–texture copy.
@immutable
final class BufferTextureLayout {
  const BufferTextureLayout({
    this.offsetInBytes = 0,
    required this.bytesPerRow,
    this.rowsPerImage,
  });

  final int offsetInBytes;

  /// Bytes from one row to the next. WebGPU requires a multiple of 256 for a
  /// copy encoded on the GPU; a backend that needs that says so by refusing.
  final int bytesPerRow;

  /// Rows from one layer to the next; null means the copy's height.
  final int? rowsPerImage;
}

/// What a general buffer may be used for, fixed when it is made.
///
/// **A promise the caller makes, which a backend may hold it to.** Every
/// backend checks the usages a call needs where its API would otherwise fail
/// late — mapping needs [hostReadable] or [hostWritable], an indirect draw
/// [indirect] — and refuses with an [ArgumentError]. A backend whose API does
/// not care (WebGL2 copies any buffer) need not check the copy usages; a
/// caller that relies on that is relying on one backend.
@immutable
final class BufferUsage {
  const BufferUsage._(this.bits);

  final int bits;

  static const BufferUsage vertex = BufferUsage._(1);

  /// Holds indices. A backend may refuse [index] combined with [vertex] or
  /// [uniform] with an [ArgumentError]: WebGL2 binds a buffer to the element
  /// array target for its life and cannot bind it anywhere else.
  static const BufferUsage index = BufferUsage._(2);
  static const BufferUsage uniform = BufferUsage._(4);

  /// Needs `DeviceFeature.compute` or `DeviceFeature.renderStageStorage`.
  static const BufferUsage storage = BufferUsage._(8);

  /// Holds the arguments of an indirect draw or dispatch.
  static const BufferUsage indirect = BufferUsage._(16);
  static const BufferUsage copySource = BufferUsage._(32);
  static const BufferUsage copyDestination = BufferUsage._(64);

  /// `GraphicsDevice.readBuffer` may read it back — what
  /// `StorageBuffer.hostReadable` records.
  ///
  /// WebGPU's `MAP_READ`: also what lets `GraphicsDevice.mapBuffer` map it
  /// with [MapMode.read], and `readBufferSync` read it where the device can.
  static const BufferUsage hostReadable = BufferUsage._(128);

  /// `GraphicsDevice.mapBuffer` may map it with [MapMode.write] — a staging
  /// buffer the host fills and a transfer pass copies onward. WebGPU's
  /// `MAP_WRITE`.
  static const BufferUsage hostWritable = BufferUsage._(256);

  /// What `createStorageBuffer` has always made: storage, copied either way.
  static const BufferUsage standardStorage = BufferUsage._(8 | 32 | 64);

  BufferUsage operator |(BufferUsage other) => BufferUsage._(bits | other.bits);

  /// Whether every usage in [other] is in this one.
  bool contains(BufferUsage other) => bits & other.bits == other.bits;

  @override
  bool operator ==(Object other) => other is BufferUsage && other.bits == bits;

  @override
  int get hashCode => bits.hashCode;

  @override
  String toString() =>
      'BufferUsage(${<String>[if (contains(vertex)) 'vertex', if (contains(index)) 'index', if (contains(uniform)) 'uniform', if (contains(storage)) 'storage', if (contains(indirect)) 'indirect', if (contains(copySource)) 'copySource', if (contains(copyDestination)) 'copyDestination', if (contains(hostReadable)) 'hostReadable', if (contains(hostWritable)) 'hostWritable'].join(' | ')})';
}

/// A general buffer — `GraphicsDevice.createBuffer`.
@immutable
final class BufferDescriptor {
  const BufferDescriptor({
    required this.lengthInBytes,
    required this.usage,
    this.label,
  }) : assert(lengthInBytes >= 0, 'a buffer is not negatively long');

  final int lengthInBytes;
  final BufferUsage usage;
  final String? label;
}

/// What a query set counts.
final class QueryType {
  const QueryType._(this.index, this.name, this.feature);

  /// The capability a set of these queries needs.
  final DeviceFeature feature;

  /// Samples that passed the depth and stencil tests between
  /// `PassEncoder.beginOcclusionQuery` and `endOcclusionQuery`. Zero means
  /// nothing was visible; any other number is only "something was".
  static const QueryType occlusion = QueryType._(
    0,
    'occlusion',
    DeviceFeature.occlusionQuery,
  );

  /// GPU time in nanoseconds, written at the start and end of a pass.
  static const QueryType timestamp = QueryType._(
    1,
    'timestamp',
    DeviceFeature.timestampQuery,
  );

  /// The five counters [PipelineStatistic] names, between
  /// `beginPipelineStatisticsQuery` and its end. A query occupies five
  /// consecutive results. `DeviceFeature.pipelineStatisticsQuery`.
  static const QueryType pipelineStatistics = QueryType._(
    2,
    'pipelineStatistics',
    DeviceFeature.pipelineStatisticsQuery,
  );

  /// Every value this version names, in the order of [index].
  static const List<QueryType> values = <QueryType>[
    occlusion,
    timestamp,
    pipelineStatistics,
  ];

  /// The value whose [name] is [wireName], or null when this version names
  /// none (absent) — how a file that names a value is read.
  static QueryType? byName(String wireName) {
    for (final value in values) {
      if (value.name == wireName) return value;
    }
    return null;
  }

  /// The position in [values]: stable within a major, appended only.
  final int index;

  /// The stable name, and the wire name: what a file, a report or a
  /// snapshot writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'QueryType.$name';
}

/// The counters a [QueryType.pipelineStatistics] query reports, in the
/// order its five results come back.
enum PipelineStatistic {
  vertexShaderInvocations,
  clipperInvocations,
  clipperPrimitivesOut,
  fragmentShaderInvocations,
  computeShaderInvocations,
}

/// How a buffer is mapped into host memory — `GraphicsDevice.mapBuffer`.
enum MapMode {
  /// The host reads what the GPU wrote. Needs [BufferUsage.hostReadable].
  read,

  /// The host writes what the GPU will read. Needs
  /// [BufferUsage.hostWritable].
  ///
  /// **The mapped bytes start undefined.** A backend that maps the buffer
  /// itself hands back what it holds; one that stages the write (WebGPU,
  /// whose map-write buffers can only be copy sources) hands back zeros and
  /// writes the range on unmap. A caller writes every byte of the range it
  /// means, and reads nothing it did not write.
  write,
}

/// A range of a buffer mapped into host memory.
///
/// **Valid until [unmap], and only until then.** [bytes] is the mapping
/// itself where the backend can hand one out (WebGPU's mapped range) and a
/// copy where it cannot; either way, reading or writing it after [unmap] is
/// undefined, and a write is only seen by the GPU after [unmap]. A buffer
/// stays unusable by any pass while mapped, on every backend, so a caller
/// that forgets to unmap finds out at the next submit rather than never.
///
/// **Implementable outside this package, and stays so through 1.x.** It does
/// not grow within a major: a capability added later arrives beside it — a
/// second interface an implementation opts into, or a member with a default
/// on a base class — so an implementation written against 1.0 keeps
/// compiling.
abstract base class MappedBuffer {
  /// The mapped range.
  ByteData get bytes;

  /// Hands the range back. For [MapMode.write], this is when the bytes
  /// reach the buffer.
  void unmap();
}

/// One indexed draw with every argument: a window of the bound indices,
/// a base vertex added to each, and an instance range.
///
/// What `PassEncoder.drawIndexed` and `PassEncoder.multiDraw` take, and the
/// shape `drawIndexedIndirectArguments` encodes. A value with optional fields
/// so a later field is not a breaking change.
@immutable
final class IndexedDraw {
  const IndexedDraw({
    this.indexCount,
    this.firstIndex = 0,
    this.baseVertex = 0,
    this.instanceCount = 1,
    this.firstInstance = 0,
  });

  /// Null reads to the end of the binding.
  final int? indexCount;
  final int firstIndex;
  final int baseVertex;
  final int instanceCount;
  final int firstInstance;

  /// Whether this needs `DeviceFeature.baseVertexBaseInstance`.
  bool get usesBaseVertexOrInstance => baseVertex != 0 || firstInstance != 0;

  @override
  bool operator ==(Object other) =>
      other is IndexedDraw &&
      other.indexCount == indexCount &&
      other.firstIndex == firstIndex &&
      other.baseVertex == baseVertex &&
      other.instanceCount == instanceCount &&
      other.firstInstance == firstInstance;

  @override
  int get hashCode => Object.hash(
    indexCount,
    firstIndex,
    baseVertex,
    instanceCount,
    firstInstance,
  );

  @override
  String toString() =>
      'IndexedDraw(${indexCount ?? 'all'} from $firstIndex, base $baseVertex, '
      '$instanceCount from $firstInstance)';
}

/// The attachments a render bundle will be replayed against —
/// `GraphicsDevice.createRenderBundleEncoder`.
@immutable
final class RenderBundleDescriptor {
  const RenderBundleDescriptor({
    required this.colorFormats,
    this.depthStencilFormat,
    this.sampleCount = 1,
    this.label,
  });

  /// One per colour attachment, in order.
  final List<TextureFormat> colorFormats;

  /// Null for a pass with no depth attachment.
  final TextureFormat? depthStencilFormat;
  final int sampleCount;
  final String? label;
}

/// Draws recorded once and replayed into passes — `PassEncoder.executeBundles`.
final class RenderBundle {
  RenderBundle._(
    this._release, {
    required this.backend,
    required this.descriptor,
    this.label,
  });

  final void Function(RenderBundle)? _release;

  /// Gives this back to the device that made it, once: what `dispose` means
  /// on every handle. A second call does nothing. A handle a backend made
  /// without naming its device (a test's fake) has nothing to give back.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _release?.call(this);
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  /// The backend's own object, as `TextureHandle.backend`.
  final Object backend;

  /// What it was recorded against; a pass replaying it must match.
  final RenderBundleDescriptor descriptor;
  final String? label;

  @override
  String toString() => 'RenderBundle(${label ?? 'unnamed'})';
}

/// A set of queries a backend owns — `GraphicsDevice.createQuerySet`.
final class QuerySet {
  QuerySet._(
    this._release, {
    required this.backend,
    required this.type,
    required this.count,
  });

  final void Function(QuerySet)? _release;

  /// Gives this back to the device that made it, once: what `dispose` means
  /// on every handle. A second call does nothing. A handle a backend made
  /// without naming its device (a test's fake) has nothing to give back.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _release?.call(this);
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  /// The backend's own object, as `TextureHandle.backend`.
  final Object backend;
  final QueryType type;
  final int count;

  @override
  String toString() => 'QuerySet(${type.name} x$count)';
}

/// Where a pass writes its start and end timestamps.
@immutable
final class PassTimestampWrites {
  const PassTimestampWrites({
    required this.querySet,
    this.beginningOfPassIndex,
    this.endOfPassIndex,
  });

  /// A [QueryType.timestamp] set.
  final QuerySet querySet;
  final int? beginningOfPassIndex;
  final int? endOfPassIndex;
}

/// How a compute or render stage may touch a storage texture.
enum StorageTextureAccess {
  writeOnly,
  readOnly,

  /// Needs `DeviceFeature.readWriteStorageTextures`.
  readWrite,
}

/// Which channels of a colour attachment a draw may change.
@immutable
final class ColorWriteMask {
  const ColorWriteMask._(this.bits);

  final int bits;

  static const ColorWriteMask none = ColorWriteMask._(0);
  static const ColorWriteMask red = ColorWriteMask._(1);
  static const ColorWriteMask green = ColorWriteMask._(2);
  static const ColorWriteMask blue = ColorWriteMask._(4);
  static const ColorWriteMask alpha = ColorWriteMask._(8);

  /// Every channel: what every pass starts with.
  static const ColorWriteMask all = ColorWriteMask._(15);

  ColorWriteMask operator |(ColorWriteMask other) =>
      ColorWriteMask._(bits | other.bits);

  bool get writesRed => bits & 1 != 0;
  bool get writesGreen => bits & 2 != 0;
  bool get writesBlue => bits & 4 != 0;
  bool get writesAlpha => bits & 8 != 0;

  @override
  bool operator ==(Object other) =>
      other is ColorWriteMask && other.bits == bits;

  @override
  int get hashCode => bits.hashCode;

  @override
  String toString() =>
      'ColorWriteMask(${writesRed ? 'r' : ''}'
      '${writesGreen ? 'g' : ''}${writesBlue ? 'b' : ''}'
      '${writesAlpha ? 'a' : ''})';
}

/// A depth offset applied to the draws that follow — what keeps a shadow
/// caster from shadowing itself.
///
/// Depth written is `depth + constant·r + slopeScale·maxSlope`, clamped to
/// [clamp] when it is not zero; `r` is the smallest step the depth format
/// resolves. WebGPU's `depthBias`, `depthBiasSlopeScale`, `depthBiasClamp`.
@immutable
final class DepthBias {
  const DepthBias({this.constant = 0, this.slopeScale = 0, this.clamp = 0});

  /// None: what every pass starts with.
  static const DepthBias none = DepthBias();

  final int constant;

  /// A unitless multiplier on the depth's largest slope across the
  /// primitive.
  final double slopeScale;

  /// The largest offset, in depth from 0 to 1 (unitless), or zero for none. A non-zero clamp is not a
  /// feature of its own in 1.0: WebGL2's `polygonOffset` has no clamp, and a
  /// backend that cannot honour one refuses it with an [UnsupportedError]
  /// naming the clamp rather than drawing unclamped.
  final double clamp;

  @override
  bool operator ==(Object other) =>
      other is DepthBias &&
      other.constant == constant &&
      other.slopeScale == slopeScale &&
      other.clamp == clamp;

  @override
  int get hashCode => Object.hash(constant, slopeScale, clamp);

  @override
  String toString() => 'DepthBias($constant, slope $slopeScale, clamp $clamp)';
}

/// The bytes an indexed indirect draw reads: five little-endian 32-bit
/// words — index count, instance count, first index, base vertex, first
/// instance. Twenty bytes; WebGPU's and every native API's layout.
ByteData drawIndexedIndirectArguments({
  required int indexCount,
  int instanceCount = 1,
  int firstIndex = 0,
  int baseVertex = 0,
  int firstInstance = 0,
}) => ByteData(20)
  ..setUint32(0, indexCount, Endian.little)
  ..setUint32(4, instanceCount, Endian.little)
  ..setUint32(8, firstIndex, Endian.little)
  ..setInt32(12, baseVertex, Endian.little)
  ..setUint32(16, firstInstance, Endian.little);

/// The bytes an indirect dispatch reads: three little-endian 32-bit words,
/// the workgroup grid. Twelve bytes.
ByteData dispatchIndirectArguments(int x, [int y = 1, int z = 1]) =>
    ByteData(12)
      ..setUint32(0, x, Endian.little)
      ..setUint32(4, y, Endian.little)
      ..setUint32(8, z, Endian.little);

/// A [RenderBundle] over a backend's own recorded [backend] bundle, for a
/// backend's `RenderBundleEncoder.finish`, from
/// `package:flutter3d_hardware/backend.dart`. [owner]'s `releaseRenderBundle`
/// is what the handle's `dispose` calls.
RenderBundle wrapRenderBundle({
  required Object backend,
  required RenderBundleDescriptor descriptor,
  String? label,
  GraphicsDevice? owner,
}) => RenderBundle._(
  owner?.releaseRenderBundle,
  backend: backend,
  descriptor: descriptor,
  label: label,
);

/// A [QuerySet] over a backend's own [backend] query set, for a backend.
/// [owner]'s `releaseQuerySet` is what the handle's `dispose` calls.
QuerySet wrapQuerySet({
  required Object backend,
  required QueryType type,
  required int count,
  GraphicsDevice? owner,
}) => QuerySet._(
  owner?.releaseQuerySet,
  backend: backend,
  type: type,
  count: count,
);
