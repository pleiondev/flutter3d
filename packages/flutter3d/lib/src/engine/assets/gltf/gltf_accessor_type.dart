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
