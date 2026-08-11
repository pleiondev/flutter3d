/// Vertex and index storage the device already holds, and the geometry that
/// has some.
///
/// **Nothing in `graphics/` may import `flutter_gpu`** —
/// `test/graphics_is_backend_free_test.dart` enforces it.
library;

/// A range of device memory holding vertices or indices.
///
/// The engine only ever does two things with one: bind the whole of a mesh's
/// buffer, or bind a prefix of a buffer that only grows — the identity index
/// sequence the debug overlay draws through. So this is a range rather than a
/// buffer, and [slice] is the only arithmetic on it.
///
/// Transient geometry — a batch of particle quads built this frame — does not
/// come through here at all. It goes to `CommandEncoder.bindVertexData`, which
/// takes bytes: where a frame's scratch vertices live until the GPU has read
/// them is a backend question, and answering it in the engine is what a
/// `HostBuffer` in an engine signature was.
final class GeometryBuffer {
  const GeometryBuffer({
    required this.backend,
    required this.offsetInBytes,
    required this.lengthInBytes,
  });

  /// The backend's own buffer object. See `TextureHandle.backend`.
  final Object backend;

  final int offsetInBytes;
  final int lengthInBytes;

  /// A shorter range starting [offset] bytes into this one.
  GeometryBuffer slice({int offset = 0, required int length}) => GeometryBuffer(
        backend: backend,
        offsetInBytes: offsetInBytes + offset,
        lengthInBytes: length,
      );

  @override
  String toString() => 'GeometryBuffer(@$offsetInBytes, $lengthInBytes bytes)';
}
