/// Decodes `images` into still-encoded [EncodedImage]s.
///
/// **A part of `gltf_loader.dart`, not a file of its own**, for the same
/// reason as the rest of this pipeline's phases: it reads the private JSON
/// helpers (`_mapList`, `_asInt`, ...) declared at the bottom of
/// `gltf_loader.dart`, and those stay unexported by staying in the same
/// library.
part of 'gltf_loader.dart';

extension _GltfImages on GltfLoader {
  // ------------------------------------------------------------------- images

  Future<List<EncodedImage>> _decodeImages(
    Map<String, Object?> json,
    List<Uint8List> buffers,
    AssetUriResolver? resolveUri,
    List<String> warnings,
  ) async {
    final images = _mapList(json['images']);
    final bufferViews = _mapList(json['bufferViews']);
    final result = <EncodedImage>[];

    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      final name = image['name'];
      final mimeType = image['mimeType'];
      final uri = image['uri'];
      final bufferViewIndex = _asInt(image['bufferView']);

      Uint8List? bytes;
      if (uri is String) {
        if (uri.startsWith('data:')) {
          bytes = decodeDataUri(uri);
        } else if (resolveUri != null) {
          try {
            bytes = await resolveUri(uri);
          } catch (error) {
            warnings.add('images[$i] could not load "$uri": $error');
          }
        } else {
          warnings.add(
            'images[$i] points at "$uri" but no URI resolver was supplied.',
          );
        }
      } else if (bufferViewIndex != null &&
          bufferViewIndex >= 0 &&
          bufferViewIndex < bufferViews.length) {
        final view = bufferViews[bufferViewIndex];
        final bufferIndex = _asInt(view['buffer']) ?? 0;
        if (bufferIndex < buffers.length) {
          final offset = _asInt(view['byteOffset']) ?? 0;
          final length = _asInt(view['byteLength']) ?? 0;
          final buffer = buffers[bufferIndex];
          if (offset + length <= buffer.length) {
            bytes = Uint8List.sublistView(buffer, offset, offset + length);
          } else {
            warnings.add('images[$i] bufferView is out of range.');
          }
        }
      } else {
        warnings.add('images[$i] has neither uri nor bufferView.');
      }

      result.add(
        EncodedImage(
          name: name is String ? name : null,
          bytes: bytes ?? Uint8List(0),
          mimeType: mimeType is String ? mimeType : null,
        ),
      );
    }

    return result;
  }
}
