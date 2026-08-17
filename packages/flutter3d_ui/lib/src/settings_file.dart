import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
// One type is all this file wants out of the game layer.
import 'package:flutter3d_game/flutter3d_game.dart' show GameConfig;

import 'storage/storage.dart';

/// Where a game keeps what the player changed.
///
/// The stored half of [GameConfig], and nothing more: which document, what goes
/// in it, and what to do when it is not there. **Where** it goes is [Storage]'s,
/// because that answer is per platform and was wrong on two of the four — see
/// that file, which carries the whole story.
///
/// Still no `path_provider`. Three platforms answer with an environment
/// variable and two with the parent of their temporary directory, which is a
/// documented assumption rather than a dependency, and it keeps this testable
/// with a map in memory.
final class SettingsFile {
  SettingsFile({required this.appName, Storage? storage})
      : storage = storage ?? defaultStorage(appName);

  /// Which game this is. Two applications sharing one document would have each
  /// overwrite the other's bindings, and finding that out takes a while because
  /// it only happens if you play both.
  final String appName;

  /// Where the document is kept, which differs per platform — see [Storage].
  final Storage storage;

  static const String _name = 'settings.json';

  /// Reads the config, or hands back defaults.
  ///
  /// **Never throws.** A missing document is the first run; an unreadable one is
  /// a disk that filled up mid-write or a hand edit that lost a brace, and in
  /// every one of those cases starting the game with default settings beats
  /// refusing to start. What is lost is a player's bindings, which is a bad day;
  /// what is avoided is a game that cannot be launched, which is a bug report
  /// nobody can act on.
  GameConfig read() {
    final text = storage.read(_name);
    if (text == null) return GameConfig();
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) return GameConfig();
      return GameConfig.fromJson(json);
    } catch (error) {
      debugPrint('settings: could not be read, using defaults ($error)');
      return GameConfig();
    }
  }

  /// Writes the config, and says whether it managed to.
  ///
  /// Indented, because this is a document a player may open and edit by hand —
  /// which `GameConfig.fromJson` is written to survive.
  bool write(GameConfig config) => storage.write(
        _name,
        const JsonEncoder.withIndent('  ').convert(config.toJson()),
      );

  /// Forgets everything the player has changed.
  void clear() => storage.remove(_name);
}
