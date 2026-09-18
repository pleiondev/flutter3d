/// A Draco-compressed mesh, decoded — `gfx-82n`.
///
/// **Why a decoder and not a refusal.** `gltf_loader_mesh.dart` detected
/// `KHR_draco_mesh_compression`, warned, and skipped the primitive — so a
/// compressed glTF opened as a model with holes in it, which is worse than
/// refusing the file outright because nothing says which parts are missing.
/// Every exporter that cares about download size writes these.
///
/// **Transcribed from the reference decoder with a real encoder beside it.**
/// Draco publishes no prose specification; what exists is the C++ decoder, and
/// this follows it file by file. Every claim here was checked against a mesh
/// compressed by Draco's own encoder and compared with its uncompressed twin —
/// which is the only reason this row could be attempted at all, and the lesson
/// `zstd.dart` paid for on `gfx-78n`: four bugs there all looked right and were
/// caught only because a real encoder disagreed.
///
/// What this decodes, named so the gap is not mistaken for coverage: the
/// sequential connectivity method, and attributes coded as quantised integers
/// with the difference predictor and the wrap transform — which is what
/// `--method sequential` produces and what every point cloud uses. The
/// edgebreaker connectivity method is not here yet; a file using it is refused
/// by name rather than half-decoded.
library;

import 'dart:typed_data';

import 'draco_buffer.dart';
import 'draco_octahedron.dart';

/// What a decoded primitive carries.
final class DracoMesh {
  const DracoMesh({required this.indices, required this.attributes});

  /// Triangle corners, three per face.
  final Uint32List indices;

  /// By the unique id the glTF extension names, which is *not* the order the
  /// attributes appear in — the extension maps `POSITION` to an id and the
  /// stream stores ids, so a decoder that returned a list would be handing back
  /// a correspondence it had guessed.
  final Map<int, DracoAttribute> attributes;
}

/// One decoded attribute.
final class DracoAttribute {
  const DracoAttribute({
    required this.type,
    required this.components,
    required this.values,
  });

  /// Draco's own attribute type: 0 position, 1 normal, 2 colour, 3 texcoord,
  /// 4 generic.
  final int type;

  final int components;

  /// `count * components` floats, dequantised.
  final Float32List values;
}

/// Draco's `GeometryAttribute::Type`.
abstract final class DracoAttributeType {
  static const int position = 0;
  static const int normal = 1;
  static const int color = 2;
  static const int texCoord = 3;
  static const int generic = 4;
}

/// Decodes [bytes], the contents of the buffer view a primitive's
/// `KHR_draco_mesh_compression` extension points at.
DracoMesh decodeDraco(Uint8List bytes) {
  final buffer = DracoBuffer(bytes);

  if (bytes.length < 11 ||
      bytes[0] != 0x44 ||
      bytes[1] != 0x52 ||
      bytes[2] != 0x41 ||
      bytes[3] != 0x43 ||
      bytes[4] != 0x4F) {
    throw const DracoException('not a Draco stream: no DRACO magic');
  }
  buffer.position = 5;
  final major = buffer.readUint8();
  final minor = buffer.readUint8();
  final encoderType = buffer.readUint8();
  final encoderMethod = buffer.readUint8();
  final flags = buffer.readUint16();

  if (major != 2) {
    throw DracoException(
      'bitstream version $major.$minor; only 2.x is read here. Draco 1.x '
      'files predate the varint counts this decoder assumes and no current '
      'encoder writes one.',
    );
  }
  if (encoderType != 1) {
    throw DracoException(
      'encoder type $encoderType is a point cloud; this reads triangular '
      'meshes, which is what the glTF extension carries.',
    );
  }
  if (encoderMethod != 0) {
    throw DracoException(
      'connectivity method $encoderMethod is edgebreaker, which is not '
      'decoded here yet — re-encode with `--method sequential`, or wait for '
      'the half of `gfx-82n` that is still missing. Refused by name rather '
      'than decoded into a mesh with the wrong faces.',
    );
  }
  // The metadata flag is the top bit. Nothing here reads metadata, and a file
  // carrying some would put it between the header and the connectivity, so it
  // is refused rather than skipped past a length this does not parse.
  if (flags & 0x8000 != 0) {
    throw const DracoException('metadata is present and is not parsed here');
  }

  final faceCount = buffer.readVarUint();
  final pointCount = buffer.readVarUint();
  final connectivityMethod = buffer.readUint8();
  if (connectivityMethod != 1) {
    throw DracoException(
      'sequential connectivity is compressed (method $connectivityMethod), '
      'which is not decoded here yet',
    );
  }

  // **Index width comes from the point count, not from the file.** The encoder
  // picks the narrowest type that can address every point and writes nothing
  // to say which it chose, so a decoder that assumed one width reads a
  // different mesh rather than failing.
  final indices = Uint32List(faceCount * 3);
  if (pointCount < 256) {
    for (var i = 0; i < indices.length; i++) {
      indices[i] = buffer.readUint8();
    }
  } else if (pointCount < 1 << 16) {
    for (var i = 0; i < indices.length; i++) {
      indices[i] = buffer.readUint16();
    }
  } else if (pointCount < 1 << 21) {
    for (var i = 0; i < indices.length; i++) {
      indices[i] = buffer.readVarUint();
    }
  } else {
    for (var i = 0; i < indices.length; i++) {
      indices[i] = buffer.readUint32();
    }
  }

  final attributes = _decodeAttributes(buffer, pointCount);
  return DracoMesh(indices: indices, attributes: attributes);
}

/// One attribute's descriptor, as the stream declares it.
final class _Descriptor {
  _Descriptor({
    required this.type,
    required this.dataType,
    required this.components,
    required this.normalized,
    required this.uniqueId,
  });

  final int type;
  final int dataType;
  final int components;
  final bool normalized;
  final int uniqueId;

  /// Set once the decoder types are read.
  int decoderType = 0;

  /// The integer values before the quantisation is undone.
  late Int32List portable;

  /// Quantisation, filled after every attribute's integers are read — the
  /// stream puts all the values first and all the parameters after.
  Float32List? minValues;
  double range = 0.0;
  int quantizationBits = 0;

  /// The octahedral box a normals attribute was quantised in — `gfx-82n`.
  OctahedronToolBox? octahedron;

  /// How many integers a point takes in the stream, which is *not* how many
  /// floats it becomes: a normal is two octahedral coordinates and three
  /// components.
  int get portableComponents => decoderType == 3 ? 2 : components;
}

Map<int, DracoAttribute> _decodeAttributes(DracoBuffer buffer, int points) {
  final decoderCount = buffer.readUint8();
  final out = <int, DracoAttribute>{};

  for (var d = 0; d < decoderCount; d++) {
    final count = buffer.readVarUint();
    final descriptors = <_Descriptor>[];
    for (var i = 0; i < count; i++) {
      descriptors.add(
        _Descriptor(
          type: buffer.readUint8(),
          dataType: buffer.readUint8(),
          components: buffer.readUint8(),
          normalized: buffer.readUint8() != 0,
          uniqueId: buffer.readVarUint(),
        ),
      );
    }

    // Every attribute's decoder type, then every attribute's values, then
    // every attribute's transform data. Three passes over the same list rather
    // than one pass doing all three, because that is the order the encoder
    // wrote them and the stream has no framing to recover from getting it
    // wrong.
    for (final descriptor in descriptors) {
      descriptor.decoderType = buffer.readUint8();
    }

    for (final descriptor in descriptors) {
      _decodeValues(buffer, descriptor, points);
    }
    for (final descriptor in descriptors) {
      _decodeTransformData(buffer, descriptor);
    }

    for (final descriptor in descriptors) {
      out[descriptor.uniqueId] = DracoAttribute(
        type: descriptor.type,
        components: descriptor.components,
        values: _dequantize(descriptor, points),
      );
    }
  }
  return out;
}

/// Draco's `PredictionSchemeMethod`.
const int _predictionNone = -2;
const int _predictionDifference = 0;

/// Draco's `PredictionSchemeTransformType`.
const int _transformWrap = 1;
const int _transformNormalOctahedronCanonicalized = 3;

void _decodeValues(DracoBuffer buffer, _Descriptor descriptor, int points) {
  final method = buffer.readInt8();
  var transform = -1;
  if (method != _predictionNone) {
    transform = buffer.readInt8();
    if (transform != _transformWrap &&
        transform != _transformNormalOctahedronCanonicalized) {
      throw DracoException(
        'prediction transform $transform is neither the wrap transform nor '
        'the canonicalized octahedron one, which are the two the reference '
        'encoder writes for sequentially coded attributes',
      );
    }
    if (method != _predictionDifference) {
      throw DracoException(
        'prediction scheme $method needs the mesh connectivity, which the '
        'sequential path does not build — only the difference predictor is '
        'decoded here',
      );
    }
  }

  final components = descriptor.portableComponents;
  final values = points * components;
  final compressed = buffer.readUint8();

  final Int32List portable;
  if (compressed > 0) {
    final symbols = decodeSymbols(buffer, values, components);
    portable = Int32List(values);
    for (var i = 0; i < values; i++) {
      portable[i] = symbols[i];
    }
  } else {
    final width = buffer.readUint8();
    portable = Int32List(values);
    for (var i = 0; i < values; i++) {
      var value = 0;
      for (var b = 0; b < width; b++) {
        value |= buffer.readUint8() << (8 * b);
      }
      portable[i] = value;
    }
  }

  // **Zig-zag back to signed, unless the scheme promises positives.** The
  // symbol coder carries unsigned integers, so a correction of −1 was written
  // as 1. The octahedron transform keeps its corrections positive and says so
  // — `AreCorrectionsPositive` — and undoing a zig-zag that was never applied
  // halves every correction.
  if (transform != _transformNormalOctahedronCanonicalized) {
    for (var i = 0; i < values; i++) {
      final symbol = portable[i];
      portable[i] = (symbol & 1) != 0 ? -((symbol + 1) >> 1) : symbol >> 1;
    }
  }

  if (transform == _transformNormalOctahedronCanonicalized) {
    _applyOctahedronDifference(buffer, descriptor, portable, points);
  } else if (method != _predictionNone) {
    _applyDifference(buffer, portable, components, points);
  }
  descriptor.portable = portable;
}

/// `PredictionSchemeDeltaDecoder` with the wrap transform.
///
/// Each value is the previous one plus a correction, wrapped back into the
/// range the encoder measured — the wrap is what lets a correction that would
/// overflow be written as a small number going the other way round.
void _applyDifference(
  DracoBuffer buffer,
  Int32List values,
  int components,
  int points,
) {
  final minValue = buffer.readUint32().toSigned(32);
  final maxValue = buffer.readUint32().toSigned(32);
  if (minValue > maxValue) {
    throw const DracoException('wrap transform range is inverted');
  }
  final span = maxValue - minValue + 1;

  // **The first point is not exempt — it is predicted from zero.** The
  // reference runs the transform over a prediction of all zeros for element
  // zero, which matters because the wrap can fire there too: this model's very
  // first coordinate came out 16384 low until that was written, and every other
  // value in the mesh was already exact. One wrong number out of a hundred and
  // ninety-two is exactly the kind of thing a test that only checked "it
  // decoded" would let through.
  for (var i = 0; i < components; i++) {
    var value = values[i];
    if (value > maxValue) {
      value -= span;
    } else if (value < minValue) {
      value += span;
    }
    values[i] = value;
  }

  for (var i = components; i < points * components; i++) {
    var value = values[i - components] + values[i];
    if (value > maxValue) {
      value -= span;
    } else if (value < minValue) {
      value += span;
    }
    values[i] = value;
  }
}

/// The delta predictor in octahedral space — `gfx-82n`.
///
/// The same "each value is the one before plus a correction" as the wrap
/// transform, except the addition happens in a frame the predictor itself
/// chooses. See `draco_octahedron.dart` for why.
void _applyOctahedronDifference(
  DracoBuffer buffer,
  _Descriptor descriptor,
  Int32List values,
  int points,
) {
  final maxQuantized = buffer.readUint32().toSigned(32);
  // Read and discarded, exactly as the reference does: the centre is derived
  // from the maximum, and the stored copy is not consulted.
  buffer.readUint32();
  final box = OctahedronToolBox.fromMaxQuantized(maxQuantized);
  descriptor.octahedron = box;

  // The first point is predicted from the origin, which for this transform is
  // the octahedral centre — the same "element zero is not exempt" the wrap
  // transform needs.
  final first = Int32List(2);
  octahedronComputeOriginal(box, first, 0, values[0], values[1]);
  values[0] = first[0];
  values[1] = first[1];

  for (var i = 1; i < points; i++) {
    final at = i * 2;
    final correctionS = values[at];
    final correctionT = values[at + 1];
    values[at] = values[at - 2];
    values[at + 1] = values[at - 1];
    octahedronComputeOriginal(box, values, at, correctionS, correctionT);
  }
}

void _decodeTransformData(DracoBuffer buffer, _Descriptor descriptor) {
  switch (descriptor.decoderType) {
    // Quantisation: the box the values were fitted into, then how finely.
    case 2:
      final minValues = Float32List(descriptor.components);
      for (var i = 0; i < descriptor.components; i++) {
        minValues[i] = buffer.readFloat32();
      }
      descriptor
        ..minValues = minValues
        ..range = buffer.readFloat32()
        ..quantizationBits = buffer.readUint8();
    // Normals: one byte saying how finely the octahedron was divided. The box
    // itself was already built from the prediction transform's own maximum;
    // this is the copy the attribute transform keeps, and the two agree.
    case 3:
      descriptor.quantizationBits = buffer.readUint8();
    default:
      throw DracoException(
        'attribute decoder type ${descriptor.decoderType} is not decoded here',
      );
  }
}

Float32List _dequantize(_Descriptor descriptor, int points) {
  final components = descriptor.components;
  final out = Float32List(points * components);

  // Normals leave octahedral space here, which is where two integers become
  // three floats.
  final box = descriptor.octahedron;
  if (box != null) {
    for (var i = 0; i < points; i++) {
      box.toUnitVector(
        descriptor.portable[i * 2],
        descriptor.portable[i * 2 + 1],
        out,
        i * 3,
      );
    }
    return out;
  }

  final minValues = descriptor.minValues;
  if (minValues == null) return out;

  final maxQuantized = (1 << descriptor.quantizationBits) - 1;
  final step = maxQuantized > 0 ? descriptor.range / maxQuantized : 0.0;
  for (var i = 0; i < points; i++) {
    for (var c = 0; c < components; c++) {
      out[i * components + c] =
          minValues[c] + descriptor.portable[i * components + c] * step;
    }
  }
  return out;
}
