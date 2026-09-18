/// Draco mesh compression — `gfx-82n`: the `KHR_draco_mesh_compression` payload
/// a glTF primitive points at, decoded to indices and attributes.
///
/// See `draco_buffer.dart` for the container and its rANS entropy coder,
/// `draco_decoder.dart` for what is decoded and what is refused, and
/// `draco_octahedron.dart` for how a normal is stored as two integers.
library;

export 'draco_buffer.dart' show DracoException;
export 'draco_decoder.dart';
