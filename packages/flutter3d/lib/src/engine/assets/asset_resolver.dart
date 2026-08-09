import 'dart:typed_data';

/// Resolves a URI referenced from inside an asset to its bytes.
///
/// A callback rather than direct file access so the decoders need neither
/// `dart:io` nor the Flutter asset bundle: that is what lets them run in plain
/// unit tests, on any platform, and inside an isolate.
///
/// Shared by every format that can reference sibling files — glTF buffers and
/// images, OBJ material libraries and their textures.
typedef AssetUriResolver = Future<Uint8List> Function(String uri);
