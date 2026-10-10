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
  const Issue(this.message);

  /// What went wrong, in a sentence a person can read.
  final String message;

  @override
  String toString() => message;
}

/// Where a library says what it could not do: the application decides what
/// to do with it.
typedef IssueSink = void Function(Issue issue);
