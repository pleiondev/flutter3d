import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show FormatDocument, FormatMigration, FormatSpec, Flutter3dFormatException;

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
final class ShareBundle extends FormatDocument {
  ShareBundle({
    required this.game,
    required this.level,
    this.run,
    this.title,
    super.unknown,
  }) : levelHash = contentDigestHex(level) {
    final run = this.run;
    if (run != null && run.levelHash != levelHash) {
      throw ShareFormatException(
        'the run was recorded in another version of the level '
        '(${run.levelHash}; the level being shared is $levelHash) — record '
        'it again in this one',
      );
    }
  }

  /// Bumped when an existing field changes meaning, with a step in
  /// [_migrations] and a fixture under `test/fixtures/v<N>/`.
  static const int formatVersion = 1;

  /// Entry `i` lifts a bundle from version `i + 1` to `i + 2`; empty while
  /// version 1 is the only one, so reading it is the identity.
  static const List<FormatMigration> _migrations = <FormatMigration>[];

  /// The share bundle in the registry: `f3d.share`. The envelope is
  /// additive at version 1 — a build from before it ignores the three keys.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.share',
    version: formatVersion,
    suffixes: <String>['.share.json'],
    fixture: 'test/fixtures/v<N>/first.share.json',
    migrations: _migrations,
  );

  @override
  FormatSpec get spec => format;

  static const Set<String> _known = <String>{
    'game',
    'title',
    'levelHash',
    'level',
    'run',
  };

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

  Map<String, Object?> toJson() => write(<String, Object?>{
    'game': game,
    if (title != null) 'title': title,
    'levelHash': levelHash,
    'level': level,
    if (run != null) 'run': run!.toJson(),
  });

  /// Reads a bundle, or throws a [ShareFormatException] that says why not.
  ///
  /// [levelHash] is read and compared rather than trusted: a bundle edited by
  /// hand after it was written names a version of the level it does not hold.
  factory ShareBundle.fromJson(Map<String, Object?> json) =>
      ShareBundle._read(json);

  factory ShareBundle._read(Map<String, Object?> document) {
    final version = document['version'];
    if (version is! num || version < 1) {
      throw const ShareFormatException('the bundle has no version in it');
    }
    // A newer version, another format's document or a `requires` this build
    // does not know is refused by the spec; every older format is lifted
    // through [_migrations] before a field is read (decision 8 of
    // `tasks/1.0-stability.md`).
    final json = format.open(document, refuse: ShareFormatException.new);
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
      unknown: FormatDocument.unknownIn(json, known: _known),
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
final class ShareFormatException extends Flutter3dFormatException {
  const ShareFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'ShareFormatException: $message';
}
