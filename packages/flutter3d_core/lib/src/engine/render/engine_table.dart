/// One table of bytes the engine's shaders sample — `G1`.
///
/// The bytes are written by `tool/make_tables.dart` as base64 in a generated
/// file under `tables/`, which keeps a 128 KB table a 170 KB source file
/// instead of a megabyte of integer literals.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// One table of bytes the engine's shaders sample, kept as base64 in a
/// generated file under `tables/`.
final class EngineTable {
  /// The table [name], [width] by [height] texels of [format], held as
  /// [base64].
  const EngineTable({
    required this.name,
    required this.width,
    required this.height,
    required this.format,
    required this.base64,
  });

  /// The table's name, the same as the constant's, such as `blueNoise`.
  final String name;

  /// Width of the table in texels.
  final int width;

  /// Height of the table in texels.
  final int height;

  /// The texel format the bytes are laid out in and uploaded as.
  final TextureFormat format;

  /// The texels, row-major from the top, as `tool/make_tables.dart` wrote them.
  final String base64;

  /// [base64] decoded. A fresh copy on every call: the caller uploads it once.
  Uint8List get bytes => base64Decode(base64);
}
