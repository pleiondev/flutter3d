/// The files a run of `flutter3d convert` means to write, held until every
/// input has been read, so `--dry-run` writes nothing and a refusal to
/// overwrite refuses before anything has moved.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Where each kind of output goes under the output directory.
abstract final class OutputLayout {
  /// A model a scene refers to but that was not itself named on the
  /// command line.
  static const String models = 'models';

  /// `.fmat` and `.f3dmat` files.
  static const String materials = 'materials';

  /// Images a material names, copied once each.
  static const String textures = 'textures';

  /// The suffix of a scene or prefab document: a level, format version 2.
  static const String level = '.level.json';
}

/// What a file in the plan would do to the disk.
final class PlannedWrite {
  const PlannedWrite(this.path, this.bytes, this.owner);

  /// Relative to the output directory, `/`-separated.
  final String path;
  final Uint8List bytes;

  /// The input that produced it.
  final String owner;
}

/// The planned outputs of one run.
///
/// **Content-addressed where it can be.** A texture two materials name is
/// copied once; two inputs that would write the same path with the same
/// bytes write it once; the same path with different bytes is a collision,
/// and the later file gets a numbered name rather than replacing the first
/// one silently.
final class OutputPlan {
  OutputPlan(this.root);

  /// The output directory.
  final String root;

  final Map<String, PlannedWrite> _files = <String, PlannedWrite>{};
  final Map<String, String> _byDigest = <String, String>{};

  /// Every planned file, in path order.
  List<PlannedWrite> get files =>
      (_files.values.toList()
        ..sort((PlannedWrite a, PlannedWrite b) => a.path.compareTo(b.path)));

  /// Plans [bytes] at [path], or at a numbered sibling when [path] is
  /// taken by different bytes. Returns the path it was planned at.
  String add(String path, Uint8List bytes, {required String owner}) {
    final existing = _files[path];
    if (existing == null) {
      _files[path] = PlannedWrite(path, bytes, owner);
      return path;
    }
    if (_same(existing.bytes, bytes)) return path;
    final dot = path.lastIndexOf('.');
    final slash = path.lastIndexOf('/');
    final (stem, suffix) = dot > slash
        ? (path.substring(0, dot), path.substring(dot))
        : (path, '');
    for (var n = 2; ; n++) {
      final candidate = '$stem-$n$suffix';
      final taken = _files[candidate];
      if (taken == null) {
        _files[candidate] = PlannedWrite(candidate, bytes, owner);
        return candidate;
      }
      if (_same(taken.bytes, bytes)) return candidate;
    }
  }

  /// Plans [text] as UTF-8 at [path]. See [add].
  String addText(String path, String text, {required String owner}) =>
      add(path, Uint8List.fromList(utf8.encode(text)), owner: owner);

  /// Plans an image under [OutputLayout.textures], named after
  /// [preferredName], once per distinct content. Returns its path.
  String addTexture(
    String preferredName,
    Uint8List bytes, {
    required String owner,
  }) {
    final digest = sha1.convert(bytes).toString();
    final known = _byDigest[digest];
    if (known != null) return known;
    final path = add(
      '${OutputLayout.textures}/${safeFileName(preferredName)}',
      bytes,
      owner: owner,
    );
    _byDigest[digest] = path;
    return path;
  }

  /// The planned files that would replace a file on disk with different
  /// bytes. A file already holding exactly these bytes is not one: running
  /// the same conversion twice is not an overwrite.
  List<String> collisions() => <String>[
    for (final write in files)
      if (_differsOnDisk(write)) write.path,
  ];

  bool _differsOnDisk(PlannedWrite write) {
    final file = File('$root/${write.path}');
    if (!file.existsSync()) return false;
    return !_same(file.readAsBytesSync(), write.bytes);
  }

  /// Forgets every planned file [owner] produced: an input that failed
  /// halfway leaves nothing behind.
  /// A path in [keep] stays: another input wrote it too. Returns the
  /// paths removed.
  List<String> removeOwner(String owner, {Set<String> keep = const {}}) {
    final removed = <String>[
      for (final w in _files.values)
        if (w.owner == owner && !keep.contains(w.path)) w.path,
    ];
    removed.forEach(_files.remove);
    _byDigest.removeWhere((String _, String path) => !_files.containsKey(path));
    return removed;
  }

  /// Forgets the file planned at [path], whoever planned it: what a bundle
  /// folded in is no longer written beside it.
  void remove(String path) {
    _files.remove(path);
    _byDigest.removeWhere((String _, String at) => at == path);
  }

  /// Writes every planned file. Returns the paths whose bytes changed.
  List<String> commit() {
    final changed = <String>[];
    for (final write in files) {
      final file = File('$root/${write.path}');
      if (file.existsSync() && _same(file.readAsBytesSync(), write.bytes)) {
        continue;
      }
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(write.bytes);
      changed.add(write.path);
    }
    return changed;
  }
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// [name] with everything but letters, digits, `.`, `-` and `_` turned into
/// `_`, and never empty. Output names come from inside source files — a
/// Unity GameObject called `Door (1)`, a USD prim — and a name with a slash
/// in it would write somewhere else.
String safeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final trimmed = cleaned.replaceAll(RegExp(r'^[._]+'), '');
  return trimmed.isEmpty ? 'unnamed' : trimmed;
}

/// [path]'s file name without its directory or last extension.
String stemOf(String path) {
  final slash = path.replaceAll(r'\', '/').lastIndexOf('/');
  final name = path.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// [path]'s lower-cased last extension, with its dot, or empty.
String extensionOf(String path) {
  final name = path.substring(path.replaceAll(r'\', '/').lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(dot).toLowerCase() : '';
}

/// [target] relative to the directory [from], both `/`-separated paths
/// relative to the same root.
String relativePath(String target, String from) {
  final a = from.isEmpty ? <String>[] : from.split('/');
  final b = target.split('/');
  var common = 0;
  while (common < a.length && common < b.length - 1 && a[common] == b[common]) {
    common++;
  }
  return <String>[
    for (var i = common; i < a.length; i++) '..',
    ...b.sublist(common),
  ].join('/');
}

/// The directory part of a `/`-separated relative path, or empty.
String directoryOf(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}
