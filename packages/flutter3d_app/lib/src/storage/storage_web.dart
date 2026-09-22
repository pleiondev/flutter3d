import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../diagnostics/issues.dart';
import 'storage.dart';

/// Documents kept in the browser's `localStorage`.
///
/// **The web build kept nothing at all**, and it looked like nothing was wrong:
/// the file-backed storage reached `Platform.environment`, `dart:io` threw
/// `UnsupportedError`, and the throw was swallowed into defaults — so every
/// launch was a first launch, bindings never survived a refresh, and a run
/// abandoned halfway was gone. A settings file that cannot be written is
/// indistinguishable from a player who has changed no settings.
///
/// `localStorage` rather than IndexedDB, and the reason is size: these are two
/// small JSON documents, synchronous reads suit callers that already promise not
/// to throw, and IndexedDB would make every one of them a future for a payload
/// that fits in a few kilobytes. If a save ever grows past the megabytes a
/// browser allows here, that is the moment to change it — and the symptom will
/// be [write] returning false rather than something silent.
///
/// Keys are namespaced by application, because two games served from the same
/// origin — which is exactly how this repository's demos are deployed — would
/// otherwise each overwrite the other's settings.
final class WebStorage implements Storage {
  WebStorage({required this.appName, IssueSink? onIssue})
    : onIssue = onIssue ?? printIssue;

  final String appName;

  /// Where this says what the browser would not let it do — a private window
  /// with storage disabled, or a quota that has run out.
  final IssueSink onIssue;

  String _key(String name) => 'flutter3d/$appName/$name';

  @override
  String? read(String name) {
    try {
      return web.window.localStorage.getItem(_key(name));
    } catch (error) {
      // Private browsing, or storage disabled by policy. Neither is a reason to
      // refuse to start the game.
      onIssue(Issue('storage: could not read $name ($error)'));
      return null;
    }
  }

  @override
  bool write(String name, String contents) {
    try {
      web.window.localStorage.setItem(_key(name), contents);
      return true;
    } catch (error) {
      // A quota that has run out is the usual one, and it arrives as an
      // exception rather than as a return value.
      onIssue(Issue('storage: could not write $name ($error)'));
      return false;
    }
  }

  @override
  void remove(String name) {
    try {
      web.window.localStorage.removeItem(_key(name));
    } catch (error) {
      onIssue(Issue('storage: could not clear $name ($error)'));
    }
  }
}

/// The storage a browser build gets.
Storage defaultStorage(String appName, {IssueSink? onIssue}) =>
    WebStorage(appName: appName, onIssue: onIssue);

/// Always null in a browser: `localStorage` and IndexedDB are not a folder,
/// and there is nothing for an application to offer to show. The native
/// build's own copy answers with a real path — see `storage_native.dart`.
String? applicationFolder(String appName) => null;

extension on web.IDBRequest {
  /// This request as a future, completing on its first `success` or `error`
  /// event with [result] or [error] respectively.
  Future<T> complete<T extends JSAny?>() {
    final completer = Completer<T>();
    onsuccess = ((web.Event _) {
      completer.complete(result as T);
    }).toJS;
    onerror = ((web.Event _) {
      completer.completeError(
        error ?? StateError('IndexedDB request failed with no error set'),
      );
    }).toJS;
    return completer.future;
  }
}

/// Documents kept in the browser's IndexedDB — the binary half of
/// [WebStorage], for a payload too large for `localStorage`'s text-only
/// budget of a few megabytes. See [BinaryStorage]'s own doc comment for why
/// a model project needs this and a settings file does not.
///
/// **One object store, one key per document.** Opening the database is
/// deferred to the first call and the open [Future] is cached, so two calls
/// made before the first completes share one connection rather than each
/// opening their own — the same reasoning [FileBinaryStorage] gives for
/// resolving its directory lazily rather than in the constructor.
final class IndexedDbBinaryStorage implements BinaryStorage {
  IndexedDbBinaryStorage({required this.appName, IssueSink? onIssue})
    : onIssue = onIssue ?? printIssue;

  final String appName;
  final IssueSink onIssue;

  static const String _storeName = 'documents';

  String get _databaseName => 'flutter3d/$appName';

  Future<web.IDBDatabase>? _opening;

  Future<web.IDBDatabase> _database() => _opening ??= _open();

  Future<web.IDBDatabase> _open() {
    final request = web.window.indexedDB.open(_databaseName, 1);
    // Fires once, the first time this database name is opened at this
    // version — exactly the moment `createObjectStore` is allowed to run.
    request.onupgradeneeded = ((web.Event _) {
      (request.result! as web.IDBDatabase).createObjectStore(_storeName);
    }).toJS;
    return request.complete<web.IDBDatabase>();
  }

  web.IDBObjectStore _store(web.IDBDatabase db, String mode) =>
      db.transaction(_storeName.toJS, mode).objectStore(_storeName);

  @override
  Future<Uint8List?> read(String name) async {
    try {
      final db = await _database();
      final result = await _store(
        db,
        'readonly',
      ).get(name.toJS).complete<JSAny?>();
      if (result == null) return null;
      // Mutation: read this back as a `JSArrayBuffer` instead of the
      // `JSUint8Array` `write` actually stored — the two are different JS
      // types and the cast below would throw rather than silently misread.
      return (result as JSUint8Array).toDart;
    } catch (error) {
      onIssue(Issue('storage: could not read $name ($error)'));
      return null;
    }
  }

  @override
  Future<bool> write(String name, Uint8List contents) async {
    try {
      final db = await _database();
      await _store(
        db,
        'readwrite',
      ).put(contents.toJS, name.toJS).complete<JSAny?>();
      return true;
    } catch (error) {
      onIssue(Issue('storage: could not write $name ($error)'));
      return false;
    }
  }

  @override
  Future<void> remove(String name) async {
    try {
      final db = await _database();
      await _store(db, 'readwrite').delete(name.toJS).complete<JSAny?>();
    } catch (error) {
      onIssue(Issue('storage: could not clear $name ($error)'));
    }
  }
}

/// The binary storage a browser build gets.
BinaryStorage defaultBinaryStorage(String appName, {IssueSink? onIssue}) =>
    IndexedDbBinaryStorage(appName: appName, onIssue: onIssue);
