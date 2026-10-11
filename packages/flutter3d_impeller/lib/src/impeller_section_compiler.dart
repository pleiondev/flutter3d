/// Impeller's entry in the material compiler registry (D26).
library;

import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/backend.dart';

/// Impeller's material compiler: it names the section a material's bundle
/// carries for this backend, and says that nothing is compiled for it while
/// a game runs.
///
/// **Impeller runs what `impellerc` compiled ahead of time**, and `impellerc`
/// ships with the Flutter SDK rather than with a game. So [compilesAtRunTime]
/// is false, and `RuntimeShaders` refuses a data plugin's material on this
/// backend by the registry's sentence, naming it, before [compile] is ever
/// called. The section itself is written by `flutter3d_build`'s material
/// step, which runs `impellerc` in the build; [compile] refuses with the
/// sentence that says so, for a caller that asks anyway.
///
/// Registered by `registerGpuBackend(compilers:)` beside the device.
final class ImpellerSectionCompiler extends MaterialCompiler {
  const ImpellerSectionCompiler();

  @override
  String get backend => 'impeller';

  @override
  String get bundleSection => ShaderBundle.impellerSection;

  @override
  MaterialCompileResult compile(MaterialCompileRequest request) =>
      throw MaterialCompileException(
        '${request.from}: Impeller\'s section is compiled by impellerc, '
        'which ships with the Flutter SDK and not with a game. Put the '
        'material in assets_src/ and let flutter3d_build compile it into '
        'the bundle',
      );
}
