/// Keeping a material in step with the `.fmat` it is linked to — `ux-47`.
///
/// **`linkMaterialFile` reads the file once.** That is the whole of what a
/// link meant: the look was copied in at the moment somebody pressed the
/// button, and a material file edited afterwards in another tool — which is
/// what a shared material library *is* — left the project holding a snapshot
/// of a file that had moved on. The review found people re-linking by hand
/// to see a colour change.
///
/// **The watching lives here and the decisions live in [LinkedMaterials].**
/// Which paths are worth watching, what a change should run, and what a file
/// that stopped parsing should leave behind are questions with no filesystem
/// in them, and they are the questions that go wrong. The platform half is
/// one stream and one read, handed in.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';

export 'linked_materials_io.dart'
    if (dart.library.js_interop) 'linked_materials_web.dart';

/// What a platform gives this: a stream that fires when [path] changes on
/// disk, the bytes at [path], and a way to hand [path] to whatever the
/// system opens `.fmat` files with.
typedef LinkedMaterialHost = ({
  Stream<void> Function(String path) watch,
  Future<Uint8List?> Function(String path) read,
  Future<bool> Function(String path) openInEditor,
});

/// Watches every `.fmat` a project links to, and re-links each when it moves.
///
/// **One watcher per path, not per material**, because two materials linked
/// to the same file are two rows over one fact; and torn down and rebuilt
/// wholesale on [follow], because a project that just changed is cheaper to
/// re-read than to diff.
final class LinkedMaterials {
  LinkedMaterials({required this.host, required this.onRelink, this.onTrouble});

  /// The platform half — see [LinkedMaterialHost].
  final LinkedMaterialHost host;

  /// Run this command, which is a `LinkMaterialFile` carrying the new bytes.
  ///
  /// The caller runs it through `ModelHistory` like any other, so a file
  /// changing behind the editor is one undo step and says what it was.
  final void Function(LinkMaterialFile relink) onRelink;

  /// A file that changed and could not be read, with the reason.
  ///
  /// **The last good material stays.** A `.fmat` is a text file somebody is
  /// editing, so it spends part of its life half-written; replacing a
  /// material with nothing every time an editor saves a partial file would
  /// make the viewport flicker between a look and a default. Saying so and
  /// keeping what was there is the only useful answer.
  final void Function(String path, String because)? onTrouble;

  final Map<String, StreamSubscription<void>> _watching =
      <String, StreamSubscription<void>>{};

  /// Which paths are being watched right now — for a test, and for anything
  /// that wants to say how many files it is following.
  Iterable<String> get watching => _watching.keys;

  /// Watches exactly the files [project] links to, and nothing else.
  void follow(ModelProject project) {
    final Set<String> wanted = pathsOf(project);
    for (final String gone in _watching.keys.toList()) {
      if (wanted.contains(gone)) continue;
      unawaited(_watching.remove(gone)!.cancel());
    }
    for (final String path in wanted) {
      if (_watching.containsKey(path)) continue;
      _watching[path] = host
          .watch(path)
          .listen((void _) => _changed(project, path));
    }
  }

  Future<void> _changed(ModelProject project, String path) async {
    final Uint8List? bytes = await host.read(path);
    if (bytes == null) {
      onTrouble?.call(path, 'the file is gone, or could not be read');
      return;
    }
    for (final int index in indicesOf(project, path)) {
      onRelink(LinkMaterialFile(index: index, path: path, bytes: bytes));
    }
  }

  /// Hands [path] to whatever the system opens a `.fmat` with, and says
  /// whether that worked.
  Future<bool> openInEditor(String path) => host.openInEditor(path);

  /// Stops watching everything.
  Future<void> dispose() async {
    for (final StreamSubscription<void> each in _watching.values) {
      await each.cancel();
    }
    _watching.clear();
  }

  /// Every distinct `.fmat` path [project]'s materials link to.
  static Set<String> pathsOf(ModelProject project) => <String>{
    for (final ProjectMaterial each in project.materials)
      if (each.fmat case final String path)
        if (path.trim().isNotEmpty) path,
  };

  /// Which material rows link to [path] — more than one when two materials
  /// share a file, which is the ordinary case for a library.
  static List<int> indicesOf(ModelProject project, String path) => <int>[
    for (var i = 0; i < project.materials.length; i++)
      if (project.materials[i].fmat == path) i,
  ];
}
