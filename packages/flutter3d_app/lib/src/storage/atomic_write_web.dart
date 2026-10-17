/// The browser's half of `atomic_write.dart`: there is no file to write, so
/// each call refuses with an [UnsupportedError] that says so.
library;

import 'dart:typed_data';

/// Refuses: a browser has no filesystem. Use `Storage` instead.
Future<void> writeFileAtomically(String path, String contents) async =>
    throw UnsupportedError(_why(path));

/// Refuses: a browser has no filesystem. Use `Storage` instead.
void writeFileAtomicallySync(String path, String contents) =>
    throw UnsupportedError(_why(path));

/// Refuses: a browser has no filesystem. Use `BinaryStorage` instead.
void writeBytesAtomicallySync(String path, Uint8List contents) =>
    throw UnsupportedError(_why(path));

String _why(String path) =>
    'cannot write $path: a browser has no filesystem; keep documents in '
    'Storage, which is localStorage there';
