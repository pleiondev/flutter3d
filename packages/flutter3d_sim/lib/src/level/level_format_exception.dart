import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dFormatException;

/// Raised when a document is not a level, or is one this build cannot read.
final class LevelFormatException extends Flutter3dFormatException {
  /// An exception saying, in [message], what was wrong with the document.
  const LevelFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'LevelFormatException: $message';
}
