/// A flutter3d graphics backend with no GPU: the reference a backend from
/// outside the engine's repository is written from.
///
///     final registry = DeviceRegistry<Object>();
///     registerNullBackend(registry);
///     final device = await registry.open(width: 320, height: 180);
///
/// It keeps textures in memory, clears, uploads and reads them back, and
/// refuses every pipeline at its first draw, so the engine's renderer runs
/// on it and a frame is the clear colour. It reaches the engine through
/// published libraries alone: `flutter3d_hardware` for the device contract
/// and its handles, `flutter3d_shaders/backend.dart` for the material
/// compiler, and nothing under another package's `src/`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Registration;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/backend.dart';

import 'src/null_device.dart';

export 'src/null_device.dart';
export 'src/null_pass.dart';
export 'src/null_texels.dart';

/// Adds the null backend to [registry], and its material compiler to
/// [compilers] when given; the registration takes both out again.
///
/// Last added, first tried, as every backend added to a registry is;
/// [asFallback] makes it the one tried when nothing else opens.
Registration registerNullBackend(
  DeviceRegistry<Object> registry, {
  MaterialCompilerRegistry? compilers,
  bool asFallback = false,
}) {
  final backend = registry.addBackend(
    NullDevice.name,
    (DeviceRequest request) =>
        NullDevice.open(width: request.width, height: request.height),
    asFallback: asFallback,
  );
  final compiler = compilers?.register(const NullMaterialCompiler());
  return Registration(() {
    compiler?.cancel();
    backend.cancel();
  });
}

/// What the build and `RuntimeShaders` ask to turn a material into this
/// backend's section of a shader bundle.
///
/// The section is the material's stage names, as JSON: a device that
/// compiles nothing needs nothing more to answer them by name. A backend
/// over a real API writes its compiled stages here instead, from
/// [MaterialCompileRequest.stages] (the material as GLSL) or from
/// `compileStage` in `package:flutter3d_shaders/compile.dart`.
final class NullMaterialCompiler extends MaterialCompiler {
  const NullMaterialCompiler();

  /// The device's `backendId`, which the registry matches exactly.
  @override
  String get backend => NullDevice.name;

  /// [nullSection], which no other backend's compiler may take.
  @override
  String get bundleSection => nullSection;

  @override
  bool get compilesAtRunTime => true;

  @override
  MaterialCompileResult compile(MaterialCompileRequest request) =>
      MaterialCompileResult(
        section: ByteData.sublistView(
          utf8.encode(
            jsonEncode(<String>[
              for (final stage in request.stages) stage.name,
            ]),
          ),
        ),
      );
}
