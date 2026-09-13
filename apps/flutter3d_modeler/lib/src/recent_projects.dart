import 'dart:convert';

import 'package:flutter3d_session/flutter3d_session.dart'
    show Storage, defaultStorage;

/// The model files this application has had open, most recent first —
/// `ui-15`'s own "недавние" half of the start screen.
///
/// **A file dialogue answers the question once and asks it again every
/// launch.** What a person actually does is come back to the two or three
/// models they are working on, so choosing the same file out of the same
/// folder is the thing they would be made to do most — which is the work this
/// list exists to take away. Every model that opens is written down, and the
/// start screen offers these beside "Open file" and "New project".
///
/// Kept through the same [Storage] `apps/flutter3d_editor`'s own
/// `RecentProjects` already keeps its projects in, and for its reasons rather
/// than out of tidiness: the directory is per platform, a read that finds
/// nothing is a first launch instead of a failure, and a write goes through a
/// temporary and a rename so a crash cannot leave half a list. This file
/// mirrors that one rather than sharing it, because the two applications keep
/// their own documents under their own [appName] and neither should see the
/// other's.
///
/// **Nothing here reaches a plugin or a window.** The open panel is the start
/// screen's own job; what a stored path still means, which order the paths go
/// in and which of them have been deleted since are all decided here, which is
/// why they are tested against a map in memory.
final class RecentModels {
  RecentModels({Storage? storage}) : storage = storage ?? defaultStorage(appName);

  /// Which application this list belongs to, and so which directory it sits
  /// in. Two programs sharing one document would each overwrite the other's.
  static const String appName = 'flutter3d_modeler';

  /// Beside whatever this application's own settings file is named, which is
  /// the point of saying it out loud: a modeller's recent files are the same
  /// kind of thing as a player's volume — small, this machine's, and no loss
  /// if it goes.
  static const String _name = 'recent.json';

  /// How many are kept.
  ///
  /// **A list nobody scrolls.** Eight is about as many models as fit on a
  /// start screen beside a "New project" card, and a recent list long enough
  /// to need searching has stopped being a shortcut and become a second file
  /// dialogue. `ui-15`'s own worked example.
  static const int keep = 8;

  final Storage storage;

  /// The paths worth offering, most recent first.
  ///
  /// [exists] is injected so this can be answered without a disk — the same
  /// seam `apps/flutter3d_editor`'s own `RecentProjects.read` uses, and for
  /// the same reason.
  List<String> read({required bool Function(String) exists}) =>
      remaining(storage.read(_name), exists: exists);

  /// Puts [path] at the front, writes the list back, and answers with it.
  ///
  /// The write is allowed to fail and is not reported: a recent list that
  /// could not be saved costs somebody one extra trip through the open panel,
  /// and a modeller that refused to open a file because it could not write a
  /// convenience list would be trading the work for the shortcut.
  List<String> remember(String path, {required bool Function(String) exists}) {
    final paths = after(read(exists: exists), path);
    storage.write(
      _name,
      const JsonEncoder.withIndent(
        '  ',
      ).convert(<String, Object?>{'recent': paths}),
    );
    return paths;
  }

  /// Forgets every model, which is what a person clearing the list means.
  void clear() => storage.remove(_name);

  /// What a stored path still means, which is never quite what it says.
  ///
  /// **A model that has been moved, renamed or deleted is not a model any
  /// more**, and offering it is offering a row that fails when clicked. So the
  /// disk decides, on every read, rather than the list being pruned by
  /// whatever noticed the loss.
  ///
  /// Never throws. A missing document is a first launch; one that will not
  /// parse is a half-written file or a hand edit that lost a brace, and in
  /// both cases an empty list is right and a program that will not start is
  /// not — `ui-15`'s own "битый JSON — пустой список".
  static List<String> remaining(
    String? text, {
    required bool Function(String) exists,
  }) {
    if (text == null) return const <String>[];
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) return const <String>[];
      final stored = json['recent'];
      if (stored is! List<Object?>) return const <String>[];
      // A set, so a document that somehow lists one model twice offers it
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
  /// more than [keep] of them — `ui-15`'s own "8 записей, без дублей".
  ///
  /// Opening one that is already in the list moves it rather than adding it: a
  /// list where the model somebody works on every day appears eight times is a
  /// list with room for nothing else.
  static List<String> after(List<String> paths, String opened) => <String>[
    opened,
    for (final path in paths)
      if (path != opened) path,
  ].take(keep).toList(growable: false);
}
