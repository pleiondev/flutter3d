// Builds the native Position Based Fluids kernels, `src/pbf_kernels.c`,
// into a library `NativePbfKernels` binds to through `@Native`.
//
// **Never the reason a build fails.** The C compiler is the machine's own:
// Xcode's, the NDK's, MSVC's, the system clang or gcc. Where there is none,
// or the build of the library fails for any other reason, this says so and
// builds nothing, and the fluid runs on the Dart kernels it would have run
// on anyway; `NativePbfKernels.available` is false.
//
// **Optimised, and vectorised where it can be**: -O3, and on x86-64 the
// SSE2 every such processor has. The kernels sum two neighbours at a time
// with the compiler's vector extensions, which is why they are held to the
// Dart reference within a tolerance rather than to the bit.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final logger = Logger('flutter3d_physics')
      // A hook's output is its standard output; there is no other logger.
      // ignore: avoid_print
      ..onRecord.listen((record) => print(record.message));
    // Windows builds with MSVC, whose flags are its own.
    final msvc = input.config.code.targetOS == OS.windows;
    final builder = CBuilder.library(
      name: 'flutter3d_physics_native',
      assetName: 'src/fluid/native/pbf_native.dart',
      sources: ['src/pbf_kernels.c'],
      flags: msvc ? const ['/O2'] : const ['-O3', '-fno-math-errno'],
    );
    try {
      await builder.run(input: input, output: output, logger: logger);
    } on Object catch (error) {
      logger.warning(
        'flutter3d_physics: no native fluid kernels ($error); the fluid '
        'runs on its Dart kernels.',
      );
    }
  });
}
