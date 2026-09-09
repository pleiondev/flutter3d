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
    // Percent-encoded text payloads are legal but never used for glTF binary
    // data; decoding them as UTF-8 would silently corrupt buffers.
    return Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
  }
  return base64Decode(payload);
}

String _clip(String value) =>
    value.length <= 48 ? value : '${value.substring(0, 48)}…';
