/// Vertex and index storage the device already holds, and the geometry that
/// has some.
///
/// **Nothing here may import a graphics API** — `tool/structure.dart` holds it.
library;

/// What a buffer will be bound as.
///
/// **Not a hint.** One backend cannot infer it and cannot change its mind:
/// WebGL binds a buffer to its target for life, so a buffer uploaded as
/// vertices can never afterwards be bound as indices — the attempt is an
/// `INVALID_OPERATION`, the draw is dropped, and the frame comes back the clear
/// colour with nothing logged anywhere.
///
/// flutter_gpu has no such split: a `DeviceBuffer` is untyped and a
/// `BufferView` binds either way, which is why the contract went without this
/// until a second backend was written against it. The engine has always known
/// which it was uploading, so saying so costs a word at each call site.
enum GeometryUsage {
  /// Interleaved vertex attributes.
  vertices,

  /// Indices, of the width the draw will name.
  ///
  /// Plural to stay clear of `Enum.index`, which every enum already has.
  indices,
}

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
///
/// **Ended with [dispose], since 1.0**, the verb every GPU resource answers
/// to — `TextureHandle.dispose` is its twin. `GraphicsDevice.releaseGeometry`
/// stays as the device's half, for backends and the engine's own owners.
final class GeometryBuffer {
  GeometryBuffer._(
    this._release, {
    required this.backend,
    required this.offsetInBytes,
    required this.lengthInBytes,
  });

  final void Function(GeometryBuffer)? _release;

  /// Gives this buffer back to the device that made it, once; a second call
  /// does nothing. **A [slice] is a view** and its `dispose` does nothing:
  /// dispose the buffer it was cut from. A buffer a backend made without
  /// naming its device (a storage buffer's view, a test's fake) has nothing
  /// to give back.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _release?.call(this);
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  /// The backend's own buffer object. See `TextureHandle.backend`.
  final Object backend;

  final int offsetInBytes;
  final int lengthInBytes;

  /// A shorter range starting [offset] bytes into this one.
  GeometryBuffer slice({int offset = 0, required int length}) =>
      GeometryBuffer._(
        null,
        backend: backend,
        offsetInBytes: offsetInBytes + offset,
        lengthInBytes: length,
      );

  @override
  String toString() => 'GeometryBuffer(@$offsetInBytes, $lengthInBytes bytes)';
}

/// A [GeometryBuffer] over [lengthInBytes] bytes of a backend's own
/// [backend] buffer from [offsetInBytes] — for a backend, from
/// `package:flutter3d_hardware/backend.dart`. [release] is what the buffer's
/// [GeometryBuffer.dispose] calls — the device's `releaseGeometry` for a
/// buffer `uploadGeometry` made, and null for a view of something else.
GeometryBuffer wrapGeometry({
  required Object backend,
  required int offsetInBytes,
  required int lengthInBytes,
  void Function(GeometryBuffer)? release,
}) => GeometryBuffer._(
  release,
  backend: backend,
  offsetInBytes: offsetInBytes,
  lengthInBytes: lengthInBytes,
);
