import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
// One type is all this file wants out of the game layer.
import 'package:flutter3d_game/flutter3d_game.dart' show GameConfig;

/// Where this game keeps what the player changed.
///
/// The file half of [GameConfig], and it is here rather than in a package
/// because the answer is per-application and per-platform: a sandboxed macOS
/// app writes inside its container, a test writes to a temporary directory,
/// and a package that picked one of those for everybody would be wrong for the
/// other two.
///
/// No `path_provider`. `HOME` inside a sandboxed macOS app is already the
/// container, so the usual place resolves correctly without a dependency —
/// which the repository's dependency policy asks for, and which keeps this
/// testable with nothing but a directory.
final class SettingsFile {
  SettingsFile({required this.appName, Directory? directory})
      : _given = directory;

  /// The directory this game keeps its settings in, under the usual place.
  ///
  /// A parameter since the second game arrived: two applications sharing one
  /// settings file would have each overwrite the other's bindings, and finding
  /// that out takes a while because it only happens if you play both.
  final String appName;

  final Directory? _given;

  /// Resolved on first use rather than in the constructor.
  ///
  /// `Platform.environment` is unavailable where there is no filesystem — a web
  /// build throws `UnsupportedError` on the way past it — and resolving it
  /// eagerly turned that into a game that never drew a frame. Deferred, the
  /// throw happens inside [read] and [write], which already promise never to
  /// throw and already fall back to defaults.
  late final Directory directory = _given ??
      Directory('${_home()}/Library/Application Support/$appName');

  File get file => File('${directory.path}/settings.json');

  /// Reads the config, or hands back defaults.
  ///
  /// **Never throws.** A missing file is the first run; an unreadable one is a
  /// disk that filled up mid-write or a hand edit that lost a brace, and in
  /// every one of those cases starting the game with default settings beats
  /// refusing to start. What is lost is a player's bindings, which is a bad
  /// day; what is avoided is a game that cannot be launched, which is a bug
  /// report nobody can act on.
  GameConfig read() {
    try {
      if (!file.existsSync()) return GameConfig();
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, Object?>) return GameConfig();
      return GameConfig.fromJson(json);
    } catch (error) {
      debugPrint('settings: could not be read, using defaults ($error)');
      return GameConfig();
    }
  }

  /// Writes the config, and says whether it managed to.
  ///
  /// Through a temporary file and a rename, because the alternative is that a
  /// crash halfway through a write leaves a half-written settings file that
  /// [read] then refuses — turning one lost session into every future one.
  bool write(GameConfig config) {
    try {
      directory.createSync(recursive: true);
      final temporary = File('${file.path}.new');
      temporary.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(config.toJson()),
        flush: true,
      );
      temporary.renameSync(file.path);
      return true;
    } catch (error) {
      debugPrint('settings: could not be written ($error)');
      return false;
    }
  }

  static String _home() =>
      Platform.environment['HOME'] ?? Directory.current.path;
}
