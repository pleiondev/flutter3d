/// Impeller registers its material compiler beside its device (D26): one
/// that names the backend's section and compiles nothing while a game runs,
/// so a data plugin's material is refused by the registry's sentence.
///
///     flutter test test/section_compiler_test.dart
///
/// Mutation: leave the compiler out of `registerGpuBackend` and the registry
/// answers null; say it compiles at run time and the refusal is skipped.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the backend registers its compiler and takes it out again', () {
    final compilers = MaterialCompilerRegistry();
    final registration = registerGpuBackend(
      DeviceRegistry(),
      compilers: compilers,
    );
    final compiler = compilers.forBackend('impeller');
    expect(compiler, isA<ImpellerSectionCompiler>());
    expect(compiler!.bundleSection, ShaderBundle.impellerSection);
    expect(compiler.compilesAtRunTime, isFalse);
    registration.cancel();
    expect(compilers.forBackend('impeller'), isNull);
  });

  test('asked to compile anyway, it names the build that does', () {
    expect(
      () => const ImpellerSectionCompiler().compile(
        const MaterialCompileRequest(
          name: 'Glow',
          from: 'glow.f3dmat',
          source: '',
          stages: <MaterialStageSource>[],
        ),
      ),
      throwsA(
        isA<MaterialCompileException>().having(
          (e) => e.message,
          'message',
          allOf(contains('glow.f3dmat'), contains('impellerc')),
        ),
      ),
    );
  });
}
