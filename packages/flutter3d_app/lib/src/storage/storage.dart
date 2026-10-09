import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show ResourceException;

export 'storage_native.dart' if (dart.library.js_interop) 'storage_web.dart';

/// Where a game keeps the small documents a player's choices live in.
///
/// **Two of the four platforms were silently losing them.** The settings and the
/// save were files under `$HOME/Library/Application Support`, which is right on
/// macOS — a sandboxed application's `HOME` *is* its container — and is nowhere
/// on the other three. On the web `dart:io` throws on the way past
/// `Platform.environment`, and the throw was swallowed into defaults, so every
/// launch was a first launch. On Android `HOME` is not the application's
/// anything, so the write failed and was swallowed the same way. Both were
/// invisible, because a settings file that cannot be written looks exactly like
/// a player who has not changed any settings.
///
/// So the place is per platform and the shape is not. A document has a name, it
/// is text, and reading one that is not there is null rather than an exception —
/// which is what both callers already wanted, since both promise never to throw
/// and both fall back to defaults.
///
/// The implementation is chosen by conditional export, as `gamepad` chooses its
/// backend and `flutter3d` its packed sort keys: the difference is a fact about
/// the platform rather than a choice anybody is making, and no fake wants to
/// stand here.
///
/// **Asynchronous, and a write that fails throws.** It was synchronous, with
/// `write` answering a boolean, which suited `localStorage` and nothing else:
/// a platform whose storage is asynchronous (IndexedDB, a plugin's channel, a
/// file read off the frame's thread) could not implement it, and a boolean
/// carried no reason a screen could show. A read that finds nothing is still
/// null; a write the platform refused throws a [StorageException] saying why.
///
/// **Implementable outside this package, as a base class.** A member added in
/// a minor release arrives with a default body, so an implementation written
/// against 1.0 keeps compiling: `extends Storage`, not `implements`.
abstract base class Storage {
  const Storage();

  /// The document called [name], or null if there is not one.
  ///
  /// A document that cannot be read (a permission, a private window) is
  /// reported by the implementation and answered as null: a game that cannot
  /// read its settings starts with defaults rather than refusing to start.
  Future<String?> read(String name);

  /// Writes [contents] under [name].
  ///
  /// Throws a [StorageException] when the platform refused — a disk that
  /// filled up mid-save, a browser quota that ran out. A caller that keeps
  /// going after a refused write catches it and says so on screen.
  Future<void> write(String name, String contents);

  /// Forgets [name], if it is there. Never throws.
  Future<void> remove(String name);
}

/// A [Storage] in memory: what a test, a replay with nothing to keep, or a
/// preview hands a document class that needs somewhere to write.
///
/// [documents] is the store itself, public so a test can seed it and read
/// back what was written.
final class MemoryStorage extends Storage {
  MemoryStorage([Map<String, String>? documents])
    : documents = documents ?? <String, String>{};

  final Map<String, String> documents;

  @override
  Future<String?> read(String name) async => documents[name];

  @override
  Future<void> write(String name, String contents) async =>
      documents[name] = contents;

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

/// A write a [Storage] or a [BinaryStorage] could not make, with what the
/// platform said.
///
/// A [ResourceException] since 1.0, so code that reports whatever the engine
/// refused catches it with the rest.
final class StorageException extends ResourceException {
  const StorageException(this.name, this.message, {this.cause});

  /// The document that was being written.
  final String name;

  /// What went wrong, as a sentence.
  @override
  final String message;

  /// What the platform threw, when it threw something.
  @override
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'StorageException: $message'
      : 'StorageException: $message ($cause)';
}

/// Where a document too large or too binary for [Storage] lives.
///
/// **Why a second interface rather than base64 through [Storage].** A model
/// project can be megabytes; `localStorage` — [Storage]'s own backing on the
/// web — is capped at a few of them per origin for every document an
/// application keeps there combined, and base64 costs another third on top
/// of that budget for nothing. IndexedDB has no such ceiling in practice and
/// stores bytes as bytes, which is what an autosave of a real document needs.
///
/// **Asynchronous, as [Storage] is, because [read] and [write] both are on
/// the web.** There is no synchronous IndexedDB from a page's own thread —
/// only from a worker — so an interface promising otherwise would be a
/// promise the web implementation could not keep. A caller on a native
/// platform pays nothing for this: [FileBinaryStorage]'s own I/O is already
/// asynchronous underneath `dart:io`.
///
/// **Implementable outside this package, as a base class**, for the reason
/// [Storage] is: `extends BinaryStorage`, not `implements`.
abstract base class BinaryStorage {
  const BinaryStorage();

  /// The document called [name], or null if there is not one.
  Future<Uint8List?> read(String name);

  /// Writes [contents], and says whether it managed to. Never throws: an
  /// autosave that could not be written is a line in a log and the next
  /// autosave, not a crash.
  Future<bool> write(String name, Uint8List contents);

  /// Forgets [name], if it is there.
  Future<void> remove(String name);
}
