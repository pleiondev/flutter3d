/// The bundle, off the disk and polled — see `shader_source.dart`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'documents.dart';
import 'shader_source.dart';
import 'shader_watch.dart';

/// Loads the bundle [path] names and arranges to keep reading it, or null
/// when no bundle was named.
///
/// The path is looked for the way the level's is. A bundle named and not
/// found throws rather than being skipped: an editor asked to draw with a
/// file and drawing without it would look like the file having no effect,
/// which is the one thing this loop exists to make impossible.
Future<WatchedShaders?> openShaders(
  GraphicsDevice device,
  String path, {
  required List<String> from,
  required void Function(LoadedShaderLibrary library) onRefreshed,
  required void Function(ShaderBundleException refused) onRefused,
}) async {
  if (path.isEmpty) return null;
  final found = Documents.find(
    path,
    from: from,
    exists: (String path) => File(path).existsSync(),
  );
  if (found == null) {
    throw FileSystemException(
      Documents.couldNotFind(path, Documents.candidates(path, from: from)),
    );
  }
  final file = File(found);
  DateTime? modifiedAt() => file.existsSync() ? file.lastModifiedSync() : null;
  Future<ByteData> read() async =>
      (await file.readAsBytes()).buffer.asByteData();
  // The time first, the bytes second: a write that lands between the two
  // is then a change the first poll sees, rather than one that was
  // stamped as seen and never read. `ShaderWatch._seen` says why.
  final seen = modifiedAt();
  final library = await device.loadShaders(await read());
  final watch = ShaderWatch(
    library: library,
    seen: seen,
    modifiedAt: modifiedAt,
    readBytes: read,
    onRefreshed: () => onRefreshed(library),
    onRefused: onRefused,
  );
  return (library: library, start: watch.start, dispose: watch.dispose);
}
