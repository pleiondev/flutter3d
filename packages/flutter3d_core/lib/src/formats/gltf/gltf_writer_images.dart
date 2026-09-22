/// Encodes `document.images` into glTF `images`, embedded in the GLB binary
/// chunk rather than referenced by URI — `writeGlb` promises one
/// self-contained file, and a `uri` pointing at a sibling that may not travel
/// with it would break that promise silently.
///
/// **A part of `gltf_writer.dart`**, to reach the same `_appendBufferView`
/// every other phase writes vertex data through.
part of 'gltf_writer.dart';

extension _GltfWriterImages on GltfWriter {
  List<Map<String, Object?>> _writeImages() => <Map<String, Object?>>[
    for (final image in document.images)
      <String, Object?>{
        'bufferView': _appendBufferView(image.bytes),
        'mimeType':
            image.mimeType ??
            sniffImageMimeType(image.bytes) ??
            'application/octet-stream',
        if (image.name != null) 'name': image.name,
      },
  ];
}
