/// The format exceptions of this package's own readers, one per kind of
/// text they read.
///
/// **Each is a leaf of [Flutter3dFormatException]**, so a tool that reports
/// anything unreadable catches the family, and one that acts on a single kind
/// catches that leaf. Before 1.0 these readers threw `dart:core`'s bare
/// `FormatException`, which a caller could not tell from a `jsonDecode` or
/// `utf8.decode` failure in its own code. The manifest, the material build
/// and the round trip already had theirs (`ManifestFormatException`,
/// `MaterialBuildException`, `F3dRoundTripException`).
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dFormatException;

/// A source file `flutter3d convert` could not read: a PLY, USD, Godot or
/// Unity text file, an XML document or a ZIP archive that is damaged or not
/// what it says, a face that names a point the mesh does not have, or a file
/// no reader claims.
///
/// The converter catches it per input and writes [message] into that input's
/// report, so one unreadable file does not stop a directory.
final class SourceFormatException extends Flutter3dFormatException {
  const SourceFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'SourceFormatException: $message';
}

/// A `flutter3d convert` command line that could not be read: an option
/// missing its value, a value of the wrong shape, an option nobody knows.
///
/// `runConvertCommand` answers it with the usage text and exit code 2.
final class ConvertUsageException extends Flutter3dFormatException {
  const ConvertUsageException(this.message);

  @override
  final String message;

  @override
  String toString() => 'ConvertUsageException: $message';
}

/// A migration table (`lib/migrations/<from>_to_<to>.yaml`) that is not one.
final class MigrationTableException extends Flutter3dFormatException {
  const MigrationTableException(this.message);

  @override
  final String message;

  @override
  String toString() => 'MigrationTableException: $message';
}
