import 'dart:typed_data';

import '../meshopt/meshopt_index_codec.dart';
import '../meshopt/meshopt_vertex_codec.dart';
import 'gltf_accessor_type.dart';

// `GltfComponentType` and `GltfAccessorType` are self-contained value
// vocabularies with nothing private about them, so they live in their own
// file; re-exported here so every existing import of this file keeps seeing
// them.
export 'gltf_accessor_type.dart';

/// Reads accessors out of the resolved glTF buffers.
///
/// The awkward parts of the format all live here: element stride may be
/// declared on the buffer view rather than implied, integer components may be
/// normalized to floats with a signed-specific rule, sparse accessors patch a
/// subset of elements after the fact, and an accessor may have no buffer view at
/// all (meaning all zeros, which is legal and used by sparse accessors).
final class GltfAccessorReader {
  GltfAccessorReader({
    required Map<String, Object?> json,
    required List<Uint8List> buffers,
  }) : buffers = List.unmodifiable(buffers),
       _accessors = _listOf(json['accessors']),
       _bufferViews = _listOf(json['bufferViews']);

  final List<Map<String, Object?>> _accessors;
  final List<Map<String, Object?>> _bufferViews;

  /// `EXT_meshopt_compression`'s own decoded bytes, by `bufferViews` index —
  /// decompressed once no matter how many accessors (an interleaved vertex
  /// buffer's several attributes, typically) read the same view.
  final Map<int, Uint8List> _decompressed = <int, Uint8List>{};

  /// Buffers already resolved by [GlbContainer.resolveBuffers], indexed the same
  /// way the glTF `buffers` array is.
  final List<Uint8List> buffers;

  /// How many accessors the file declared.
  ///
  /// The loader walks accessors by index from the meshes that name them and
  /// never counts them. It is for a tool that reports what is in a glTF before
  /// anything is decoded — an import dialog, or a check that a file somebody
  /// exported is the shape it was meant to be.
  int get accessorCount => _accessors.length;

  /// Number of elements in an accessor (not components).
  int countOf(int accessorIndex) =>
      _requireInt(_accessor(accessorIndex), 'count', accessorIndex);

  GltfAccessorType typeOf(int accessorIndex) => GltfAccessorType.fromName(
    _requireString(_accessor(accessorIndex), 'type', accessorIndex),
  );

  GltfComponentType componentTypeOf(int accessorIndex) =>
      GltfComponentType.fromCode(
        _requireInt(_accessor(accessorIndex), 'componentType', accessorIndex),
      );

  /// Whether accessors[accessorIndex] names a `bufferView`.
  ///
  /// False is legal on its own — every element then reads as zero, which is
  /// exactly what a sparse accessor's own base is meant to be. It is also
  /// the shape a `KHR_draco_mesh_compression`/`EXT_meshopt_compression`
  /// primitive's fallback accessor takes when an exporter left the real
  /// data in the extension's own buffer and named no fallback at all —
  /// `fmt-15`'s own reason a caller needs to ask this before reading,
  /// rather than reading and getting a silent, degenerate zero mesh back.
  bool hasBufferView(int accessorIndex) =>
      _accessor(accessorIndex)['bufferView'] is int;

  /// Whether reading accessors[accessorIndex] reads *something* — a buffer
  /// view of its own, or data handed to [supplyDecoded].
  bool hasData(int accessorIndex) =>
      _supplied.containsKey(accessorIndex) || hasBufferView(accessorIndex);

  /// The bytes `bufferViews[index]` spans — for an extension that points at a
  /// buffer view directly rather than through an accessor, which is how
  /// `KHR_draco_mesh_compression` names its payload.
  Uint8List bytesOfBufferView(int index) {
    if (index < 0 || index >= _bufferViews.length) {
      throw FormatException('bufferViews[$index] does not exist.');
    }
    final data = _resolveView(index, -1).data;
    return Uint8List.sublistView(data);
  }

  /// Gives accessors[accessorIndex] its elements from outside the buffers.
  ///
  /// **The accessor still says what the data is; this says where it came
  /// from.** `KHR_draco_mesh_compression` leaves a primitive's accessors in
  /// place — count, type, component type, min and max all describe the
  /// *decoded* mesh — and takes away only their buffer views, because the
  /// bytes are inside the compressed payload. Putting the decoded values back
  /// behind the same accessor index is the extension's own model, and it
  /// means nothing downstream — morph targets counting vertices, the writer
  /// reading ranges — needs to know the primitive was ever compressed.
  ///
  /// [integers], when the decoder has them, are the values as stored; they are
  /// what [readAsUint32] returns, and what [readAsFloats] normalizes by the
  /// accessor's own rule — a colour kept as bytes is 255 to Draco and 1.0 to
  /// glTF. [floats] are used as they are. The length is checked against what
  /// the accessor declares, since a decoded mesh with a different vertex count
  /// from the one the file promised would index past the end of something.
  void supplyDecoded(
    int accessorIndex, {
    Float32List? floats,
    List<int>? integers,
  }) {
    final expected =
        countOf(accessorIndex) * typeOf(accessorIndex).componentCount;
    final actual = integers?.length ?? floats?.length;
    if (actual != expected) {
      throw FormatException(
        'accessors[$accessorIndex] declares $expected components and the '
        'decoded data has $actual.',
      );
    }
    _supplied[accessorIndex] = (floats: floats, integers: integers);
  }

  final Map<int, ({Float32List? floats, List<int>? integers})> _supplied =
      <int, ({Float32List? floats, List<int>? integers})>{};

  /// Reads an accessor as floats, applying the normalization rule when set.
  ///
  /// The result is tightly packed: `count * componentCount` floats.
  Float32List readAsFloats(int accessorIndex) {
    final accessor = _accessor(accessorIndex);
    final type = typeOf(accessorIndex);
    final componentType = componentTypeOf(accessorIndex);
    final count = countOf(accessorIndex);
    final normalized = accessor['normalized'] == true;
    final components = type.componentCount;

    // Supplied data first. Floats are what a float accessor wants; an integer
    // accessor wants the integers, read by its own normalization rule.
    final supplied = _supplied[accessorIndex];
    if (supplied != null) {
      return switch (supplied) {
        (:final floats?, integers: _)
            when componentType == GltfComponentType.float =>
          floats,
        (floats: _, :final integers?) => Float32List.fromList(<double>[
          for (final v in integers)
            normalized ? componentType.normalize(v) : v.toDouble(),
        ]),
        (:final floats?, integers: null) => floats,
        (floats: null, integers: null) => throw FormatException(
          'accessors[$accessorIndex] was supplied no data.',
        ),
      };
    }

    final out = Float32List(count * components);
    _forEachElement(accessorIndex, (elementIndex, data, byteOffset) {
      for (var c = 0; c < components; c++) {
        final offset = byteOffset + c * componentType.sizeInBytes;
        out[elementIndex * components + c] = componentType.readDouble(
          data,
          offset,
          normalized: normalized,
        );
      }
    });
    return out;
  }

  /// Reads an accessor as unsigned integers, for indices and joint references.
  Uint32List readAsUint32(int accessorIndex) {
    final type = typeOf(accessorIndex);
    final componentType = componentTypeOf(accessorIndex);
    final count = countOf(accessorIndex);
    final components = type.componentCount;

    if (componentType == GltfComponentType.float) {
      throw FormatException(
        'accessors[$accessorIndex] is float but was read as integers.',
      );
    }

    final supplied = _supplied[accessorIndex];
    if (supplied != null) {
      return Uint32List.fromList(
        supplied.integers ??
            <int>[for (final v in supplied.floats ?? Float32List(0)) v.round()],
      );
    }

    final out = Uint32List(count * components);
    _forEachElement(accessorIndex, (elementIndex, data, byteOffset) {
      for (var c = 0; c < components; c++) {
        final offset = byteOffset + c * componentType.sizeInBytes;
        out[elementIndex * components + c] = componentType.readInt(
          data,
          offset,
        );
      }
    });
    return out;
  }

  /// Walks the elements of an accessor, handling stride, the missing-buffer-view
  /// case and the sparse override.
  void _forEachElement(
    int accessorIndex,
    void Function(int elementIndex, ByteData data, int byteOffset) visit,
  ) {
    final accessor = _accessor(accessorIndex);
    final type = typeOf(accessorIndex);
    final componentType = componentTypeOf(accessorIndex);
    final count = countOf(accessorIndex);
    final elementSize = type.componentCount * componentType.sizeInBytes;

    final bufferViewIndex = accessor['bufferView'];
    if (bufferViewIndex is int) {
      final view = _resolveView(bufferViewIndex, accessorIndex);
      final accessorOffset = _optionalInt(accessor, 'byteOffset') ?? 0;
      // A declared byteStride means the data is interleaved with other
      // attributes; without one, elements are tightly packed.
      final stride = view.byteStride ?? elementSize;
      if (accessorOffset < 0 || count < 0 || stride < elementSize) {
        throw FormatException(
          'accessors[$accessorIndex] has byteOffset $accessorOffset, count '
          '$count and a stride of $stride for $elementSize-byte elements.',
        );
      }

      final available = view.data.lengthInBytes - accessorOffset;
      final needed = count == 0 ? 0 : (count - 1) * stride + elementSize;
      if (needed > available) {
        throw FormatException(
          'accessors[$accessorIndex] needs $needed bytes at offset '
          '$accessorOffset but bufferViews[$bufferViewIndex] only provides '
          '$available.',
        );
      }

      for (var i = 0; i < count; i++) {
        visit(i, view.data, accessorOffset + i * stride);
      }
    }
    // No bufferView: every element reads as zero, which is what the spec
    // prescribes and what a sparse accessor builds on. visit() is simply not
    // called, leaving the caller's zero-initialized output alone.

    _applySparse(accessorIndex, accessor, type, componentType, visit);
  }

  void _applySparse(
    int accessorIndex,
    Map<String, Object?> accessor,
    GltfAccessorType type,
    GltfComponentType componentType,
    void Function(int elementIndex, ByteData data, int byteOffset) visit,
  ) {
    final sparse = accessor['sparse'];
    if (sparse is! Map) return;

    final sparseCount = _requireInt(
      sparse.cast<String, Object?>(),
      'count',
      accessorIndex,
    );
    final indices = sparse['indices'];
    final values = sparse['values'];
    if (indices is! Map || values is! Map) {
      throw FormatException(
        'accessors[$accessorIndex].sparse needs both indices and values.',
      );
    }

    final indexView = _resolveView(
      _requireInt(indices.cast<String, Object?>(), 'bufferView', accessorIndex),
      accessorIndex,
    );
    final indexOffset =
        _optionalInt(indices.cast<String, Object?>(), 'byteOffset') ?? 0;
    final indexComponent = GltfComponentType.fromCode(
      _requireInt(
        indices.cast<String, Object?>(),
        'componentType',
        accessorIndex,
      ),
    );

    final valueView = _resolveView(
      _requireInt(values.cast<String, Object?>(), 'bufferView', accessorIndex),
      accessorIndex,
    );
    final valueOffset =
        _optionalInt(values.cast<String, Object?>(), 'byteOffset') ?? 0;
    final elementSize = type.componentCount * componentType.sizeInBytes;

    // Both runs are read by position, so both have to hold `count` entries;
    // and every index names an element the caller allocated room for.
    final count = countOf(accessorIndex);
    if (sparseCount < 0 ||
        indexOffset < 0 ||
        valueOffset < 0 ||
        indexOffset + sparseCount * indexComponent.sizeInBytes >
            indexView.data.lengthInBytes ||
        valueOffset + sparseCount * elementSize >
            valueView.data.lengthInBytes) {
      throw FormatException(
        'accessors[$accessorIndex].sparse names $sparseCount entries, more '
        'than its indices or values buffer views hold.',
      );
    }

    for (var i = 0; i < sparseCount; i++) {
      final target = indexComponent.readInt(
        indexView.data,
        indexOffset + i * indexComponent.sizeInBytes,
      );
      if (target < 0 || target >= count) {
        throw FormatException(
          'accessors[$accessorIndex].sparse replaces element $target of '
          '$count.',
        );
      }
      visit(target, valueView.data, valueOffset + i * elementSize);
    }
  }

  _ResolvedView _resolveView(int index, int accessorIndex) {
    if (index < 0 || index >= _bufferViews.length) {
      throw FormatException(
        'accessors[$accessorIndex] references bufferViews[$index], which does '
        'not exist.',
      );
    }
    final view = _bufferViews[index];

    final extensions = view['extensions'];
    final compression = extensions is Map
        ? extensions['EXT_meshopt_compression']
        : null;
    if (compression is Map) {
      final compressionMap = compression.cast<String, Object?>();
      final decoded = _decompressed.putIfAbsent(
        index,
        () => _decodeMeshopt(compressionMap, index),
      );
      return _ResolvedView(
        data: ByteData.sublistView(decoded),
        byteStride: _optionalInt(compressionMap, 'byteStride'),
      );
    }

    final bufferIndex = _requireInt(view, 'buffer', index);
    if (bufferIndex < 0 || bufferIndex >= buffers.length) {
      throw FormatException(
        'bufferViews[$index] references buffers[$bufferIndex], which was not '
        'resolved.',
      );
    }
    final buffer = buffers[bufferIndex];
    final byteOffset = _optionalInt(view, 'byteOffset') ?? 0;
    final byteLength = _requireInt(view, 'byteLength', index);

    if (byteOffset < 0 ||
        byteLength < 0 ||
        byteOffset + byteLength > buffer.length) {
      throw FormatException(
        'bufferViews[$index] spans ${byteOffset + byteLength} bytes but '
        'buffers[$bufferIndex] holds only ${buffer.length}.',
      );
    }

    return _ResolvedView(
      data: ByteData.sublistView(buffer, byteOffset, byteOffset + byteLength),
      byteStride: _optionalInt(view, 'byteStride'),
    );
  }

  /// [compression] is `bufferViews[bufferViewIndex]`'s own
  /// `extensions.EXT_meshopt_compression` object — `buffer`/`byteOffset`/
  /// `byteLength` name where the *compressed* bytes actually live (not the
  /// outer view, which this writer never gives a fallback of its own —
  /// `fmt-30n`'s own row), and `mode`/`count`/`byteStride` say how to read
  /// them back. A `filter` other than `NONE` is refused by name: this
  /// package's own writer never requests one, and decoding a filtered view
  /// without undoing the filter's octahedral/quaternion/exponential/colour
  /// math would hand back bytes that read as plausible, wrong numbers.
  Uint8List _decodeMeshopt(Map<String, Object?> compression, int viewIndex) {
    final filter = compression['filter'] ?? 'NONE';
    if (filter != 'NONE') {
      throw FormatException(
        'bufferViews[$viewIndex]\'s EXT_meshopt_compression names filter '
        '"$filter", which this reader does not undo (only NONE).',
      );
    }
    final bufferIndex = _requireInt(compression, 'buffer', viewIndex);
    if (bufferIndex < 0 || bufferIndex >= buffers.length) {
      throw FormatException(
        'bufferViews[$viewIndex]\'s EXT_meshopt_compression references '
        'buffers[$bufferIndex], which was not resolved.',
      );
    }
    final buffer = buffers[bufferIndex];
    final byteOffset = _optionalInt(compression, 'byteOffset') ?? 0;
    final byteLength = _requireInt(compression, 'byteLength', viewIndex);
    final count = _requireInt(compression, 'count', viewIndex);
    final byteStride = _optionalInt(compression, 'byteStride') ?? 0;
    final mode = compression['mode'] as String?;

    if (byteOffset < 0 ||
        byteLength < 0 ||
        count < 0 ||
        byteOffset + byteLength > buffer.length) {
      throw FormatException(
        'bufferViews[$viewIndex]\'s EXT_meshopt_compression spans '
        '${byteOffset + byteLength} bytes but buffers[$bufferIndex] holds '
        'only ${buffer.length}.',
      );
    }
    final compressed = Uint8List.sublistView(
      buffer,
      byteOffset,
      byteOffset + byteLength,
    );

    return switch (mode) {
      // The codec's own decoder always answers in 32-bit indices;
      // `byteStride` is the extension's own name for the size an index
      // *accessor* actually reads (2 or 4) — `_narrowIndices` repacks into
      // that width, the same distinction `_forEachElement` already draws
      // between `componentType.sizeInBytes` and what a producer chose to
      // store.
      'TRIANGLES' => _narrowIndices(
        decodeMeshoptIndexBuffer(compressed, count),
        byteStride,
        viewIndex,
      ),
      // The extension's own bound on an attribute stride, and the one the
      // codec's block size is derived from: past 256 bytes the block holds
      // no elements at all.
      'ATTRIBUTES'
          when byteStride < 4 || byteStride > 256 || byteStride % 4 != 0 =>
        throw FormatException(
          'bufferViews[$viewIndex]\'s EXT_meshopt_compression names an '
          'ATTRIBUTES byteStride of $byteStride; it must be a multiple of 4 '
          'from 4 to 256.',
        ),
      'ATTRIBUTES' => decodeMeshoptVertexBufferV0(
        compressed,
        count,
        byteStride,
      ),
      _ => throw FormatException(
        'bufferViews[$viewIndex]\'s EXT_meshopt_compression names mode '
        '"$mode", which this reader does not decode (only ATTRIBUTES and '
        'TRIANGLES).',
      ),
    };
  }

  static Uint8List _narrowIndices(
    Uint32List indices,
    int byteStride,
    int viewIndex,
  ) {
    switch (byteStride) {
      case 4:
        return indices.buffer.asUint8List(
          indices.offsetInBytes,
          indices.lengthInBytes,
        );
      case 2:
        final narrow = Uint16List(indices.length);
        for (var i = 0; i < indices.length; i++) {
          narrow[i] = indices[i];
        }
        return narrow.buffer.asUint8List();
      default:
        throw FormatException(
          'bufferViews[$viewIndex]\'s EXT_meshopt_compression names a '
          'TRIANGLES byteStride of $byteStride, and an index is 2 or 4 '
          'bytes.',
        );
    }
  }

  Map<String, Object?> _accessor(int index) {
    if (index < 0 || index >= _accessors.length) {
      throw FormatException('accessors[$index] does not exist.');
    }
    return _accessors[index];
  }
}

final class _ResolvedView {
  const _ResolvedView({required this.data, required this.byteStride});

  final ByteData data;
  final int? byteStride;
}

List<Map<String, Object?>> _listOf(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final item in value)
      if (item is Map) item.cast<String, Object?>() else <String, Object?>{},
  ];
}

int _requireInt(Map<String, Object?> map, String key, int index) {
  final value = map[key];
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  throw FormatException('Entry $index is missing required int "$key".');
}

String _requireString(Map<String, Object?> map, String key, int index) {
  final value = map[key];
  if (value is String) return value;
  throw FormatException('Entry $index is missing required string "$key".');
}

int? _optionalInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  return null;
}
