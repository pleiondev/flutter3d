/// The page's disk, in a browser: a [MemoryDisk] whose writes outlive a
/// reload and whose saves are downloads.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'editor_disk.dart';
import 'memory_disk.dart';

EditorDisk platformDisk() => MemoryDisk(
  deliver: download,
  persist: SessionFiles.keep,
  restored: SessionFiles.read(),
);

/// The files this tab has opened or written, in `sessionStorage`.
///
/// **The session's, not forever's.** `localStorage` would keep a level in
/// the browser after the tab that made it is gone, where nobody would think
/// to look for it and nothing would ever clear it; the person's copy of their
/// work is the download. What this buys is a reload: the documents opened in
/// this tab are still here afterwards, so the recent list — kept beside a
/// game's settings, in `localStorage` — still offers them, and a project made
/// from a template is not lost to a stray ⌘R.
///
/// **Storage can be missing or full**, in a private window or past a quota,
/// and both arrive as exceptions. Neither is a reason to refuse to open a
/// level, so each is swallowed here and the page simply forgets more on a
/// reload.
abstract final class SessionFiles {
  static const String prefix = 'flutter3d/flutter3d_editor/file:';

  static void keep(String path, Uint8List bytes) {
    try {
      web.window.sessionStorage.setItem('$prefix$path', base64.encode(bytes));
    } catch (error) {
      // A quota that ran out, or storage turned off. See above.
    }
  }

  static Map<String, Uint8List> read() {
    final files = <String, Uint8List>{};
    try {
      final storage = web.window.sessionStorage;
      for (var i = 0; i < storage.length; i++) {
        final key = storage.key(i);
        if (key == null || !key.startsWith(prefix)) continue;
        final value = storage.getItem(key);
        if (value == null) continue;
        files[key.substring(prefix.length)] = base64.decode(value);
      }
    } catch (error) {
      // Unreadable storage is a first visit; see above.
    }
    return files;
  }
}

/// Hands [bytes] to the browser as a download called [name].
void download(String name, Uint8List bytes) {
  final blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  // In the document for the click: Firefox ignores a click on an anchor
  // that is not.
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Revoked a moment later rather than at once: revoking in the same task
  // cancels the download in Safari.
  Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
}
