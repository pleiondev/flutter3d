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
/// this follows it file by file. Every claim here was checked against meshes
/// compressed by Draco's own encoder and compared with their uncompressed
/// twins — which is the only reason this row could be attempted at all, and
/// the lesson `zstd.dart` paid for on `gfx-78n`: four bugs there all looked
/// right and were caught only because a real encoder disagreed.
///
/// What this decodes, named so the gap is not mistaken for coverage:
///
/// * both connectivity methods — sequential here, edgebreaker in
///   `draco_edgebreaker.dart` with its standard and valence traversals;
/// * attributes coded as raw values, as integers, as quantised floats and as
///   octahedral normals;
/// * every prediction scheme a bitstream 2.2 encoder can choose — see
///   `draco_prediction.dart` — over both attribute walks in
///   `draco_traversal.dart`.
///
/// What it refuses, by name: point clouds, bitstreams older than 2.0 (and
/// edgebreaker older than 2.2), metadata, compressed sequential connectivity,
/// the predictive edgebreaker traversal and the two retired prediction
/// schemes. None of those is something `gltf-transform`, Blender or the
/// reference encoder writes today.
library;

import 'dart:typed_data';

import 'draco_buffer.dart';
import 'draco_edgebreaker.dart';
import 'draco_octahedron.dart';
import 'draco_prediction.dart';
import 'draco_traversal.dart';

/// What a decoded primitive carries.
final class DracoMesh {
  const DracoMesh({
    required this.indices,
    required this.pointCount,
    required this.attributes,
  });

  /// Triangle corners, three per face.
  final Uint32List indices;

  /// How many points — what a GPU calls vertices — every attribute has a
  /// value for. After edgebreaker this is the count *after* seams have split
  /// vertices, which is the count the glTF accessors declare.
  final int pointCount;

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
    this.integers,
  });

  /// Draco's own attribute type: 0 position, 1 normal, 2 colour, 3 texcoord,
  /// 4 generic.
  final int type;

  final int components;

  /// `count * components` floats, one run per point: dequantised where the
  /// attribute was quantised, converted where it was stored as integers.
  final Float32List values;

  /// The same values as the integers they were stored as, when they were —
  /// joint indices, or a colour kept as bytes. Null for anything quantised.
  /// Signed 32-bit, so an unsigned value past 2^31 reads negative here and
  /// correctly in [values]' doubles only up to float precision; nothing a glTF
  /// vertex attribute holds is that wide.
  ///
  /// Both, because what an integer *means* is not Draco's to say: glTF's
  /// accessor decides whether a byte of 255 is the joint 255 or the colour
  /// 1.0, and that decision needs the byte.
  final Int32List? integers;
}

/// Draco's `GeometryAttribute::Type`.
abstract final class DracoAttributeType {
  static const int position = 0;
  static const int normal = 1;
  static const int color = 2;
  static const int texCoord = 3;
  static const int generic = 4;
}

Never _fail(String message) => throw DracoException(message);

/// Decodes [bytes], the contents of the buffer view a primitive's
/// `KHR_draco_mesh_compression` extension points at.
DracoMesh decodeDraco(Uint8List bytes) {
  try {
    return _decode(bytes);
  } on RangeError {
    // The cursor's multi-byte reads and every table lookup are bounds-checked
    // by the language rather than by hand. A stream that runs one off the end
    // is truncated or lying about a count, and the caller was promised one
    // kind of exception.
    throw const DracoException(
      'the stream ends, or names something out of range, part way through',
    );
  }
}

DracoMesh _decode(Uint8List bytes) {
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
  // The metadata flag is the top bit. Nothing here reads metadata, and a file
  // carrying some would put it between the header and the connectivity, so it
  // is refused rather than skipped past a length this does not parse.
  if (flags & 0x8000 != 0) {
    throw const DracoException('metadata is present and is not parsed here');
  }

  final _Connectivity connectivity = switch (encoderMethod) {
    0 => _decodeSequentialConnectivity(buffer),
    1 when minor >= 2 => _Connectivity.edgebreaker(
      decodeEdgebreakerConnectivity(buffer),
    ),
    1 => throw DracoException(
      'edgebreaker connectivity in bitstream $major.$minor; only 2.2 is read '
      'here. Earlier 2.x streams order the same sections differently and '
      'nothing has written one since 2017.',
    ),
    _ => throw DracoException('unknown connectivity method $encoderMethod'),
  };

  return DracoMesh(
    indices: connectivity.indices,
    pointCount: connectivity.pointCount,
    attributes: _decodeAttributes(buffer, connectivity),
  );
}

/// What the attribute section needs to know about the faces before it.
final class _Connectivity {
  const _Connectivity.sequential(this.indices, this.pointCount)
    : edgebreaker = null;

  _Connectivity.edgebreaker(EdgebreakerConnectivity this.edgebreaker)
    : indices = edgebreaker.cornerToPoint,
      pointCount = edgebreaker.pointCount;

  final Uint32List indices;
  final int pointCount;

  /// Null for sequential connectivity, which stores plain indices and builds
  /// no corner table — so nothing there can be predicted from the mesh.
  final EdgebreakerConnectivity? edgebreaker;
}

_Connectivity _decodeSequentialConnectivity(DracoBuffer buffer) {
  final faceCount = buffer.readVarUint();
  final pointCount = buffer.readVarUint();
  final connectivityMethod = buffer.readUint8();
  if (connectivityMethod != 1) {
    throw DracoException(
      'sequential connectivity is compressed (method $connectivityMethod), '
      'which is not decoded here yet',
    );
  }
  if (faceCount * 3 > buffer.remaining) {
    _fail('$faceCount faces do not fit in ${buffer.remaining} bytes');
  }
  if (pointCount > buffer.remaining * 4096) {
    // Every attribute allocates by this number. There is no honest floor on
    // bytes per point once an entropy coder is involved, so the bound is loose
    // — and still far below what a hostile header can name.
    _fail('$pointCount points do not fit in ${buffer.remaining} bytes');
  }

  // **Index width comes from the point count, not from the file.** The encoder
  // picks the narrowest type that can address every point and writes nothing
  // to say which it chose, so a decoder that assumed one width reads a
  // different mesh rather than failing.
  final int Function() readIndex = pointCount < 256
      ? buffer.readUint8
      : pointCount < 1 << 16
      ? buffer.readUint16
      : pointCount < 1 << 21
      ? buffer.readVarUint
      : buffer.readUint32;
  final indices = Uint32List(faceCount * 3);
  for (var i = 0; i < indices.length; i++) {
    indices[i] = readIndex();
  }
  return _Connectivity.sequential(indices, pointCount);
}

/// Draco's `DataType`, as far as an attribute can have one.
enum _DataType {
  int8(1, integral: true),
  uint8(1, integral: true),
  int16(2, integral: true),
  uint16(2, integral: true),
  int32(4, integral: true),
  uint32(4, integral: true),
  float32(4, integral: false);

  const _DataType(this.bytes, {required this.integral});

  final int bytes;
  final bool integral;

  static _DataType fromCode(int code) => switch (code) {
    1 => int8,
    2 => uint8,
    3 => int16,
    4 => uint16,
    5 => int32,
    6 => uint32,
    9 => float32,
    // A bool is stored as a byte and nothing downstream tells them apart.
    11 => uint8,
    7 || 8 || 10 => _fail(
      'attribute data type $code is 64 bits wide, which no glTF accessor can '
      'hold and which is not decoded here',
    ),
    _ => _fail('unknown attribute data type $code'),
  };
}

/// Draco's `SequentialAttributeEncoderType`: how an attribute's values were
/// turned into the integers the stream stores.
enum _Coding {
  /// Not turned into anything: raw little-endian values.
  generic,

  /// Integers already, stored as they are.
  integer,

  /// Floats, fitted into a box and rounded to so many bits.
  quantization,

  /// Unit vectors, as two octahedral coordinates.
  normals;

  static _Coding fromCode(int code) => switch (code) {
    0 => generic,
    1 => integer,
    2 => quantization,
    3 => normals,
    _ => _fail('attribute decoder type $code is not decoded here'),
  };
}

/// One attribute, from its descriptor to its integers.
final class _Attribute {
  _Attribute(DracoBuffer buffer)
    : type = buffer.readUint8(),
      dataType = _DataType.fromCode(buffer.readUint8()),
      components = buffer.readUint8(),
      normalized = buffer.readUint8() != 0,
      uniqueId = buffer.readVarUint() {
    if (components == 0) _fail('an attribute with no components');
  }

  final int type;
  final _DataType dataType;
  final int components;
  final bool normalized;
  final int uniqueId;

  late final _Coding coding;

  /// The integers the stream stores, once prediction is undone; one run of
  /// [portableComponents] per stored value.
  late final Int32List portable;

  /// Raw values, for [_Coding.generic] only.
  late final ByteData raw;

  /// Quantisation, read after every attribute's integers — the stream puts
  /// all the values first and all the parameters after.
  late final Float32List minValues;
  late final double range;
  late final int quantizationBits;

  /// How many integers a stored value takes, which is *not* how many floats it
  /// becomes: a normal is two octahedral coordinates and three components.
  int get portableComponents => coding == _Coding.normals ? 2 : components;
}

/// Where one attribute decoder's values go — the order they are stored in and
/// which point each belongs to.
final class _Layout {
  const _Layout({
    required this.sequence,
    required this.entryToPoint,
    required this.pointToValue,
  });

  /// The walk that ordered the values; null for sequential connectivity,
  /// where value *i* is point *i* and that is all there is.
  final AttributeSequence? sequence;
  final Int32List entryToPoint;

  /// Null where point and value are the same number.
  final Int32List? pointToValue;

  int get entries => entryToPoint.length;
}

/// `MeshEdgebreakerDecoderImpl::CreateAttributesDecoder`: which connectivity
/// an attribute decoder's values are laid out over.
_Layout _edgebreakerLayout(
  DracoBuffer buffer,
  EdgebreakerConnectivity mesh,
  Set<int> claimed,
) {
  final attributeData = buffer.readInt8();
  final perCorner = switch (buffer.readUint8()) {
    0 => false,
    1 => true,
    final other => _fail('unknown mesh attribute element type $other'),
  };
  final traversalMethod = buffer.readUint8();

  if (attributeData >= mesh.attributeTables.length) {
    _fail(
      'an attribute decoder names connectivity $attributeData, which the '
      'stream did not declare',
    );
  }
  // −1 is the position's own; anything else is an attribute connectivity, and
  // each may be claimed by one decoder only.
  if (!claimed.add(attributeData < 0 ? -1 : attributeData)) {
    _fail('two attribute decoders claim the same connectivity');
  }

  final corners = mesh.corners;
  final AttributeSequence sequence;
  if (perCorner) {
    // Stored once per *attribute* vertex, over the seamed table.
    if (attributeData < 0) {
      _fail('a per-corner attribute decoder names no connectivity');
    }
    if (traversalMethod != 0) {
      _fail('per-corner attributes are only ever walked depth first');
    }
    final table = mesh.attributeTables[attributeData];
    sequence = traverseDepthFirst(
      table,
      table.vertexCount > corners.vertexCount
          ? table.vertexCount
          : corners.vertexCount,
    );
  } else {
    // Stored once per mesh vertex: the attribute had no seams of its own, so
    // the seamed table the stream declared for it goes unused.
    sequence = switch (traversalMethod) {
      0 => traverseDepthFirst(corners, corners.vertexCount),
      1 => traverseByPredictionDegree(corners, corners.vertexCount),
      _ => _fail('unknown attribute traversal method $traversalMethod'),
    };
  }

  final table = sequence.table;
  final pointToValue = Int32List(mesh.pointCount);
  for (var corner = 0; corner < table.cornerCount; corner++) {
    final value = sequence.vertexToValue[table.vertex(corner)];
    if (value >= mesh.pointCount) {
      _fail('an attribute has more values than the mesh has points');
    }
    pointToValue[mesh.cornerToPoint[corner]] = value;
  }
  return _Layout(
    sequence: sequence,
    entryToPoint: Int32List.fromList(<int>[
      for (var value = 0; value < sequence.valueCount; value++)
        mesh.cornerToPoint[sequence.cornerOf(value)],
    ]),
    pointToValue: pointToValue,
  );
}

Map<int, DracoAttribute> _decodeAttributes(
  DracoBuffer buffer,
  _Connectivity connectivity,
) {
  final decoderCount = buffer.readUint8();
  final mesh = connectivity.edgebreaker;

  // **Three sweeps over the decoders, because that is the order of the
  // stream**: every decoder's layout, then every decoder's attribute
  // descriptors, then every decoder's values. With sequential connectivity
  // there is one decoder and the distinction vanishes; an edgebreaker mesh
  // with UVs has at least two, and reading one decoder to the end before
  // starting the next reads the second one's header out of the first one's
  // values.
  final claimed = <int>{};
  final layouts = <_Layout>[
    for (var d = 0; d < decoderCount; d++)
      mesh == null
          ? _Layout(
              sequence: null,
              entryToPoint: Int32List.fromList(<int>[
                for (var p = 0; p < connectivity.pointCount; p++) p,
              ]),
              pointToValue: null,
            )
          : _edgebreakerLayout(buffer, mesh, claimed),
  ];

  final decoders = <List<_Attribute>>[
    for (var d = 0; d < decoderCount; d++) _readDescriptors(buffer),
  ];

  // The positions a texture-coordinate or normal predictor leans on: the
  // first three-component position attribute, as in the reference.
  final parent = <(int, int)>[
    for (var d = 0; d < decoderCount; d++)
      for (var i = 0; i < decoders[d].length; i++)
        if (decoders[d][i].type == DracoAttributeType.position &&
            decoders[d][i].components == 3 &&
            decoders[d][i].coding != _Coding.generic)
          (d, i),
  ].firstOrNull;

  final out = <int, DracoAttribute>{};
  for (var d = 0; d < decoderCount; d++) {
    final layout = layouts[d];
    final attributes = decoders[d];

    // Within a decoder: every attribute's values, then every attribute's
    // transform parameters. The stream has no framing to recover from getting
    // that order wrong.
    for (var i = 0; i < attributes.length; i++) {
      // Only positions that are *already decoded* can be predicted from, which
      // the encoder guarantees by ordering and a hostile stream does not.
      final positions = switch (parent) {
        (final pd, final pi) when pd < d || (pd == d && pi < i) =>
          ParentPositions(
            portable: decoders[pd][pi].portable,
            pointToValue: layouts[pd].pointToValue,
            entryToPoint: layout.entryToPoint,
          ),
        _ => null,
      };
      _decodeValues(buffer, attributes[i], layout, positions);
    }
    for (final attribute in attributes) {
      _decodeTransformData(buffer, attribute);
    }
    for (final attribute in attributes) {
      out[attribute.uniqueId] = _toPoints(
        attribute,
        layout,
        connectivity.pointCount,
      );
    }
  }
  return out;
}

/// `AttributesDecoder::DecodeAttributesDecoderData`, then the coding byte each
/// attribute has in `SequentialAttributeDecodersController`.
List<_Attribute> _readDescriptors(DracoBuffer buffer) {
  final count = buffer.readVarUint();
  if (count > buffer.remaining) _fail('more attributes than bytes');
  final attributes = <_Attribute>[
    for (var i = 0; i < count; i++) _Attribute(buffer),
  ];
  for (final attribute in attributes) {
    attribute.coding = _Coding.fromCode(buffer.readUint8());
  }
  return attributes;
}

/// Draco's `PredictionSchemeMethod`.
const int _predictionNone = -2;
const int _predictionDifference = 0;
const int _predictionParallelogram = 1;
const int _predictionMultiParallelogram = 2;
const int _predictionTexCoordsDeprecated = 3;
const int _predictionConstrainedMultiParallelogram = 4;
const int _predictionTexCoordsPortable = 5;
const int _predictionGeometricNormal = 6;

/// Draco's `PredictionSchemeTransformType`.
const int _transformWrap = 1;
const int _transformNormalOctahedronCanonicalized = 3;

void _decodeValues(
  DracoBuffer buffer,
  _Attribute attribute,
  _Layout layout,
  ParentPositions? positions,
) {
  if (attribute.coding == _Coding.generic) {
    // `SequentialAttributeDecoder::DecodeValues`: no integers, no prediction,
    // the attribute's own bytes one value after another.
    final size =
        layout.entries * attribute.components * attribute.dataType.bytes;
    attribute.raw = ByteData.sublistView(buffer.readBytes(size));
    return;
  }

  final method = buffer.readInt8();
  final transformType = method == _predictionNone ? -1 : buffer.readInt8();
  _checkScheme(attribute, layout, method, transformType, positions);

  final components = attribute.portableComponents;
  final count = layout.entries * components;
  final portable = Int32List(count);

  if (buffer.readUint8() > 0) {
    portable.setAll(0, decodeSymbols(buffer, count, components));
  } else {
    final width = buffer.readUint8();
    if (width > 4) _fail('uncompressed integers $width bytes wide');
    if (count * width > buffer.remaining) _fail('integers run past the end');
    for (var i = 0; i < count; i++) {
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
  if (transformType != _transformNormalOctahedronCanonicalized) {
    for (var i = 0; i < count; i++) {
      final symbol = portable[i] & 0xFFFFFFFF;
      portable[i] = (symbol & 1) != 0 ? -((symbol + 1) >> 1) : symbol >> 1;
    }
  }

  attribute.portable = portable;
  if (method == _predictionNone) return;

  // Each scheme reads its own side data and then its transform's, in the order
  // the reference's `DecodePredictionData` overrides do — the geometric normal
  // being the one that reads the transform first.
  final sequence = layout.sequence;
  switch (method) {
    case _predictionGeometricNormal:
      GeometricNormal(buffer).predict(sequence!, positions!, portable);

    case _predictionTexCoordsPortable:
      final scheme = TexCoordsPortable(buffer);
      scheme.predict(
        WrapTransform(buffer, components),
        sequence!,
        positions!,
        portable,
      );

    case _predictionConstrainedMultiParallelogram:
      final scheme = ConstrainedMultiParallelogram(
        buffer,
        sequence!.table.cornerCount,
      );
      scheme.predict(
        WrapTransform(buffer, components),
        sequence,
        portable,
        components,
      );

    case _predictionParallelogram:
      predictParallelogram(
        WrapTransform(buffer, components),
        sequence!,
        portable,
        components,
      );

    default:
      predictDifference(
        transformType == _transformWrap
            ? WrapTransform(buffer, components)
            : OctahedronTransform(buffer),
        portable,
        components,
        layout.entries,
      );
  }
}

/// Refuses, by name, every combination of scheme and transform that is not
/// decoded — before a single value is read, so a refusal is never a half-built
/// mesh.
void _checkScheme(
  _Attribute attribute,
  _Layout layout,
  int method,
  int transformType,
  ParentPositions? positions,
) {
  if (method == _predictionNone) return;

  final isNormal = attribute.coding == _Coding.normals;
  if (transformType !=
      (isNormal ? _transformNormalOctahedronCanonicalized : _transformWrap)) {
    throw DracoException(
      'prediction transform $transformType on '
      '${isNormal ? 'an octahedral normal' : 'an integer attribute'}; the '
      'reference encoder writes the canonicalized octahedron transform (3) '
      'for the one and the wrap transform (1) for the other, and the older '
      'octahedron transform (2) was retired before bitstream 2.2',
    );
  }

  switch (method) {
    case _predictionDifference:
      return;
    case _predictionMultiParallelogram:
      throw const DracoException(
        'prediction scheme 2 is the unconstrained multi-parallelogram, which '
        'was retired before bitstream 2.2 and which no current encoder writes',
      );
    case _predictionTexCoordsDeprecated:
      throw const DracoException(
        'prediction scheme 3 is the deprecated texture-coordinate predictor, '
        'which computed in floats and was replaced by the portable one (5) '
        'because two machines could disagree about it',
      );
    case _predictionParallelogram ||
        _predictionConstrainedMultiParallelogram ||
        _predictionTexCoordsPortable ||
        _predictionGeometricNormal:
      break;
    default:
      throw DracoException('unknown prediction scheme $method');
  }

  if (layout.sequence == null) {
    throw DracoException(
      'prediction scheme $method needs the mesh connectivity, which '
      'sequential connectivity does not build — only the difference predictor '
      'can follow it',
    );
  }
  if (isNormal != (method == _predictionGeometricNormal)) {
    throw DracoException(
      'prediction scheme $method on '
      '${isNormal ? 'an octahedral normal' : 'an integer attribute'}, which '
      'is not a pairing the reference encoder makes',
    );
  }
  if (positions == null &&
      (method == _predictionTexCoordsPortable ||
          method == _predictionGeometricNormal)) {
    throw DracoException(
      'prediction scheme $method predicts from the positions, and no '
      'three-component integer position attribute was decoded before it',
    );
  }
  if (method == _predictionTexCoordsPortable &&
      attribute.portableComponents != 2) {
    throw const DracoException(
      'the texture-coordinate predictor on an attribute that is not two '
      'components wide',
    );
  }
}

void _decodeTransformData(DracoBuffer buffer, _Attribute attribute) {
  switch (attribute.coding) {
    case _Coding.generic || _Coding.integer:
      return;
    // Quantisation: the box the values were fitted into, then how finely.
    case _Coding.quantization:
      attribute
        ..minValues = Float32List.fromList(<double>[
          for (var i = 0; i < attribute.components; i++) buffer.readFloat32(),
        ])
        ..range = buffer.readFloat32()
        ..quantizationBits = buffer.readUint8();
      if (attribute.quantizationBits < 1 || attribute.quantizationBits > 30) {
        _fail('${attribute.quantizationBits}-bit quantisation');
      }
    // Normals: one byte saying how finely the octahedron was divided.
    case _Coding.normals:
      attribute.quantizationBits = buffer.readUint8();
      if (attribute.quantizationBits < 2 || attribute.quantizationBits > 30) {
        _fail('${attribute.quantizationBits}-bit octahedral quantisation');
      }
      if (attribute.components != 3) {
        _fail('an octahedral normal with ${attribute.components} components');
      }
  }
}

/// From stored values to one run of floats per point.
///
/// **This is where a value stops being shared.** The stream stores a normal
/// once however many points use it; the mesh handed back has one per point,
/// because that is the shape an index buffer addresses.
DracoAttribute _toPoints(_Attribute attribute, _Layout layout, int pointCount) {
  final components = attribute.components;
  final stored = _storedValues(attribute, layout.entries);
  final pointToValue = layout.pointToValue;

  final values = Float32List(pointCount * components);
  final integers = attribute.dataType.integral
      ? Int32List(pointCount * components)
      : null;
  for (var point = 0; point < pointCount; point++) {
    final from = (pointToValue?[point] ?? point) * components;
    for (var c = 0; c < components; c++) {
      final value = stored[from + c];
      values[point * components + c] = value.toDouble();
      integers?[point * components + c] = value.toInt();
    }
  }
  return DracoAttribute(
    type: attribute.type,
    components: components,
    values: values,
    integers: integers,
  );
}

/// One run of `components` numbers per *stored* value, transforms undone.
List<num> _storedValues(_Attribute attribute, int entries) {
  final components = attribute.components;
  switch (attribute.coding) {
    case _Coding.generic:
      final raw = attribute.raw;
      final type = attribute.dataType;
      return <num>[
        for (var i = 0; i < entries * components; i++)
          switch (type) {
            _DataType.int8 => raw.getInt8(i),
            _DataType.uint8 => raw.getUint8(i),
            _DataType.int16 => raw.getInt16(i * 2, Endian.little),
            _DataType.uint16 => raw.getUint16(i * 2, Endian.little),
            _DataType.int32 => raw.getInt32(i * 4, Endian.little),
            _DataType.uint32 => raw.getUint32(i * 4, Endian.little),
            _DataType.float32 => raw.getFloat32(i * 4, Endian.little),
          },
      ];

    case _Coding.integer:
      return attribute.portable;

    case _Coding.quantization:
      // `maxQuantized` steps across `range`, from the box's minimum corner.
      final out = Float32List(entries * components);
      final step = attribute.range / ((1 << attribute.quantizationBits) - 1);
      for (var i = 0; i < out.length; i++) {
        out[i] =
            attribute.minValues[i % components] + attribute.portable[i] * step;
      }
      return out;

    case _Coding.normals:
      // Normals leave octahedral space here, which is where two integers
      // become three floats.
      final box = OctahedronToolBox(attribute.quantizationBits);
      final out = Float32List(entries * 3);
      for (var i = 0; i < entries; i++) {
        box.toUnitVector(
          attribute.portable[i * 2],
          attribute.portable[i * 2 + 1],
          out,
          i * 3,
        );
      }
      return out;
  }
}
