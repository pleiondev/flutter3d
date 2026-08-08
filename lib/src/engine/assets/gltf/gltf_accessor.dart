import 'dart:typed_data';

/// glTF `componentType` values.
///
/// Reading lives on the enum rather than in static helpers on the reader: the
/// rules — element size, and the asymmetric normalization of signed types — are
/// properties of the component type itself, so this is where they belong.
enum GltfComponentType {
  byte(5120, 1),
  unsignedByte(5121, 1),
  short(5122, 2),
  unsignedShort(5123, 2),
  unsignedInt(5125, 4),
  float(5126, 4);

  const GltfComponentType(this.code, this.sizeInBytes);

  final int code;
  final int sizeInBytes;

  static GltfComponentType fromCode(int code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw FormatException('Unknown glTF componentType $code.');
  }

  /// Reads one component as a double, applying the normalization rule when asked.
  double readDouble(ByteData data, int offset, {bool normalized = false}) {
    switch (this) {
      case GltfComponentType.float:
        return data.getFloat32(offset, Endian.little);
      case GltfComponentType.unsignedByte:
        final v = data.getUint8(offset);
        return normalized ? v / 255.0 : v.toDouble();
      case GltfComponentType.unsignedShort:
        final v = data.getUint16(offset, Endian.little);
        return normalized ? v / 65535.0 : v.toDouble();
      case GltfComponentType.unsignedInt:
        final v = data.getUint32(offset, Endian.little);
        return normalized ? v / 4294967295.0 : v.toDouble();
      case GltfComponentType.byte:
        final v = data.getInt8(offset);
        // Signed normalization clamps at -1: -128 and -127 both map to -1.0,
        // which is what keeps the range symmetric.
        return normalized ? (v / 127.0).clamp(-1.0, 1.0) : v.toDouble();
      case GltfComponentType.short:
        final v = data.getInt16(offset, Endian.little);
        return normalized ? (v / 32767.0).clamp(-1.0, 1.0) : v.toDouble();
    }
  }

  /// Reads one component as an integer, for indices and joint references.
  int readInt(ByteData data, int offset) {
    switch (this) {
      case GltfComponentType.unsignedByte:
        return data.getUint8(offset);
      case GltfComponentType.unsignedShort:
        return data.getUint16(offset, Endian.little);
      case GltfComponentType.unsignedInt:
        return data.getUint32(offset, Endian.little);
      case GltfComponentType.byte:
        return data.getInt8(offset);
      case GltfComponentType.short:
        return data.getInt16(offset, Endian.little);
      case GltfComponentType.float:
        return data.getFloat32(offset, Endian.little).toInt();
    }
  }
}

/// glTF accessor `type` values.
enum GltfAccessorType {
  scalar('SCALAR', 1),
  vec2('VEC2', 2),
  vec3('VEC3', 3),
  vec4('VEC4', 4),
  mat2('MAT2', 4),
  mat3('MAT3', 9),
  mat4('MAT4', 16);

  const GltfAccessorType(this.name, this.componentCount);

  final String name;
  final int componentCount;

  static GltfAccessorType fromName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('Unknown glTF accessor type "$name".');
  }
}

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
    required this.buffers,
  })  : _accessors = _listOf(json['accessors']),
        _bufferViews = _listOf(json['bufferViews']);

  final List<Map<String, Object?>> _accessors;
  final List<Map<String, Object?>> _bufferViews;

  /// Buffers already resolved by [GlbContainer.resolveBuffers], indexed the same
  /// way the glTF `buffers` array is.
  final List<Uint8List> buffers;

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

    final out = Float32List(count * components);
    _forEachElement(accessorIndex, (elementIndex, data, byteOffset) {
      for (var c = 0; c < components; c++) {
        final offset = byteOffset + c * componentType.sizeInBytes;
        out[elementIndex * components + c] =
            componentType.readDouble(data, offset, normalized: normalized);
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

    final out = Uint32List(count * components);
    _forEachElement(accessorIndex, (elementIndex, data, byteOffset) {
      for (var c = 0; c < components; c++) {
        final offset = byteOffset + c * componentType.sizeInBytes;
        out[elementIndex * components + c] =
            componentType.readInt(data, offset);
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

    for (var i = 0; i < sparseCount; i++) {
      final target = indexComponent.readInt(
        indexView.data,
        indexOffset + i * indexComponent.sizeInBytes,
      );
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

    if (byteOffset + byteLength > buffer.length) {
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
