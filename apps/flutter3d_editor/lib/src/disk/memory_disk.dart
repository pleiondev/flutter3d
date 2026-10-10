/// Documents without the disk: the web build's files, kept in the page.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';

import 'editor_disk.dart';

/// A file a person picked: what it is called and what is in it. A browser
/// hands over nothing else — no path, no folder around it.
typedef PickedBytes = ({String name, Uint8List bytes});

/// Files held in memory, under paths that look like a disk's so that
/// `Documents`, `RecentProjects` and `projectAt` need not know.
///
/// **Three things a desktop does that a page cannot, and what is done
/// instead.**
///
///  * *Opening* is reading the bytes a person picked out of the browser's
///    own file dialogue into [opened], under the name it had. Nothing else
///    from the folder it came from comes with it, so a level picked on its
///    own draws without its game's textures — flat surfaces, each one named
///    in the level's issues, as a missing texture always is.
///  * *Saving* is a download of the document, by the name it was opened
///    with. The person's browser files it wherever it files downloads; the
///    page cannot write over the file that was opened, and does not pretend
///    to.
///  * *A new project* is written here, opened, and downloaded once as one
///    zip — a dozen separate downloads would be a dozen questions from the
///    browser about whether to allow them.
///
/// Every write is also handed to [persist], which the browser build backs
/// with the session's storage, so a reload keeps what the session opened and
/// the "where you were" list still has something to offer.
///
/// No `package:web` here, so all of that is tested on the VM; the few lines
/// that touch a browser are `disk_web.dart`.
final class MemoryDisk implements EditorDisk {
  MemoryDisk({
    required this.deliver,
    this.persist,
    Future<PickedBytes?> Function(XTypeGroup group)? pick,
    Map<String, Uint8List> restored = const <String, Uint8List>{},
  }) : pick = pick ?? _pickWithFileSelector,
       _files = Map<String, Uint8List>.of(restored);

  /// Where every path here starts, so nothing in the page is mistaken for a
  /// file on somebody's machine when it is printed.
  static const String root = '/browser';

  /// Where a picked document is kept.
  static const String opened = '$root/opened';

  /// Where a template's projects are written.
  static const String projects = '$root/projects';

  /// Hands bytes to the person, as a file called `name`.
  final void Function(String name, Uint8List bytes) deliver;

  /// Keeps a write past a reload; null keeps nothing.
  final void Function(String path, Uint8List bytes)? persist;

  /// Asks the person for a file.
  final Future<PickedBytes?> Function(XTypeGroup group) pick;

  final Map<String, Uint8List> _files;

  /// Every path held, for a test to look at.
  Iterable<String> get paths => _files.keys;

  @override
  bool get savesInPlace => false;

  @override
  List<String> searchFrom() => const <String>[root];

  @override
  String absolute(String path) => path.startsWith('/') ? path : '$root/$path';

  @override
  bool exists(String path) => _files.containsKey(path);

  @override
  bool hasDirectory(String path) => hasFilesUnder(path);

  /// A directory here is nothing but a prefix files share, so one with
  /// nothing in it does not exist — which is the same answer a template
  /// needs.
  @override
  bool hasFilesUnder(String path) {
    final prefix = path.endsWith('/') ? path : '$path/';
    return _files.keys.any((String file) => file.startsWith(prefix));
  }

  @override
  Future<String> readText(String path) async => utf8.decode(_read(path));

  @override
  Future<Uint8List> readBytes(String path) async => _read(path);

  Uint8List _read(String path) =>
      _files[path] ?? (throw StateError('nothing in this page at $path'));

  void _keep(String path, Uint8List bytes) {
    _files[path] = bytes;
    persist?.call(path, bytes);
  }

  @override
  Future<String> writeDocument(String path, String text) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    _keep(path, bytes);
    final name = path.split('/').last;
    deliver(name, bytes);
    return 'downloaded $name — a browser cannot write over the file it '
        'opened, so the saved level is in your downloads';
  }

  @override
  String newProjectRoot(String levelPath, String name) => '$projects/$name';

  @override
  Future<String?> writeProject(
    String root,
    Map<String, Uint8List> files,
  ) async {
    final name = root.split('/').last;
    final archive = Archive();
    for (final MapEntry(key: path, value: bytes) in files.entries) {
      _keep('$root/$path', bytes);
      // Under the project's own folder, so unpacking it makes one directory
      // rather than scattering `lib/` and `assets/` into Downloads.
      archive.add(ArchiveFile.bytes('$name/$path', bytes));
    }
    deliver('$name.zip', ZipEncoder().encodeBytes(archive));
    return 'made $name in this page, and downloaded it as $name.zip — '
        'unpack it to run it with flutter run';
  }

  @override
  Future<String?> choose(XTypeGroup group) async {
    final picked = await pick(group);
    if (picked == null) return null;
    final path = '$opened/${picked.name}';
    _keep(path, picked.bytes);
    return path;
  }

  @override
  Future<bool> saveAs(
    String suggestedName,
    String text,
    XTypeGroup group,
  ) async {
    deliver(suggestedName, Uint8List.fromList(utf8.encode(text)));
    return true;
  }

  /// `file_selector`'s open panel, which in a browser is an
  /// `<input type="file">` and answers with bytes rather than a path.
  static Future<PickedBytes?> _pickWithFileSelector(XTypeGroup group) async {
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    if (file == null) return null;
    return (name: file.name, bytes: await file.readAsBytes());
  }
}
