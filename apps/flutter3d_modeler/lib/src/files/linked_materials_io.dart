/// The platform half of `ux-47`, where there is a filesystem to watch.
///
/// **`File.watch` rather than polling.** Every desktop this ships to has an
/// operating-system notification for "this file changed" — `FSEvents`,
/// `inotify`, `ReadDirectoryChangesW` — and `dart:io` already wraps all
/// three. Polling would mean choosing an interval, and every interval is
/// either a delay somebody notices or a `stat` a second for the length of a
/// session.
///
/// **The directory is watched, not the file.** An editor that saves by
/// writing a temporary file and renaming it over the original — which is
/// most of them, because that is how a save survives a crash — destroys the
/// inode a file watch is attached to, so the watch goes quiet after exactly
/// one save. Watching the folder and filtering by name survives the rename.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'linked_materials.dart' show LinkedMaterialHost;

/// The gap a burst of writes is collected over.
///
/// A save is rarely one event: a truncate and a write are two, and a
/// rename-over is three. Re-reading on each would run the command three
/// times for one save, which is three undo steps.
const Duration kLinkedMaterialSettle = Duration(milliseconds: 120);

/// What [LinkedMaterials] needs from a desktop.
LinkedMaterialHost linkedMaterialHost() =>
    (watch: _watch, read: _read, openInEditor: _openInEditor);

Stream<void> _watch(String path) {
  final Directory folder = File(path).parent;
  final String name = _nameOf(path);
  late StreamController<void> out;
  StreamSubscription<FileSystemEvent>? watching;
  Timer? settling;

  void fired(FileSystemEvent event) {
    final bool mine =
        _nameOf(event.path) == name ||
        (event is FileSystemMoveEvent &&
            event.destination != null &&
            _nameOf(event.destination!) == name);
    if (!mine) return;
    settling?.cancel();
    settling = Timer(kLinkedMaterialSettle, () {
      if (!out.isClosed) out.add(null);
    });
  }

  out = StreamController<void>(
    onListen: () {
      try {
        watching = folder.watch().listen(fired, onError: (Object _) {});
      } on FileSystemException {
        // A folder that cannot be watched — a network mount, a platform
        // without the notification API — is a folder whose files simply do
        // not hot-swap. Better than a crash on a link.
      }
    },
    onCancel: () async {
      settling?.cancel();
      await watching?.cancel();
    },
  );
  return out.stream;
}

Future<Uint8List?> _read(String path) async {
  try {
    return await File(path).readAsBytes();
  } on FileSystemException {
    return null;
  }
}

/// Hands [path] to whatever the desktop opens a `.fmat` with.
///
/// One command per platform, and none of them is a shell: the path goes to
/// the process as an argument rather than into a string somebody's file name
/// could put a quote in.
Future<bool> _openInEditor(String path) async {
  final (
    String program,
    List<String> arguments,
  ) = switch (Platform.operatingSystem) {
    'macos' => ('open', <String>[path]),
    'windows' => ('cmd', <String>['/c', 'start', '', path]),
    _ => ('xdg-open', <String>[path]),
  };
  try {
    final ProcessResult ran = await Process.run(program, arguments);
    return ran.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

String _nameOf(String path) => path.split(Platform.pathSeparator).last;
