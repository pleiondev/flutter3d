/// How a run ended, or that it has not.
///
/// ## Three enums, one skeleton
///
/// Every genre in this repository grew its own, and they say the same three
/// things in different words:
///
/// | | playing | ended badly | ended well |
/// |---|---|---|---|
/// | platformer | `running`, `fallen` | `lost` | `finished` |
/// | shooter | `playing` | `dead` | `complete` |
/// | racing | `countdown`, `running` | — | `finished` |
///
/// The extra members are real and stay where they are: `fallen` is one step
/// long and is the beat before a respawn, `countdown` is the grid with the
/// lights on. Neither is an *outcome*; both are moments inside "playing".
///
/// ## Why this is in the engine and not above it
///
/// A save file, a title card, a HUD and the code that decides whether to load
/// the next level all ask the same question, and all of them live above the
/// genre packages. But the answer has to be given *by* a genre package — and a
/// genre package depends on neither the renderer nor `flutter3d_game`, so
/// anything it must implement has to be down here with it.
///
/// Deliberately three values and not four today. "Ended, and I am not saying
/// how" is a state a screen cannot draw and a save cannot decide about, and
/// every caller that had one grew a second flag beside it within a week.
///
/// **An open class with constants, not an enum** (§A.2 of
/// `tasks/1.0-api-review.md`): a later minor may add an outcome — a draw, a
/// run abandoned — and a `switch` written against three values would stop
/// compiling. A `switch` over this needs a default; ask [isOver] where the
/// question is whether it ended. [name] is its word in a file.
final class RunOutcome {
  const RunOutcome._(this.name, {required this.isOver});

  /// Being played, whatever the genre's own word for it is.
  static const RunOutcome playing = RunOutcome._('playing', isOver: false);

  /// Over, badly. The lives ran out, the health did, the time did.
  static const RunOutcome lost = RunOutcome._('lost', isOver: true);

  /// Over, well. The exit was reached, the flag was taken, the race finished.
  static const RunOutcome won = RunOutcome._('won', isOver: true);

  /// Every outcome this build knows, in the order the enum declared them.
  static const List<RunOutcome> values = <RunOutcome>[playing, lost, won];

  /// The outcome written as [name]; null for a word this build does not
  /// know.
  static RunOutcome? byName(String name) {
    for (final outcome in values) {
      if (outcome.name == name) return outcome;
    }
    return null;
  }

  /// Its word in a file and a message.
  final String name;

  /// Whether the run has ended, either way.
  ///
  /// The question two thirds of the callers actually ask — a pause gate, a
  /// restart key, a save that must not be written — and the one that is wrong
  /// to spell as `!= playing` in each of them.
  final bool isOver;

  @override
  String toString() => 'RunOutcome.$name';
}
