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
/// Reached through `package:flutter3d_shaders/compile.dart` only, never the
/// package's barrel: it runs processes, and nothing a consumer's application
/// builds has a reason to carry that.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException;

import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show ShaderStageKind;

import 'shader_target.dart';

/// Where the two programs are, by name, resolved through `PATH`.
const String glslangExecutable = 'glslangValidator';

/// naga's CLI. Installed by `cargo install naga-cli`, which puts it under
/// `~/.cargo/bin` — on `PATH` for a developer and worth naming in the failure
/// message for everyone else.
const String nagaExecutable = 'naga';

/// Raised when one of the two programs refuses, carrying what it said.
final class WgslCompileException extends Flutter3dFormatException {
  const WgslCompileException(this.message);

  @override
  final String message;

  @override
  String toString() => 'WgslCompileException: $message';
}

/// What one stage's compilation produced: its SPIR-V, the text of the
/// [target] it was translated into, and the uniform offsets glslang laid
/// out.
///
/// **The backend author's half of the shader contract** (D27): a backend
/// that loads SPIR-V (Vulkan) takes [spirv]; one that loads a language
/// (WebGPU's WGSL, Metal's MSL, Direct3D's HLSL) takes [text] for the
/// [target] it asked for. A class rather than a record, so a later minor can
/// hand over more — reflection, a source map — without changing its shape.
final class CompiledStage {
  CompiledStage({
    required this.spirv,
    required this.target,
    required this.text,
    required this.offsets,
  });

  /// The stage as SPIR-V, what glslang made of the GLSL.
  final Uint8List spirv;

  /// What [text] is in.
  final ShaderTarget target;

  /// The stage in [target]'s language, or null when [target] is
  /// [ShaderTarget.spirv].
  final String? text;

  /// glslang's own `Offset` per uniform block member, by block.
  final Map<String, Map<String, int>> offsets;

  /// [text] as WGSL. Throws a [StateError] for a stage compiled to another
  /// target.
  String get wgsl => target == ShaderTarget.wgsl
      ? text!
      : throw StateError('this stage was compiled to ${target.name}');
}

/// Compiles [glsl] to SPIR-V and translates it to [target] — WGSL unless
/// asked otherwise — and reads back the offsets glslang assigned.
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
///
/// [kind] says what the stage runs as. Without it, [compute] and [fragment]
/// say it as they always have: a compute stage when [compute] is true, a
/// fragment stage when [fragment] is, and a vertex stage otherwise.
///
/// [target] [ShaderTarget.spirv] stops after glslang and hands back the
/// SPIR-V alone. WGSL is read back through naga a second time, as before;
/// the other languages are naga's to write and the backend's to load.
CompiledStage compileStage(
  String glsl, {
  required String name,
  bool fragment = false,
  bool compute = false,
  ShaderStageKind? kind,
  ShaderTarget target = ShaderTarget.wgsl,
}) {
  final stage =
      kind ??
      (compute
          ? ShaderStageKind.compute
          : fragment
          ? ShaderStageKind.fragment
          : ShaderStageKind.vertex);
  final directory = Directory.systemTemp.createTempSync('flutter3d_wgsl_');
  try {
    // glslang picks the stage from the extension, so the extension is the
    // one place a compute stage (`H6`) differs from the other two here.
    final source = File(
      '${directory.path}/$name.'
      '${_extensionOf(stage)}',
    )..writeAsStringSync(glsl);
    final spirv = '${directory.path}/$name.spv';
    final extension = switch (target) {
      // naga picks the GLSL stage from the extension, as glslang does.
      ShaderTarget.glsl => _extensionOf(stage),
      _ => target.extension,
    };
    final translatedPath = extension == null
        ? null
        : '${directory.path}/$name.out.$extension';

    final compiled = Process.runSync(glslangExecutable, <String>[
      '-V',
      '--auto-map-locations',
      '-H',
      source.path,
      '-o',
      spirv,
    ]);
    if (compiled.exitCode != 0) {
      throw WgslCompileException(
        '$glslangExecutable refused $name:\n${compiled.stdout}${compiled.stderr}',
      );
    }

    final offsets = _offsets(compiled.stdout as String);
    final binary = File(spirv).readAsBytesSync();
    if (translatedPath == null) {
      return CompiledStage(
        spirv: binary,
        target: target,
        text: null,
        offsets: offsets,
      );
    }

    final translated = Process.runSync(nagaExecutable, <String>[
      '--keep-coordinate-space',
      spirv,
      translatedPath,
    ]);
    if (translated.exitCode != 0) {
      throw WgslCompileException(
        '$nagaExecutable refused $name:\n${translated.stdout}${translated.stderr}',
      );
    }

    // Back through naga the other way, for WGSL. It costs a process and it
    // answers a question the forward pass cannot: naga writing a file does
    // not mean naga would accept that file, and the browser is a third
    // implementation with an opinion of its own. Anything WGSL's own
    // validator rejects would reach the device as a compile error at first
    // draw, on a user's machine, with the build long finished.
    if (target == ShaderTarget.wgsl) {
      final revalidated = Process.runSync(nagaExecutable, <String>[
        '--input-kind',
        'wgsl',
        translatedPath,
      ]);
      if (revalidated.exitCode != 0) {
        throw WgslCompileException(
          '$nagaExecutable would not read back the WGSL it wrote for $name:\n'
          '${revalidated.stdout}${revalidated.stderr}',
        );
      }
    }

    return CompiledStage(
      spirv: binary,
      target: target,
      text: File(translatedPath).readAsStringSync(),
      offsets: offsets,
    );
  } on ProcessException catch (error, stack) {
    Error.throwWithStackTrace(
      WgslCompileException(
        'could not run ${error.executable} for $name: ${error.message}. '
        'glslangValidator comes with the Vulkan SDK or `brew install '
        'glslang`; naga comes from `cargo install naga-cli`.',
      ),
      stack,
    );
  } finally {
    directory.deleteSync(recursive: true);
  }
}

/// The extension glslang and naga read a GLSL stage's kind from.
/// glslang's and naga's extension for [kind]; a kind neither tool takes is
/// refused by name rather than compiled as another.
String _extensionOf(ShaderStageKind kind) => switch (kind) {
  ShaderStageKind.compute => 'comp',
  ShaderStageKind.fragment => 'frag',
  ShaderStageKind.vertex => 'vert',
  _ => throw UnsupportedError(
    'compileStage has no glslang stage for a ${kind.name} stage',
  ),
};

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
