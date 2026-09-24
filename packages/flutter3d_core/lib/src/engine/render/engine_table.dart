/// One table of bytes the engine's shaders sample — `G1`.
///
/// The bytes are written by `tool/make_tables.dart` as base64 in a generated
/// file under `tables/`, which keeps a 128 KB table a 170 KB source file
/// instead of a megabyte of integer literals.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

final class EngineTable {
  const EngineTable({
    required this.name,
    required this.width,
    required this.height,
    required this.format,
    required this.base64,
  });

  final String name;
  final int width;
  final int height;
  final TextureFormat format;

  /// The texels, row-major from the top, as `tool/make_tables.dart` wrote them.
  final String base64;

  /// [base64] decoded. A fresh copy on every call: the caller uploads it once.
  Uint8List get bytes => base64Decode(base64);
}
