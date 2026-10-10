import 'dart:typed_data';

Never _noFiles(String path) =>
    throw UnsupportedError('there is no file system in the browser: $path');

/// The bytes of the file at [path]: never, in the browser.
Future<Uint8List> readFileBytes(String path) => _noFiles(path);

/// The directory [path] is in, by its last slash.
String parentDirectoryOf(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? '.' : path.substring(0, slash);
}

/// The bytes of the file at [path]: never, in the browser.
Future<Uint8List> readReferencedFile(String path, String message) =>
    _noFiles(path);

/// Whether [error] is a file that was not there: never one in the browser,
/// where there are no files to miss.
bool isMissingFile(Object error) => false;
