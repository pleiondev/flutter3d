enum LevelIssueSeverity {
  /// The level will not play correctly. Loading should stop.
  error,

  /// The level will play, and somebody probably did not mean this.
  warning,
}

/// Something wrong with a level, and where to look for it.
///
/// In its own file so an [EntityKind] can report one without importing the
/// validator that collects them — the validator asks the kinds, so the
/// dependency has to run one way only.
final class LevelIssue {
  const LevelIssue(this.severity, this.message, {this.where});

  final LevelIssueSeverity severity;
  final String message;

  /// Where to look: `entities[4] door "north"`, `brushes[17]`.
  final String? where;

  bool get isError => severity == LevelIssueSeverity.error;

  @override
  String toString() =>
      '${severity.name.toUpperCase()}${where == null ? '' : ' $where'}: '
      '$message';
}
