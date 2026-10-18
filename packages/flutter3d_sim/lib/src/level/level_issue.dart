import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Severity;

/// Something wrong with a level, and where to look for it.
///
/// In its own file so an [EntityKind] can report one without importing the
/// validator that collects them — the validator asks the kinds, so the
/// dependency has to run one way only.
final class LevelIssue {
  /// An issue of [severity] saying [message], found at [where] when given.
  const LevelIssue(this.severity, this.message, {this.where});

  /// How bad it is: an error stops a level from being played, a warning
  /// does not.
  final Severity severity;

  /// What is wrong, as a sentence for the level's author.
  final String message;

  /// Where to look: `entities[4] door "north"`, `brushes[17]`.
  final String? where;

  /// Whether [severity] is [Severity.error].
  bool get isError => severity == Severity.error;

  @override
  String toString() =>
      '${severity.name.toUpperCase()}${where == null ? '' : ' $where'}: '
      '$message';
}
