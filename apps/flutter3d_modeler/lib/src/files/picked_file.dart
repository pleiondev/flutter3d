/// A file that arrived from outside the application.
///
/// One type for both platforms, because what a caller needs is the same on
/// both: the bytes, a name to show, and — where there is one — the path it came
/// from, so "save" can mean "save over that" rather than "ask again". A browser
/// has no path and says so with null, which is a case the caller has to handle
/// anyway.
library;

import 'dart:typed_data';

final class PickedFile {
  const PickedFile({required this.name, required this.bytes, this.path});

  /// What to show in a title bar. Never a path — a browser has none.
  final String name;

  final Uint8List bytes;

  /// Where it came from, or null in a browser.
  ///
  /// **A path under the macOS sandbox is not a licence to read it later.** The
  /// grant is for the file the person chose, in this run; keeping the string
  /// and opening it next launch is what fails with `PathAccessException` on a
  /// path that is plainly there. See `doc/model-editor.md` §6 for the
  /// measurement that says so.
  final String? path;
}

/// How a save went, which is a question with three answers rather than two.
enum SaveOutcome {
  /// The bytes reached a file, or a download.
  written,

  /// Somebody dismissed the picker. Not an error, and not a success either:
  /// a caller that treats it as failure shows an alarming message for a thing
  /// the person deliberately did.
  cancelled,

  /// The platform refused. The sentence is in [SaveResult.said].
  refused,
}

final class SaveResult {
  const SaveResult(this.outcome, {this.path, this.said});

  final SaveOutcome outcome;

  /// Where it landed, when the platform has paths and the save succeeded.
  final String? path;

  /// What went wrong, when it did.
  final String? said;

  static const SaveResult cancelled = SaveResult(SaveOutcome.cancelled);
}
