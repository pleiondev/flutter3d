import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter3d_game/flutter3d_game.dart'
    show Issue, IssueSink, printIssue;

import 'atomic_write.dart';
import 'storage.dart';

/// Where this platform keeps a small document belonging to one application.
///
/// **A table rather than one path, because there is no one path.** The rules
/// below are each platform's own convention, and getting them from the
/// environment rather than from a plugin is what keeps this package free of
/// `path_provider` — the dependency policy in `ARCHITECTURE.md` asks for that, and
/// on three of the five it is genuinely just an environment variable.
///
/// The two mobile platforms are the interesting ones. Neither publishes its
/// container in the environment, but both set `TMPDIR`, and both put it **inside**
/// that container:
///
/// * Android: `/data/user/0/<package>/cache`, whose parent is the private data
///   directory that `files/` and `shared_prefs/` sit in;
/// * iOS: `<container>/tmp`, whose parent is the container.
///
/// So the parent of [temporary] is the root to build from. **That is an
/// assumption about the Flutter engine's own setup**, not a documented API, and
/// it is written down here rather than buried: if it ever stops holding, the
/// symptom is a game that cannot keep settings, which is exactly what this
/// replaced — no worse, and now with a name.
///
/// Returns null where nothing can be worked out, which a caller treats as "this
/// platform does not keep anything" rather than as a failure.
String? applicationDirectory({
  required String appName,
  required TargetPlatform platform,
  required Map<String, String> environment,
  required String temporary,
}) {
  final home = environment['HOME'];
  switch (platform) {
    case TargetPlatform.macOS:
      // A sandboxed application's `HOME` is its container, so this is inside it.
      return home == null ? null : '$home/Library/Application Support/$appName';
    case TargetPlatform.iOS:
      return '${_parent(temporary)}/Library/Application Support/$appName';
    case TargetPlatform.android:
      // Beside `files/`, which is where an Android application's own data goes.
      return '${_parent(temporary)}/files/$appName';
    case TargetPlatform.linux:
      final config =
          environment['XDG_CONFIG_HOME'] ??
          (home == null ? null : '$home/.config');
      return config == null ? null : '$config/$appName';
    case TargetPlatform.windows:
      final appData = environment['APPDATA'];
      return appData == null ? null : '$appData\\$appName';
    case TargetPlatform.fuchsia:
      return null;
  }
}

String _parent(String path) {
  final trimmed = path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  final cut = trimmed.lastIndexOf('/');
  return cut <= 0 ? trimmed : trimmed.substring(0, cut);
}

/// Documents kept as files, one per name, in a directory this platform owns.
final class FileStorage implements Storage {
  FileStorage({required this.appName, Directory? directory, IssueSink? onIssue})
    : _given = directory,
      onIssue = onIssue ?? printIssue;

  final String appName;
  final Directory? _given;

  /// Where this says what the platform would not let it do.
  ///
  /// A write that fails already comes back as `false`; what the boolean cannot
  /// carry is *why*, and "no such directory" and "the disk is full" are
  /// different days.
  final IssueSink onIssue;

  /// Resolved on first use rather than in the constructor.
  ///
  /// `Platform.environment` is unavailable where there is no filesystem, and
  /// resolving it eagerly turned that into a game that never drew a frame.
  /// Deferred, the failure lands inside a read or a write, which already promise
  /// never to throw.
  late final Directory? directory = _given ?? _resolve();

  Directory? _resolve() {
    try {
      final path = applicationDirectory(
        appName: appName,
        platform: defaultTargetPlatform,
        environment: Platform.environment,
        temporary: Directory.systemTemp.path,
      );
      return path == null ? null : Directory(path);
    } catch (error) {
      onIssue(Issue('storage: no directory on this platform ($error)'));
      return null;
    }
  }

  File? _file(String name) {
    final where = directory;
    return where == null ? null : File('${where.path}/$name');
  }

  @override
  String? read(String name) {
    try {
      final file = _file(name);
      if (file == null || !file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (error) {
      onIssue(Issue('storage: could not read $name ($error)'));
      return null;
    }
  }

  @override
  bool write(String name, String contents) {
    try {
      final where = directory;
      final file = _file(name);
      if (where == null || file == null) return false;
      where.createSync(recursive: true);
      // Through a temporary file and a rename — see [writeFileAtomicallySync],
      // which is where this now lives because the level editor needed the same
      // thing and had written the unsafe version instead.
      writeFileAtomicallySync(file.path, contents);
      return true;
    } catch (error) {
      onIssue(Issue('storage: could not write $name ($error)'));
      return false;
    }
  }

  @override
  void remove(String name) {
    try {
      final file = _file(name);
      if (file != null && file.existsSync()) file.deleteSync();
    } catch (error) {
      onIssue(Issue('storage: could not clear $name ($error)'));
    }
  }
}

/// The storage a build outside the browser gets.
Storage defaultStorage(String appName, {IssueSink? onIssue}) =>
    FileStorage(appName: appName, onIssue: onIssue);
