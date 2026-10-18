import 'dart:typed_data';
import '../format_exceptions.dart';

/// glTF `componentType` values.
///
/// Reading lives on the enum rather than in static helpers on the reader: the
/// rules — element size, and the asymmetric normalization of signed types — are
/// properties of the component type itself, so this is where they belong.
///
/// **Closed for good**: glTF 2.0's own component types: the specification is
/// versioned, and a file naming another is not glTF 2.0. No member can be added
/// without changing what the type means, so it stays an enum and a `switch`
/// over it may name every case.
enum GltfComponentType {
  /// A signed 8-bit integer; normalised by 127, clamped at -1.
  byte(5120, 1),

  /// An unsigned 8-bit integer; normalised by 255.
  unsignedByte(5121, 1),

  /// A signed 16-bit integer; normalised by 32767, clamped at -1.
  short(5122, 2),

  /// An unsigned 16-bit integer; normalised by 65535.
  unsignedShort(5123, 2),

  /// An unsigned 32-bit integer, for indices; normalised by `2^32 − 1`.
  unsignedInt(5125, 4),

  /// A 32-bit float, read as it is.
  float(5126, 4);

  const GltfComponentType(this.code, this.sizeInBytes);

  /// The number glTF's `componentType` writes for this type.
  final int code;

  /// Size of one component in bytes.
  final int sizeInBytes;

  /// Returns the type glTF numbers [code]. Throws a [GltfFormatException]
  /// for a number glTF does not define.
  static GltfComponentType fromCode(int code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw GltfFormatException('Unknown glTF componentType $code.');
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
///
/// **Closed for good**: glTF 2.0's own accessor types: the specification is
/// versioned, and a file naming another is not glTF 2.0. No member can be added
/// without changing what the type means, so it stays an enum and a `switch`
/// over it may name every case.
enum GltfAccessorType {
  /// One component an element.
  scalar('SCALAR', 1),

  /// Two components an element.
  vec2('VEC2', 2),

  /// Three components an element.
  vec3('VEC3', 3),

  /// Four components an element.
  vec4('VEC4', 4),

  /// A 2×2 matrix, four components, column-major.
  mat2('MAT2', 4),

  /// A 3×3 matrix, nine components, column-major.
  mat3('MAT3', 9),

  /// A 4×4 matrix, sixteen components, column-major.
  mat4('MAT4', 16);

  const GltfAccessorType(this.name, this.componentCount);

  /// The string glTF's accessor `type` writes: `VEC3`.
  final String name;

  /// Count of components in one element.
  final int componentCount;

  /// Returns the type glTF spells [name]. Throws a [GltfFormatException]
  /// for a name glTF does not define.
  static GltfAccessorType fromName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw GltfFormatException('Unknown glTF accessor type "$name".');
  }
}
