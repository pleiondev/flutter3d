import 'dart:convert';
import 'dart:typed_data';

import '../asset_resolver.dart';

/// A parsed glTF container: the JSON document plus the optional binary chunk.
final class GlbContainer {
  const GlbContainer({required this.json, this.binaryChunk});

  final Map<String, Object?> json;

  /// The GLB `BIN` chunk. Buffers with no `uri` refer to this.
  final Uint8List? binaryChunk;

  static const int _kMagic = 0x46546C67; // 'glTF'
  static const int _kChunkJson = 0x4E4F534A; // 'JSON'
  static const int _kChunkBin = 0x004E4942; // 'BIN\0'

  /// Detects the container form and parses it.
  ///
  /// `.glb` starts with the `glTF` magic; anything else is treated as `.gltf`
  /// JSON text.
  factory GlbContainer.parse(Uint8List bytes) {
    if (bytes.length >= 4) {
      final magic = ByteData.sublistView(
        bytes,
        0,
        4,
      ).getUint32(0, Endian.little);
      if (magic == _kMagic) return GlbContainer._parseBinary(bytes);
    }
    return GlbContainer._parseJson(bytes);
  }

  factory GlbContainer._parseJson(Uint8List bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (error) {
      throw FormatException('Not a glTF file: JSON parse failed ($error).');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('glTF root must be a JSON object.');
    }
    return GlbContainer(json: decoded);
  }

  factory GlbContainer._parseBinary(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const FormatException('GLB truncated: header needs 12 bytes.');
    }
    final data = ByteData.sublistView(bytes);
    final version = data.getUint32(4, Endian.little);
    final declaredLength = data.getUint32(8, Endian.little);

    if (version != 2) {
      throw FormatException('Unsupported GLB version $version, expected 2.');
    }
    // Trust the smaller of the two: a declared length beyond the actual buffer
    // would let chunk parsing read past the end.
    final totalLength = declaredLength <= bytes.length
        ? declaredLength
        : bytes.length;

    Map<String, Object?>? json;
    Uint8List? binary;
    var offset = 12;

    while (offset + 8 <= totalLength) {
      final chunkLength = data.getUint32(offset, Endian.little);
      final chunkType = data.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;
      final chunkEnd = chunkStart + chunkLength;

      if (chunkEnd > totalLength) {
        throw FormatException(
          'GLB chunk at $offset claims $chunkLength bytes but only '
          '${totalLength - chunkStart} remain.',
        );
      }

      switch (chunkType) {
        case _kChunkJson:
          final text = utf8.decode(
            Uint8List.sublistView(bytes, chunkStart, chunkEnd),
            allowMalformed: true,
          );
          final decoded = jsonDecode(text);
          if (decoded is! Map<String, Object?>) {
            throw const FormatException('GLB JSON chunk is not an object.');
          }
          json = decoded;
        case _kChunkBin:
          binary = Uint8List.sublistView(bytes, chunkStart, chunkEnd);
        default:
        // Unknown chunk types must be ignored per the spec, which is how
        // forward compatibility is supposed to work.
      }

      // Chunks are padded to a 4-byte boundary.
      offset = chunkEnd + ((4 - (chunkLength % 4)) % 4);
    }

    if (json == null) {
      throw const FormatException('GLB has no JSON chunk.');
    }
    return GlbContainer(json: json, binaryChunk: binary);
  }

  /// Encodes [json] and an optional [binary] chunk into a `.glb` file.
  ///
  /// The exact inverse of [_parseBinary]: a 12-byte header naming the total
  /// length, then the `JSON` chunk padded with spaces (the byte the spec
  /// requires for that chunk's padding, as opposed to zero for `BIN`), then
  /// the `BIN` chunk when there is one. Nothing here validates [json] against
  /// the schema — a writer that built a bad document gets a bad file back,
  /// which is what makes round-tripping through [GlbContainer.parse] a
  /// meaningful check of the writer rather than of this method.
  static Uint8List encode(Map<String, Object?> json, {Uint8List? binary}) {
    final jsonBytes = utf8.encode(jsonEncode(json));
    final jsonPadding = (4 - (jsonBytes.length % 4)) % 4;
    final binPadding = binary == null ? 0 : (4 - (binary.length % 4)) % 4;

    final total =
        12 +
        8 +
        jsonBytes.length +
        jsonPadding +
        (binary == null ? 0 : 8 + binary.length + binPadding);

    final out = BytesBuilder();
    final header = ByteData(12);
    header.setUint32(0, _kMagic, Endian.little);
    header.setUint32(4, 2, Endian.little);
    header.setUint32(8, total, Endian.little);
    out.add(header.buffer.asUint8List());

    final jsonHeader = ByteData(8);
    jsonHeader.setUint32(0, jsonBytes.length + jsonPadding, Endian.little);
    jsonHeader.setUint32(4, _kChunkJson, Endian.little);
    out.add(jsonHeader.buffer.asUint8List());
    out.add(jsonBytes);
    out.add(List<int>.filled(jsonPadding, 0x20));

    if (binary != null) {
      final binHeader = ByteData(8);
      binHeader.setUint32(0, binary.length + binPadding, Endian.little);
      binHeader.setUint32(4, _kChunkBin, Endian.little);
      out.add(binHeader.buffer.asUint8List());
      out.add(binary);
      out.add(List<int>.filled(binPadding, 0));
    }

    return out.toBytes();
  }

  /// Resolves every `buffers[i]` entry to its bytes.
  ///
  /// Three forms exist and all three appear in the wild: no `uri` at all (the
  /// GLB binary chunk), a `data:` URI with base64 payload, and a relative path
  /// next to the `.gltf` file.
  Future<List<Uint8List>> resolveBuffers({AssetUriResolver? resolveUri}) async {
    final buffers = json['buffers'];
    if (buffers is! List) return const <Uint8List>[];

    final result = <Uint8List>[];
    for (var i = 0; i < buffers.length; i++) {
      final buffer = buffers[i];
      if (buffer is! Map) {
        throw FormatException('buffers[$i] is not an object.');
      }
      final uri = buffer['uri'];

      if (uri == null) {
        final chunk = binaryChunk;
        if (chunk == null) {
          throw FormatException(
            'buffers[$i] has no uri but there is no GLB binary chunk. '
            'A .gltf file cannot omit the uri.',
          );
        }
        result.add(chunk);
        continue;
      }
      if (uri is! String) {
        throw FormatException('buffers[$i].uri is not a string.');
      }

      if (uri.startsWith('data:')) {
        result.add(decodeDataUri(uri));
        continue;
      }

      if (resolveUri == null) {
        throw FormatException(
          'buffers[$i] points at "$uri" but no URI resolver was supplied. '
          'Pass resolveUri to load .gltf files with external buffers.',
        );
      }
      result.add(await resolveUri(AssetRequest(uri)));
    }
    return result;
  }
}

/// Decodes a `data:` URI payload.
///
/// glTF uses several media types here (`application/octet-stream`,
/// `application/gltf-buffer`, `image/png`), so the type is ignored and only the
/// base64 payload matters.
Uint8List decodeDataUri(String uri) {
  final comma = uri.indexOf(',');
  if (comma < 0) {
    throw FormatException('Malformed data URI: no comma. "${_clip(uri)}"');
  }
  final meta = uri.substring(5, comma);
  final payload = uri.substring(comma + 1);

  if (!meta.contains('base64')) {
    // Percent-encoded payloads are legal and rare. Each `%XX` is one byte, so
    // they are unescaped straight to bytes — going through a UTF-8 string
    // would turn `%FF` into two bytes, or refuse it outright.
    return UriData.parse(uri).contentAsBytes();
  }
  return base64Decode(payload);
}

String _clip(String value) =>
    value.length <= 48 ? value : '${value.substring(0, 48)}…';
