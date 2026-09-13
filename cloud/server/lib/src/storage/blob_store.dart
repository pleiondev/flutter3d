/// Where the bytes of a model live.
///
/// **Addressed by content.** A blob's name is the SHA-256 of what is in it, so
/// the same file uploaded twice is stored once, a name can never point at
/// different bytes than it did yesterday, and a row that says which hash it
/// wants is enough to find the file on any store that implements this.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

abstract interface class BlobStore {
  /// Stores [bytes] and returns their hash, as lowercase hex.
  Future<String> put(Uint8List bytes);

  /// The bytes stored under [sha256], as a stream, or null when there are none.
  Future<Stream<List<int>>?> open(String sha256);

  /// The size of the blob, or null when it does not exist.
  Future<int?> sizeOf(String sha256);

  Future<void> delete(String sha256);
}

/// Blobs as files in a directory tree: `ab/cd/abcd…`.
///
/// Two levels of fan-out, because a directory with a hundred thousand entries
/// is slow to list on every filesystem the service is likely to meet, and
/// 65,536 directories each holding a handful is not.
class FileBlobStore implements BlobStore {
  FileBlobStore(String root) : _root = Directory(root);

  final Directory _root;

  static final _hex = RegExp(r'^[0-9a-f]{64}$');

  @override
  Future<String> put(Uint8List bytes) async {
    final hash = sha256.convert(bytes).toString();
    final target = _fileOf(hash);
    if (await target.exists()) return hash;

    await target.parent.create(recursive: true);

    // **Written beside its final name, then renamed.** A rename within one
    // directory is atomic, so a reader sees either no file or the whole file,
    // never the first half of an upload that the process died in the middle
    // of writing.
    final temporary = File(
      '${target.path}.$pid.${Random().nextInt(1 << 32)}.partial',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    return hash;
  }

  @override
  Future<Stream<List<int>>?> open(String sha256) async {
    final file = _fileOf(sha256);
    return await file.exists() ? file.openRead() : null;
  }

  @override
  Future<int?> sizeOf(String sha256) async {
    final file = _fileOf(sha256);
    return await file.exists() ? file.length() : null;
  }

  @override
  Future<void> delete(String sha256) async {
    final file = _fileOf(sha256);
    if (await file.exists()) await file.delete();
  }

  File _fileOf(String hash) {
    // The hash arrives from the database, but a path built from anything a
    // caller passes must not be able to leave the root.
    if (!_hex.hasMatch(hash)) {
      throw ArgumentError.value(hash, 'sha256', 'not a lowercase SHA-256 hex digest');
    }
    return File('${_root.path}/${hash.substring(0, 2)}/${hash.substring(2, 4)}/$hash');
  }
}

/// Blobs in memory, for tests.
class MemoryBlobStore implements BlobStore {
  final _blobs = <String, Uint8List>{};

  @override
  Future<String> put(Uint8List bytes) async {
    final hash = sha256.convert(bytes).toString();
    _blobs[hash] = Uint8List.fromList(bytes);
    return hash;
  }

  @override
  Future<Stream<List<int>>?> open(String sha256) async =>
      _blobs[sha256] == null ? null : Stream.value(_blobs[sha256]!);

  @override
  Future<int?> sizeOf(String sha256) async => _blobs[sha256]?.length;

  @override
  Future<void> delete(String sha256) async => _blobs.remove(sha256);

  int get length => _blobs.length;
}
