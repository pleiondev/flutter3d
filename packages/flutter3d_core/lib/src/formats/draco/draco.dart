/// Draco mesh compression — `gfx-82n`: the `KHR_draco_mesh_compression` payload
/// a glTF primitive points at, decoded to indices and attributes.
///
/// One entry point, [decodeDraco], and the rest is how it gets there:
/// `draco_buffer.dart` for the container and its two rANS entropy coders,
/// `draco_decoder.dart` for the header, the attributes and what is refused,
/// `draco_edgebreaker.dart` and `draco_corner_table.dart` for the connectivity
/// every real file uses, `draco_traversal.dart` for the order an edgebreaker
/// mesh stores its values in, `draco_prediction.dart` for how those values are
/// guessed before they are corrected, and `draco_octahedron.dart` for how a
/// normal is stored as two integers.
library;

export 'draco_buffer.dart' show DracoException;
export 'draco_decoder.dart';
