import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/storage_native.dart' show applicationDirectory;
import 'photo_shelf.dart';

/// Where a game's photos go on this platform, or null where nothing can be
/// worked out.
///
/// **The player's own Pictures folder on a desktop**, in a folder named after
/// the game, because that is where a person looks for a screenshot and the
/// game's settings folder is somewhere they never look. A sandboxed macOS
/// build's `HOME` is its container, so this lands in the container's own
/// `Pictures` unless the application has the pictures entitlement — still a
/// folder the message names, but not the one the player opens.
///
/// **The game's own folder on a phone**, under `photos/`. Neither phone lets
/// an application write into the shared gallery without a plugin, and this
/// package takes none — see [PhotoShelf]. [FilePhotoShelf] says so in its
/// message rather than claiming the picture is in the gallery.
String? picturesDirectory({
  required String appName,
  required TargetPlatform platform,
  required Map<String, String> environment,
  required String temporary,
}) {
  final home = environment['HOME'];
  return switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.linux => home == null ? null : '$home/Pictures/$appName',
    TargetPlatform.windows => switch (environment['USERPROFILE']) {
      final profile? => '$profile\\Pictures\\$appName',
      null => null,
    },
    TargetPlatform.android ||
    TargetPlatform.iOS => switch (applicationDirectory(
      appName: appName,
      platform: platform,
      environment: environment,
      temporary: temporary,
    )) {
      final root? => '$root/photos',
      null => null,
    },
    TargetPlatform.fuchsia => null,
  };
}

/// Photos written as files into [directory], or into [picturesDirectory]
/// for [appName].
///
/// **Through a `.part` file and a rename**, as every other write in this
/// package goes: a game closed half way through a large capture leaves a
/// `.part` behind rather than a PNG that opens as half a picture.
final class FilePhotoShelf extends PhotoShelf {
  FilePhotoShelf({required this.appName, Directory? directory})
    : _given = directory;

  final String appName;
  final Directory? _given;

  Directory? _resolve() {
    if (_given != null) return _given;
    try {
      final path = picturesDirectory(
        appName: appName,
        platform: defaultTargetPlatform,
        environment: Platform.environment,
        temporary: Directory.systemTemp.path,
      );
      return path == null ? null : Directory(path);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<PhotoSaving> open(String name) async {
    final directory = _resolve();
    if (directory == null) {
      return _Nowhere('This platform has no folder to put "$name" in.');
    }
    try {
      await directory.create(recursive: true);
      final file = File('${directory.path}${Platform.pathSeparator}$name');
      final part = File('${file.path}.part');
      return _FileSaving(file, part, await part.open(mode: FileMode.write));
    } catch (error) {
      return _Nowhere(
        '"$name" could not be started in ${directory.path}: '
        '$error',
      );
    }
  }
}

final class _FileSaving extends PhotoSaving {
  _FileSaving(this.file, this.part, this.handle);

  final File file;
  final File part;
  final RandomAccessFile handle;
  Object? _failed;

  /// Writes as the bytes arrive, synchronously, so a strip is on disk before
  /// the next is drawn and the memory it took is free.
  @override
  void add(Uint8List bytes) {
    if (_failed != null) return;
    try {
      handle.writeFromSync(bytes);
    } catch (error) {
      _failed = error;
    }
  }

  @override
  Future<PhotoSaved> close() async {
    final failed = _failed;
    if (failed != null) {
      await abandon();
      return PhotoSaved(
        kept: false,
        message: 'The picture could not be written to ${file.path}: $failed',
      );
    }
    try {
      await handle.close();
      await part.rename(file.path);
      final phone =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      return PhotoSaved(
        kept: true,
        where: file.path,
        message: phone
            ? 'Saved in the game\'s own folder, ${file.path}. It is not in '
                  'the gallery: that needs the game to offer a share sheet.'
            : 'Saved to ${file.path}.',
      );
    } catch (error) {
      await abandon();
      return PhotoSaved(
        kept: false,
        message: 'The picture could not be written to ${file.path}: $error',
      );
    }
  }

  @override
  Future<void> abandon() async {
    try {
      await handle.close();
    } catch (_) {
      // Already closed by [close], which is how a failed close gets here.
    }
    try {
      if (part.existsSync()) await part.delete();
    } catch (_) {
      // A `.part` left behind is the documented failure, and harmless.
    }
  }
}

/// A shelf that could not be opened: takes the bytes and drops them, and
/// says why at the end.
final class _Nowhere extends PhotoSaving {
  _Nowhere(this.why);

  final String why;

  @override
  void add(Uint8List bytes) {}

  @override
  Future<PhotoSaved> close() async => PhotoSaved(kept: false, message: why);

  @override
  Future<void> abandon() async {}
}

/// The shelf a build outside the browser gets.
PhotoShelf defaultPhotoShelf(String appName) =>
    FilePhotoShelf(appName: appName);
