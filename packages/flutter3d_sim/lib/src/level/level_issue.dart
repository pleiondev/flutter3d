/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class LevelIssueSeverity {
  const LevelIssueSeverity._(this.name);

  /// The level will not play correctly. Loading should stop.
  static const LevelIssueSeverity error = LevelIssueSeverity._('error');

  /// The level will play, and somebody probably did not mean this.
  static const LevelIssueSeverity warning = LevelIssueSeverity._('warning');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<LevelIssueSeverity> values = <LevelIssueSeverity>[
    error,
    warning,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static LevelIssueSeverity? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'LevelIssueSeverity.$name';
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
