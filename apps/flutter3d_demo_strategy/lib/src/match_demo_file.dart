import 'dart:convert';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart'
    show MatchDemo;
import 'package:flutter3d_sim/flutter3d_sim.dart' show DemoFormatException;

import 'backend.dart'
    show Storage, StorageException, defaultStorage, printIssue;
import 'match_recording.dart' show RecordedMatch;

/// Where the last match is kept as what was ordered, the way `DemoFile` keeps
/// the other three genres' own last run.
///
/// **A file of its own rather than `DemoFile` reused.** That class reads and
/// writes `Demo`, whose `tape` field is typed `InputTape` by name —
/// `OrderTape`'s own doc comment gives the full reason a shared document was
/// rejected for this genre's tape, and the same reason keeps the *file*
/// apart: a class that opened either would have to guess which one a
/// `.f3drun` on disk holds before it could read it, and `MatchDemo.fromJson`
/// already refuses to guess. One document, one reader.
final class MatchDemoFile {
  MatchDemoFile({required this.appName, Storage? storage, IssueSink? onIssue})
    : onIssue = onIssue ?? printIssue,
      storage = storage ?? defaultStorage(appName, onIssue: onIssue);

  /// Which game's demo this is. See `SaveFile.appName`.
  final String appName;

  /// Where the document is kept.
  final Storage storage;

  /// Where this says what it could not read.
  final IssueSink onIssue;

  static const String _name = 'demo${MatchDemo.fileExtension}';

  /// The last match, or null with a reason said through [onIssue].
  ///
  /// Never throws, on `DemoFile.read`'s own reasoning: a demo that cannot be
  /// read is a bug report that has to be written in words instead.
  Future<RecordedMatch?> read() async {
    final text = await storage.read(_name);
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) {
        onIssue(Issue('demo: the document is not an object'));
        return null;
      }
      return RecordedMatch.fromJson(json);
    } on DemoFormatException catch (error) {
      onIssue(Issue('demo: ${error.message}'));
      return null;
    } catch (error) {
      onIssue(Issue('demo: could not be read ($error)'));
      return null;
    }
  }

  /// Writes the match, with the loop's record beside it, and says whether
  /// it managed to.
  Future<bool> write(RecordedMatch match) async {
    final text = const JsonEncoder.withIndent('  ').convert(match.toJson());
    try {
      await storage.write(_name, text);
      return true;
    } on StorageException catch (error) {
      onIssue(Issue('demo: could not be written (${error.message})'));
      return false;
    }
  }

  /// Forgets the match.
  Future<void> clear() => storage.remove(_name);
}
