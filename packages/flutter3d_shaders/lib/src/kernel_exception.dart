import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException;

/// Kernel language source that is not a kernel: a word the language does
/// not have, a type that does not fit, a write to a buffer declared read —
/// with the [line] and [column] of the first thing that is wrong.
final class ComputeKernelException extends Flutter3dFormatException {
  /// The mistake [reason], first found at [line] and [column].
  const ComputeKernelException(
    this.reason, {
    required this.line,
    required this.column,
  });

  /// What is wrong, as a sentence.
  final String reason;

  /// Where, counted from one.
  final int line;

  /// See [line].
  final int column;

  @override
  String get message => 'line $line, column $column: $reason';

  @override
  String toString() => 'ComputeKernelException: $message';
}
