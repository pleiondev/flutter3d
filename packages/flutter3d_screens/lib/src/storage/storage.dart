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
