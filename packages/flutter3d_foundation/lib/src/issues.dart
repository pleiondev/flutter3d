/// What a library reports that it could not do, and where it says it.
///
/// **Here because this is the package every other one can depend on.** The
/// type lived in `flutter3d_app`, and the audio packages, which name no
/// renderer and no application, kept an identical class of their own beside
/// it (`AudioIssue`), so a game routing both to one screen held two types for
/// one sentence. `flutter3d_app` still exports this one, with its
/// `printIssue` and `IssueLog` beside it.
library;

/// What a library is reporting.
///
/// **One object rather than a bare string, so this can grow.** A function type
/// is frozen the day it is published: adding a severity, or which subsystem
/// spoke, means widening `void Function(String)` and breaking every sink
/// anybody has written. Adding a field here does not.
final class Issue {
  const Issue(this.message, {this.severity = Severity.warning});

  /// What went wrong, in a sentence a person can read.
  final String message;

  /// How much it matters; a warning unless the library says otherwise.
  final Severity severity;

  @override
  String toString() => message;
}

/// Where a library says what it could not do: the application decides what
/// to do with it.
typedef IssueSink = void Function(Issue issue);

/// Roughly how much an issue matters: the one severity a mesh check, an
/// export, a level's validation and a library's [Issue] all speak in.
///
/// Three levels is what a panel shows and a person can triage today. The set
/// is open all the same, because a severity is a tier, and tiers are where a
/// later release finds it wants one more.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class Severity {
  const Severity._(this.name);

  /// Worth knowing. A boundary edge on a plane, an n-gon in a file.
  static const Severity note = Severity._('note');

  /// Probably not what somebody meant. Vertices in the same place, a shell
  /// wound inside out, a level whose spawn is in a wall.
  static const Severity warning = Severity._('warning');

  /// Will not survive being drawn, written out or played. A face with no
  /// area, a level with no way to start.
  static const Severity error = Severity._('error');

  /// Every value this version names, from the least to the most serious. A
  /// later version appends; nothing is removed or renamed within a major.
  static const List<Severity> values = <Severity>[note, warning, error];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static Severity? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  /// The position in [values]: stable within a major, appended only.
  int get index => values.indexOf(this);

  @override
  String toString() => 'Severity.$name';
}
