import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d_game/flutter3d_game.dart' show Snapshot;

/// Where a run in progress is kept between launches.
///
/// The same shape as [SettingsFile] and for the same reason — the right
/// directory is per-application — but a separate file on purpose: settings are
/// what a player chose and a save is where they got to, and one of those must
/// survive a delete of the other. Wiping a corrupt save should not cost
/// somebody their key bindings.
///
/// **A save is a level and a snapshot together.** A snapshot restored into the
/// wrong level is worse than no save at all: the positions are real numbers
/// that mean nothing here, so the runner arrives inside a wall of a level they
/// were never in. So the level's asset path is stored beside it and checked on
/// the way back in.
final class SaveFile {
  SaveFile({Directory? directory}) : _given = directory;

  final Directory? _given;

  /// Resolved on first use rather than in the constructor.
  ///
  /// `Platform.environment` is unavailable where there is no filesystem — a web
  /// build throws `UnsupportedError` on the way past it — and resolving it
  /// eagerly turned that into a game that never drew a frame. Deferred, the
  /// throw happens inside [read] and [write], which already promise never to
  /// throw and already fall back to a fresh run.
  late final Directory directory = _given ??
      Directory('${_home()}/Library/Application Support/platformer');

  File get file => File('${directory.path}/save.json');

  /// The run that was saved, or null if there is nothing to resume.
  ///
  /// **Never throws**, on the same argument as [SettingsFile.read]: a save that
  /// cannot be read is a run that has to start again, and that is a much
  /// smaller loss than a game that will not launch.
  ({String level, Snapshot run})? read() {
    try {
      if (!file.existsSync()) return null;
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, Object?>) return null;
      final level = json['level'];
      final run = json['run'];
      if (level is! String || run is! Map<String, Object?>) return null;
      return (level: level, run: Snapshot(run));
    } catch (error) {
      debugPrint('save: could not be read, starting fresh ($error)');
      return null;
    }
  }

  /// Writes the run, and says whether it managed to.
  ///
  /// Through a temporary file and a rename, so a crash mid-write cannot leave
  /// a half-written save where a whole one used to be.
  bool write(String level, Snapshot run) {
    try {
      directory.createSync(recursive: true);
      final temporary = File('${file.path}.new');
      temporary.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(
          <String, Object?>{'level': level, 'run': run.data},
        ),
        flush: true,
      );
      temporary.renameSync(file.path);
      return true;
    } catch (error) {
      debugPrint('save: could not be written ($error)');
      return false;
    }
  }

  /// Forgets the run. Called when it ends, either way.
  ///
  /// A finished run left on disk is resumed on the next launch, and the player
  /// is put back on the last checkpoint of a level they already beat.
  void clear() {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (error) {
      debugPrint('save: could not be cleared ($error)');
    }
  }

  static String _home() =>
      Platform.environment['HOME'] ?? Directory.current.path;
}
