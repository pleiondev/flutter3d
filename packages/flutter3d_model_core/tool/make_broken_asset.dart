/// Writes `test/fixtures/broken_asset.glb` from `test/broken_asset.dart`.
///
///     dart run tool/make_broken_asset.dart
///
/// **A GLB rather than the project, because the fault being tested is in the
/// file.** `AssetAudit` is for assets that arrive from somewhere else, so the
/// fixture goes through the same writer and the same loader such an asset
/// does; a project handed straight to the audit would skip the one step
/// whose losses — a material merged, a degenerate triangle dropped — the
/// audit exists to catch. Unlike `mint_fixture.dart` this overwrites: the
/// fixture is a function of `broken_asset.dart`, not a file from the past.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../test/broken_asset.dart';

void main() {
  const path = 'test/fixtures/broken_asset.glb';
  final written = const GlbModelWriter().write(
    toModelDocument(brokenAsset()),
    baseName: 'broken_asset',
  );
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(written.files.single.bytes);
  stdout.writeln('$path: ${written.files.single.bytes.length} bytes');
}
