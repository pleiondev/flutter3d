import 'dart:io';
import 'dart:typed_data';

/// The bytes of the file at [path].
Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();

/// The directory [path] is in.
String parentDirectoryOf(String path) => File(path).parent.path;

/// The bytes of the file at [path], or a [FileSystemException] saying
/// [message] when there is none. Asked synchronously: an async `exists` is a
/// round trip through the event loop for an answer the file system has at
/// once, and this is asked once per buffer and image a model references.
Future<Uint8List> readReferencedFile(String path, String message) {
  final file = File(path);
  if (!file.existsSync()) throw FileSystemException(message, path);
  return file.readAsBytes();
}

/// Whether [error] is a file that was not there.
bool isMissingFile(Object error) => error is FileSystemException;
