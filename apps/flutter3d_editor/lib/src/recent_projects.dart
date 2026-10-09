import 'dart:convert';

import 'package:flutter3d_app/flutter3d_app.dart'
    show Storage, StorageException, defaultStorage;

/// The documents this editor has had open, most recent first.
///
/// **A file dialogue answers the question once and asks it again every
/// launch.** What a person actually does is come back to the two or three
/// projects they are working on, so choosing the same file out of the same
/// folder is the thing they would be made to do most — which is the work this
/// list exists to take away. Every document that opens is written down, and the
/// screen that offers templates offers these beside them.
///
/// Kept through the same [Storage] a game keeps its settings in, and for its
/// reasons rather than out of tidiness: the directory is per platform and was
/// wrong on two of four before that file existed, a read that finds nothing is
/// a first launch instead of a failure, and a write goes through a temporary
/// and a rename so a crash cannot leave half a list.
///
/// **Nothing here reaches a plugin or a window.** The open panel is one
/// function in `editor_chooser.dart`; what a stored document still means, which
/// order the paths go in and which of them have been deleted since are all
/// decided here, which is why they are tested against a map in memory.
final class RecentProjects {
  RecentProjects({Storage? storage})
    : storage = storage ?? defaultStorage(appName);

  /// Which application this list belongs to, and so which directory it sits
  /// in. Two programs sharing one document would each overwrite the other's.
  static const String appName = 'flutter3d_editor';

  /// Beside `settings.json`, which is the point of saying it out loud: an
  /// editor's recent projects are the same kind of thing as a player's volume
  /// — small, this machine's, and no loss if it goes.
  static const String _name = 'recent.json';

  /// The file's version. A document without one is version 1, and a newer
  /// one offers nothing rather than being misread.
  static const int formatVersion = 1;

  /// The envelope every flutter3d document starts with.
  static const Map<String, Object?> envelope = <String, Object?>{
    'format': 'f3d.editor-recent',
    'version': formatVersion,
    'requires': <String>[],
    'generator': 'flutter3d_editor',
  };

  /// The top-level keys of [text] this version does not write, so a list
  /// saved by a later editor keeps what that editor added.
  static Map<String, Object?> unknownIn(String? text) {
    if (text == null) return const <String, Object?>{};
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) return const <String, Object?>{};
      return <String, Object?>{
        for (final MapEntry(:key, :value) in json.entries)
          if (!envelope.containsKey(key) && key != 'recent') key: value,
      };
    } on FormatException {
      return const <String, Object?>{};
    }
  }

  /// How many are kept.
  ///
  /// **A list nobody scrolls.** Eight is about as many projects as fit on the
  /// screen beside four templates, and a recent list long enough to need
  /// searching has stopped being a shortcut and become a second file dialogue.
  static const int keep = 8;

  final Storage storage;

  /// The paths worth offering, most recent first.
  ///
  /// [exists] is injected so this can be answered without a disk — the same
  /// seam `Documents.find` uses next door, and for the same reason.
  Future<List<String>> read({required bool Function(String) exists}) async =>
      remaining(await storage.read(_name), exists: exists);

  /// Puts [path] at the front, writes the list back, and answers with it.
  ///
  /// The write is allowed to fail and is not reported: a recent list that could
  /// not be saved costs somebody one extra trip through the open panel, and an
  /// editor that refused to open a level because it could not write a
  /// convenience file would be trading the work for the shortcut.
  Future<List<String>> remember(
    String path, {
    required bool Function(String) exists,
  }) async {
    final text = await storage.read(_name);
    final paths = after(remaining(text, exists: exists), path);
    await _keep(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        ...envelope,
        // What a later version of this file added, kept as it was.
        ...unknownIn(text),
        'recent': paths,
      }),
    );
    return paths;
  }

  /// Forgets every project, which is what a person clearing the list means.
  Future<void> clear() => storage.remove(_name);

  Future<void> _keep(String text) async {
    try {
      await storage.write(_name, text);
    } on StorageException {
      return;
    }
  }

  /// What a stored document still means, which is never quite what it says.
  ///
  /// **A project that has been moved, renamed or deleted is not a project any
  /// more**, and offering it is offering a row that fails when clicked. So the
  /// disk decides, on every read, rather than the list being pruned by
  /// whatever noticed the loss.
  ///
  /// Never throws. A missing document is a first launch; one that will not
  /// parse is a half-written file or a hand edit that lost a brace, and in both
  /// cases an empty list is right and a program that will not start is not.
  static List<String> remaining(
    String? text, {
    required bool Function(String) exists,
  }) {
    if (text == null) return const <String>[];
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) return const <String>[];
      final format = json['format'];
      final version = json['version'];
      if ((format != null && format != envelope['format']) ||
          (version is num && version > formatVersion)) {
        return const <String>[];
      }
      final stored = json['recent'];
      if (stored is! List<Object?>) return const <String>[];
      // A set, so a document that somehow lists one project twice offers it
      // once — and a set literal keeps the order it was written in, which is
      // the order this whole file is about.
      return <String>{
        for (final path in stored.whereType<String>())
          if (exists(path)) path,
      }.take(keep).toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  /// [paths] with [opened] at the front, no second copy of it anywhere, and no
  /// more than [keep] of them.
  ///
  /// Opening one that is already in the list moves it rather than adding it: a
  /// list where the project somebody works in every day appears eight times is
  /// a list with room for nothing else.
  static List<String> after(List<String> paths, String opened) => <String>[
    opened,
    for (final path in paths)
      if (path != opened) path,
  ].take(keep).toList(growable: false);
}
