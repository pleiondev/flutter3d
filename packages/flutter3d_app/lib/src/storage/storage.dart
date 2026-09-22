import 'dart:typed_data';

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
abstract interface class Storage {
  /// The document called [name], or null if there is not one.
  String? read(String name);

  /// Writes [contents], and says whether it managed to.
  ///
  /// **Never throws**, whatever the platform did: a disk that filled up mid-save
  /// is a bad day and a game that will not launch is a bug report nobody can
  /// act on. The boolean is for a caller that wants to say so on screen.
  bool write(String name, String contents);

  /// Forgets [name], if it is there.
  void remove(String name);
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
/// **Asynchronous, unlike [Storage], because [read] and [write] both are on
/// the web.** There is no synchronous IndexedDB from a page's own thread —
/// only from a worker — so an interface promising otherwise would be a
/// promise the web implementation could not keep. A caller on a native
/// platform pays nothing for this: [FileBinaryStorage]'s own I/O is already
/// asynchronous underneath `dart:io`.
abstract interface class BinaryStorage {
  /// The document called [name], or null if there is not one.
  Future<Uint8List?> read(String name);

  /// Writes [contents], and says whether it managed to. Never throws, for
  /// the same reason [Storage.write] does not.
  Future<bool> write(String name, Uint8List contents);

  /// Forgets [name], if it is there.
  Future<void> remove(String name);
}
