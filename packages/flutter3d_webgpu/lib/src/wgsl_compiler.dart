/// The two external programs, and the exact words they are called with.
///
/// One file rather than a line inside the generator, because the test that
/// measures the pipeline and the generator that writes the table must call them
/// the same way. A flag present in one and absent in the other would mean the
/// thing being measured was not the thing being shipped, and one of the two
/// flags below is exactly the kind that goes missing.
///
/// ## `--keep-coordinate-space`, which is not optional
///
/// **naga 30.0.1 inserts a y-flip into every vertex entry point unless told
/// not to.** The tail of `main` grows `gl_Position.y = -(gl_Position.y)`, on the
/// assumption that SPIR-V arriving here came from OpenGL and wants turning
/// over. The engine's clip space is already WebGPU's, so the flip is a
/// correction of an error nobody made.
///
/// Nothing fails when the flag is forgotten. The WGSL compiles, the pipeline
/// builds, the draw succeeds, and every scene comes back upside down — which is
/// the shape of failure this repository has learned to fear most, because the
/// tool that would catch it is the golden set, and the golden set for this
/// backend does not exist yet. `test/wgsl_pipeline_test.dart` compiles one
/// vertex stage both ways and holds the difference, so the flag has a reason
/// attached to it rather than a memory.
///
/// ## `--auto-map-locations`, which is a net rather than a decision
///
/// [prepareStage] hands out every location itself, so glslang should have
/// nothing left to assign. The flag stays because an unassigned location is an
/// error under `-V` and this way it is a quiet one — and because it is the
/// command line the pipeline was measured with.
///
/// **`--auto-map-bindings` is deliberately absent.** Letting glslang number the
/// bindings would mean reading them back out of the WGSL to write the
/// reflection, and a parser for WGSL is a second implementation of a decision
/// the packer already made. The packer numbers them, so the reflection is a
/// by-product of the numbering rather than a reconstruction of it.
///
/// Under `lib/src/` for the reason `source_package.dart` gives: the browser
/// test runner cannot read a directory beside `test/`, so a build-time file no
/// test can import is a build-time file no test can measure. Nothing this
/// package exports reaches it.
library;

import 'dart:io';

/// Where the two programs are, by name, resolved through `PATH`.
const String kGlslang = 'glslangValidator';

/// naga's CLI. Installed by `cargo install naga-cli`, which puts it under
/// `~/.cargo/bin` — on `PATH` for a developer and worth naming in the failure
/// message for everyone else.
const String kNaga = 'naga';

/// Raised when one of the two programs refuses, carrying what it said.
final class WgslCompileError implements Exception {
  const WgslCompileError(this.message);

  final String message;

  @override
  String toString() => 'WgslCompileError: $message';
}

/// What one stage's compilation produced.
typedef CompiledStage = ({String wgsl, Map<String, Map<String, int>> offsets});

/// Compiles [glsl] to WGSL, and reads back the offsets glslang assigned.
///
/// [name] appears in every failure message and in the temporary file names, so
/// a refusal names the stage rather than a path under `/tmp`.
///
/// [offsets] is glslang's own `Offset` decoration per uniform block member,
/// read out of `-H`'s human-readable SPIR-V. It is not used to build the
/// reflection — the packer computes std140 itself, from the GLSL — but it is
/// the one independent witness to whether that arithmetic is right, and
/// `generate_shaders.dart` checks every block against it. The two agreeing is
/// what makes "std140 and WGSL's uniform address space lay this out the same
/// way" a measurement.
CompiledStage compileStage(
  String glsl, {
  required String name,
  required bool fragment,
}) {
  final directory = Directory.systemTemp.createTempSync('flutter3d_wgsl_');
  try {
    final source = File('${directory.path}/$name.${fragment ? 'frag' : 'vert'}')
      ..writeAsStringSync(glsl);
    final spirv = '${directory.path}/$name.spv';
    final wgsl = '${directory.path}/$name.wgsl';

    final compiled = Process.runSync(kGlslang, <String>[
      '-V',
      '--auto-map-locations',
      '-H',
      source.path,
      '-o',
      spirv,
    ]);
    if (compiled.exitCode != 0) {
      throw WgslCompileError(
        '$kGlslang refused $name:\n${compiled.stdout}${compiled.stderr}',
      );
    }

    final translated = Process.runSync(kNaga, <String>[
      '--keep-coordinate-space',
      spirv,
      wgsl,
    ]);
    if (translated.exitCode != 0) {
      throw WgslCompileError(
        '$kNaga refused $name:\n${translated.stdout}${translated.stderr}',
      );
    }

    // Back through naga the other way. It costs a process and it answers a
    // question the forward pass cannot: naga writing a file does not mean naga
    // would accept that file, and the browser is a third implementation with an
    // opinion of its own. Anything WGSL's own validator rejects would reach the
    // device as a compile error at first draw, on a user's machine, with the
    // build long finished.
    final revalidated = Process.runSync(kNaga, <String>[
      '--input-kind',
      'wgsl',
      wgsl,
    ]);
    if (revalidated.exitCode != 0) {
      throw WgslCompileError(
        '$kNaga would not read back the WGSL it wrote for $name:\n'
        '${revalidated.stdout}${revalidated.stderr}',
      );
    }

    return (
      wgsl: File(wgsl).readAsStringSync(),
      offsets: _offsets(compiled.stdout as String),
    );
  } on ProcessException catch (error) {
    throw WgslCompileError(
      'could not run ${error.executable} for $name: ${error.message}. '
      'glslangValidator comes with the Vulkan SDK or `brew install '
      'glslang`; naga comes from `cargo install naga-cli`.',
    );
  } finally {
    directory.deleteSync(recursive: true);
  }
}

/// `Offset` decorations per block, out of glslang's `-H` listing.
///
/// The listing names a type once — `MemberName 11(FragInfo) 0 "light_position"`
/// — and decorates it by id afterwards, so the two halves are joined here by
/// id rather than by position.
Map<String, Map<String, int>> _offsets(String listing) {
  final names = <String, String>{};
  final members = <String, Map<int, String>>{};
  final offsets = <String, Map<String, int>>{};

  for (final line in listing.split('\n')) {
    final member = _memberName.firstMatch(line);
    if (member != null) {
      final id = member.group(1)!;
      names[id] = member.group(2)!;
      (members[id] ??= <int, String>{})[int.parse(member.group(3)!)] = member
          .group(4)!;
      continue;
    }
    final decoration = _memberOffset.firstMatch(line);
    if (decoration == null) continue;
    final id = decoration.group(1)!;
    final block = names[id];
    final field = members[id]?[int.parse(decoration.group(2)!)];
    if (block == null || field == null) continue;
    (offsets[block] ??= <String, int>{})[field] = int.parse(
      decoration.group(3)!,
    );
  }
  return offsets;
}

final RegExp _memberName = RegExp(
  r'MemberName\s+(\d+)\((\w+)\)\s+(\d+)\s+"(\w+)"',
);
final RegExp _memberOffset = RegExp(
  r'MemberDecorate\s+(\d+)\(\w+\)\s+(\d+)\s+Offset\s+(\d+)',
);
