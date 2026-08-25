/// Raised when a document is not a level, or is one this build cannot read.
final class LevelFormatException implements Exception {
  const LevelFormatException(this.message);

  final String message;

  @override
  String toString() => 'LevelFormatException: $message';
}
