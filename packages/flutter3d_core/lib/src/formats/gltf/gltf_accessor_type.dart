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
    if (this == GltfComponentType.float) {
      return data.getFloat32(offset, Endian.little);
    }
    final v = readInt(data, offset);
    return normalized ? normalize(v) : v.toDouble();
  }

  /// The normalization rule on its own: an integer component as the float it
  /// stands for.
  ///
  /// Separate from [readDouble] because not every integer comes out of a
  /// buffer view — `KHR_draco_mesh_compression` hands back a colour as the
  /// bytes it was stored as, and they mean what the accessor says they mean.
  double normalize(int v) => switch (this) {
    GltfComponentType.float => v.toDouble(),
    GltfComponentType.unsignedByte => v / 255.0,
    GltfComponentType.unsignedShort => v / 65535.0,
    GltfComponentType.unsignedInt => v / 4294967295.0,
    // Signed normalization clamps at -1: -128 and -127 both map to -1.0,
    // which is what keeps the range symmetric.
    GltfComponentType.byte => (v / 127.0).clamp(-1.0, 1.0),
    GltfComponentType.short => (v / 32767.0).clamp(-1.0, 1.0),
  };

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
