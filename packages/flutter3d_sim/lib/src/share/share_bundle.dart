import '../save/demo.dart';
import '../save/state_digest.dart';

/// A level somebody shares, and optionally a run through it — what a short
/// code stands for.
///
/// **A level, its hash and a `.f3drun`, and nothing a server could make up.**
/// The level is a document rather than a parsed [Level] so that any genre's
/// own format travels the same way — a level here, a track there — the way
/// [Demo.levelHash] already compares [contentDigestHex] of whatever document
/// recorded it. A reader that knows the format parses [level]; a server that
/// does not can still check the hash and store the bytes.
///
/// **The run is checked against the level before anything leaves.** A bundle
/// whose run was recorded in another version of the level is a ghost running
/// through walls, and it is refused here and again on the server with the two
/// hashes named, because the person who made it can fix it and the person who
/// opens it cannot.
///
/// The address a server files it under is not here: a 32-bit [StateDigest] is
/// right for telling two states apart and wrong for naming a document among
/// every document strangers upload, so the server takes a SHA-256 of the bytes
/// [toJson] writes.
final class ShareBundle {
  ShareBundle({required this.game, required this.level, this.run, this.title})
    : levelHash = contentDigestHex(level) {
    final run = this.run;
    if (run != null && run.levelHash != levelHash) {
      throw ShareFormatException(
        'the run was recorded in another version of the level '
        '(${run.levelHash}; the level being shared is $levelHash) — record '
        'it again in this one',
      );
    }
  }

  /// Bumped when an existing field changes meaning.
  static const int formatVersion = 1;

  /// What the game calls itself, so that a viewer knows which game opens it.
  final String game;

  /// The level document, as its own `toJson()` wrote it.
  final Map<String, Object?> level;

  /// [contentDigestHex] of [level]: which version of it this is.
  final String levelHash;

  /// A run through [level], or null for a level shared on its own.
  final Demo? run;

  /// What the person sharing it called it, or null.
  final String? title;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': formatVersion,
    'game': game,
    if (title != null) 'title': title,
    'levelHash': levelHash,
    'level': level,
    if (run != null) 'run': run!.toJson(),
  };

  /// Reads a bundle, or throws a [ShareFormatException] that says why not.
  ///
  /// [levelHash] is read and compared rather than trusted: a bundle edited by
  /// hand after it was written names a version of the level it does not hold.
  factory ShareBundle.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! num) {
      throw const ShareFormatException('the bundle has no version in it');
    }
    if (version > formatVersion) {
      throw ShareFormatException(
        'the bundle was written by a newer build (format $version, this build '
        'reads $formatVersion) — update flutter3d to open it',
      );
    }
    final game = json['game'];
    if (game is! String || game.isEmpty) {
      throw const ShareFormatException('the bundle names no game');
    }
    final level = json['level'];
    if (level is! Map<String, Object?>) {
      throw const ShareFormatException('the bundle has no level in it');
    }
    final title = json['title'];
    if (title != null && title is! String) {
      throw const ShareFormatException('the title is not text');
    }
    final rawRun = json['run'];
    if (rawRun != null && rawRun is! Map<String, Object?>) {
      throw const ShareFormatException('the run is not a document');
    }
    final Demo? run;
    try {
      run = rawRun == null
          ? null
          : Demo.fromJson(rawRun as Map<String, Object?>);
    } on DemoFormatException catch (error) {
      throw ShareFormatException('the run: ${error.message}');
    }
    final bundle = ShareBundle(
      game: game,
      level: level,
      run: run,
      title: title as String?,
    );
    final claimed = json['levelHash'];
    if (claimed != bundle.levelHash) {
      throw ShareFormatException(
        'the bundle says its level is $claimed, and the level in it is '
        '${bundle.levelHash}',
      );
    }
    return bundle;
  }
}

/// Thrown when a bundle cannot be read, or would not mean what it says.
final class ShareFormatException implements Exception {
  const ShareFormatException(this.message);

  final String message;

  @override
  String toString() => 'ShareFormatException: $message';
}
