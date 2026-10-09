/// No bundle to watch in a browser — see `shader_source.dart`.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'shader_source.dart';

/// Null when no bundle was named; a refusal when one was.
Future<WatchedShaders?> openShaders(
  GraphicsDevice device,
  String path, {
  required List<String> from,
  required void Function(LoadedShaderLibrary library) onRefreshed,
  required void Function(ShaderBundleException refused) onRefused,
}) async {
  if (path.isEmpty) return null;
  throw UnsupportedError(
    'shaders=$path: a browser build has no file to watch — '
    'run the desktop editor to draw with a bundle',
  );
}
