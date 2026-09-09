import 'dart:typed_data';

/// Resolves a URI referenced from inside an asset to its bytes.
///
/// A callback rather than direct file access so the decoders need neither
/// `dart:io` nor the Flutter asset bundle: that is what lets them run in plain
/// unit tests, on any platform, and inside an isolate.
///
/// Shared by every format that can reference sibling files — glTF buffers and
/// images, OBJ material libraries and their textures.
typedef AssetUriResolver = Future<Uint8List> Function(AssetRequest request);

/// What a resolver is being asked for.
///
/// **One object rather than a bare string, so this can grow.** A function type
/// is frozen the day it is published: asking a resolver for a byte range, a
/// priority, or which format wants the file means widening
/// `Future<Uint8List> Function(String)`, and that breaks every resolver
/// anybody has written. Adding a field here does not.
///
/// Allocated per request, unlike the scratch a contact filter is handed —
/// resolving an asset is I/O, and one small object beside a file read is not
/// a cost worth a sentence anywhere but this one.
final class AssetRequest {
  const AssetRequest(this.uri);

  /// What was asked for, relative to whatever the resolver treats as its root.
  final String uri;

  @override
  String toString() => 'AssetRequest($uri)';
}
