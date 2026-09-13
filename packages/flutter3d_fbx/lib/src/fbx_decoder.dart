/// `fmt-29d`'s own row: `FbxDecoder implements ModelDecoder` as a stub —
/// [handles] recognises an FBX file by its own magic, and [decode] refuses
/// every one of them with a clear reason rather than crashing on one. The
/// real reader is `fmt-24` (binary and ASCII 7.x, geometry/materials/
/// hierarchy) and `fmt-25` (skins and animation), still to come.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';

/// The first bytes of a binary FBX file — `"Kaydara FBX Binary  "` followed
/// by two NUL bytes and a version number, every binary FBX ever written
/// since the format's own 2005 introduction.
const List<int> _binaryMagic = <int>[
  0x4b, 0x61, 0x79, 0x64, 0x61, 0x72, 0x61, // "Kaydara"
  0x20, 0x46, 0x42, 0x58, // " FBX"
  0x20, 0x42, 0x69, 0x6e, 0x61, 0x72, 0x79, // " Binary"
  0x20, 0x20, 0x00, // "  " + NUL
];

/// A `ModelDecoder` for Autodesk's FBX — the skeleton this package's own
/// `pubspec.yaml` describes: recognises the format, and says plainly that
/// reading one is not built here yet.
final class FbxDecoder implements ModelDecoder {
  const FbxDecoder();

  @override
  bool handles(String fileName, Uint8List bytes) {
    if (fileName.toLowerCase().endsWith('.fbx')) return true;
    if (bytes.length >= _binaryMagic.length) {
      var matches = true;
      for (var i = 0; i < _binaryMagic.length; i++) {
        if (bytes[i] != _binaryMagic[i]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    // The ASCII form has no fixed magic, only a header comment every
    // exporter writes — checked over a short, UTF-8-safe prefix rather than
    // the whole file, since a multi-megabyte FBX has no reason to be
    // decoded twice just to answer "is this one of yours".
    final prefixLength = bytes.length < 64 ? bytes.length : 64;
    try {
      final prefix = utf8.decode(
        bytes.sublist(0, prefixLength),
        allowMalformed: true,
      );
      if (prefix.trimLeft().startsWith('; FBX')) return true;
    } on FormatException {
      // Not text at all — already answered by the binary check above.
    }
    return false;
  }

  @override
  Future<ModelDocument> decode(
    Uint8List bytes,
    ModelLoadRequest request,
    AssetUriResolver resolveUri,
  ) async {
    throw const FormatException(
      'FBX files are recognised but not yet read — flutter3d_fbx is a '
      'skeleton (fmt-29d); the reader (fmt-24/25) has not landed. Re-export '
      'as glTF/GLB in the meantime.',
    );
  }
}
