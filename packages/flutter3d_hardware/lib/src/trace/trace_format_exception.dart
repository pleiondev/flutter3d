import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException;

/// A `.f3dtrace` that is not one, is newer than this build reads, or names
/// something this build has no value for.
final class TraceFormatException extends Flutter3dFormatException {
  const TraceFormatException(this.message, {this.cause});

  @override
  final String message;

  @override
  final Object? cause;

  @override
  String toString() =>
      'TraceFormatException: $message'
      '${cause == null ? '' : ' (caused by $cause)'}';
}
