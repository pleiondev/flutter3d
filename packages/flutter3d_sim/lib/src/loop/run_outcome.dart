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
/// genre package depends on neither the renderer nor `flutter3d_screens`, so
/// anything it must implement has to be down here with it.
///
/// Deliberately three values and not four. "Ended, and I am not saying how" is
/// a state a screen cannot draw and a save cannot decide about, and every
/// caller that had one grew a second flag beside it within a week.
enum RunOutcome {
  /// Being played, whatever the genre's own word for it is.
  playing,

  /// Over, badly. The lives ran out, the health did, the time did.
  lost,

  /// Over, well. The exit was reached, the flag was taken, the race finished.
  won;

  /// Whether the run has ended, either way.
  ///
  /// The question two thirds of the callers actually ask — a pause gate, a
  /// restart key, a save that must not be written — and the one that is wrong
  /// to spell as `!= playing` in each of them, because that is the same
  /// sentence written four times with one chance each of being inverted.
  bool get isOver => this != RunOutcome.playing;
}
