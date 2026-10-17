import 'dart:convert';

// One type is all this file wants out of the game layer.
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import '../config/game_config.dart';
import '../input/action_map.dart';

/// Where a game keeps what the player changed.
///
/// The stored half of [GameSettings], and nothing more: which document, what goes
/// in it, and what to do when it is not there. **Where** it goes is [Storage]'s,
/// because that answer is per platform and was wrong on two of the four — see
/// that file, which carries the whole story.
///
/// Still no `path_provider`. Three platforms answer with an environment
/// variable and two with the parent of their temporary directory, which is a
/// documented assumption rather than a dependency, and it keeps this testable
/// with a map in memory.
final class SettingsFile {
  SettingsFile({
    required this.appName,
    Storage? storage,
    IssueSink? onIssue,
    this.defaultActions,
  }) : onIssue = onIssue ?? printIssue,
       storage = storage ?? defaultStorage(appName, onIssue: onIssue);

  /// The game's own action map, which a saved map is read against — see
  /// [GameSettings.fromJson]. Null reads it over `ActionSet.common`.
  final ActionMap Function()? defaultActions;

  /// Which game this is. Two applications sharing one document would have each
  /// overwrite the other's bindings, and finding that out takes a while because
  /// it only happens if you play both.
  final String appName;

  /// Where the document is kept, which differs per platform — see [Storage].
  final Storage storage;

  /// Where this says what it could not read.
  ///
  /// Prints, unless the application wants to know — see [IssueSink]. A settings
  /// document that will not parse costs a player their bindings, and the game
  /// is the only thing here with a screen to say so on.
  final IssueSink onIssue;

  static const String _name = 'settings.json';

  /// Reads the config, or hands back defaults.
  ///
  /// **Never throws.** A missing document is the first run; an unreadable one is
  /// a disk that filled up mid-write or a hand edit that lost a brace, and in
  /// every one of those cases starting the game with default settings beats
  /// refusing to start. What is lost is a player's bindings, which is a bad day;
  /// what is avoided is a game that cannot be launched, which is a bug report
  /// nobody can act on.
  ///
  /// A file from before the format envelope is read as version 1 of
  /// [GameSettings.format] and lifted: its settings under their namespaced
  /// ids, its bindings into the action map.
  Future<GameSettings> read() async {
    final text = await storage.read(_name);
    if (text == null) return const GameSettings();
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) {
        // **This one said nothing at all**, which is worse than the `catch`
        // below: a document that parses as JSON and is not an object — a
        // stored `null`, a `[]`, a truncated write on a platform where the
        // atomic rename did not apply — went back as defaults with no word
        // anywhere, so a player whose bindings had just been silently reset
        // had nothing to report. `SaveFile.read` got this right next door and
        // says so in its own comment; the lesson did not cross the file.
        onIssue(
          Issue('settings: the document is not an object, using defaults'),
        );
        return const GameSettings();
      }
      return GameSettings.fromJson(json, defaultActions: defaultActions);
    } catch (error) {
      onIssue(Issue('settings: could not be read, using defaults ($error)'));
      return const GameSettings();
    }
  }

  /// Writes [settings] in the format envelope, and says whether it managed
  /// to; a refusal is said through [onIssue] as well.
  ///
  /// Indented, because this is a document a player may open and edit by hand —
  /// which `GameSettings.fromJson` is written to survive. The document is made
  /// now, when this is called; only the write waits.
  Future<bool> write(GameSettings settings) async {
    final text = const JsonEncoder.withIndent('  ').convert(settings.toJson());
    try {
      await storage.write(_name, text);
      return true;
    } on StorageException catch (error) {
      onIssue(Issue('settings: could not be written (${error.message})'));
      return false;
    }
  }

  /// Forgets everything the player has changed.
  Future<void> clear() => storage.remove(_name);
}
