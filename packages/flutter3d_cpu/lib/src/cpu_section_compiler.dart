/// The software rasteriser's compiler for the material language (D26).
library;

import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/backend.dart';

/// Writes the software rasteriser's section of a material's bundle: the
/// source itself, under every stage it becomes, in the material section.
///
/// **Nothing is compiled, and that is why it runs while a game runs.** The
/// device evaluates a material's tree in Dart through its
/// `CpuMaterialCompiler` when it loads the bundle, so the section is the
/// `.f3dmat` text and the stage names that point at it — what
/// `RuntimeShaders` wrote for this backend before compilers were registered.
///
/// Registered by `registerCpuBackend(materialCompilers:)` beside the device.
final class CpuSectionCompiler extends MaterialCompiler {
  const CpuSectionCompiler();

  @override
  String get backend => 'cpu';

  @override
  String get bundleSection => ShaderBundle.materialSection;

  @override
  bool get compilesAtRunTime => true;

  @override
  MaterialCompileResult compile(MaterialCompileRequest request) =>
      MaterialCompileResult(
        section: encodeMaterialSection(<String, String>{
          for (final stage in request.stages) stage.name: request.source,
        }),
      );
}
