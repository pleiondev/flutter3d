import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

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
  WebStorage({required this.appName});

  final String appName;

  String _key(String name) => 'flutter3d/$appName/$name';

  @override
  String? read(String name) {
    try {
      return web.window.localStorage.getItem(_key(name));
    } catch (error) {
      // Private browsing, or storage disabled by policy. Neither is a reason to
      // refuse to start the game.
      debugPrint('storage: could not read $name ($error)');
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
      debugPrint('storage: could not write $name ($error)');
      return false;
    }
  }

  @override
  void remove(String name) {
    try {
      web.window.localStorage.removeItem(_key(name));
    } catch (error) {
      debugPrint('storage: could not clear $name ($error)');
    }
  }
}

/// The storage a browser build gets.
Storage defaultStorage(String appName) => WebStorage(appName: appName);
