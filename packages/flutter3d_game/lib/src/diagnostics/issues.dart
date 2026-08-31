import 'package:flutter/foundation.dart' show debugPrint;

/// Where a library says what it could not do.
///
/// **Twelve places in three packages swallowed a failure into `debugPrint`**:
/// a texture that would not decode, a model that would not load, a level that
/// would not read, a settings document that would not parse — and, the one
/// that costs a player something, **a save that could not be read, which
/// silently became a new game**. Every one of those is a fact the application
/// wants and the package cannot use: a package has no screen, and a game does.
///
/// So the package collects and the application decides. This is the same
/// arrangement `LoadedLevel.issues` already had, with the type it was missing.
///
/// The default is what the code did before — print it and carry on — so that
/// nothing regresses for a caller that has not thought about it yet.
typedef IssueSink = void Function(String issue);

/// Prints and carries on: the behaviour every one of these sites had.
void printIssue(String issue) => debugPrint(issue);

/// Collects issues instead of printing them.
///
/// For an application that wants to show what went wrong, and for a test that
/// wants to assert a failure was reported rather than hunt through console
/// output for it — which is the only reason half of these could not be tested
/// before.
final class IssueLog {
  final List<String> issues = <String>[];

  bool get isEmpty => issues.isEmpty;
  bool get isNotEmpty => issues.isNotEmpty;

  /// Pass this where an [IssueSink] is wanted.
  void add(String issue) => issues.add(issue);

  /// Everything said so far, as one block, or null when nothing was.
  String? get summary => issues.isEmpty ? null : issues.join('\n');

  void clear() => issues.clear();
}
