/// A backend's compiler for the material language, and the registry the
/// build and the run time find it in (D26).
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show CapabilityException, Registration;
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show ShaderStageKind;

/// One stage a `.f3dmat` source becomes, as GLSL the engine's emitter wrote:
/// the fragment stage, and a `vertex` block's two vertex stages.
final class MaterialStageSource {
  /// A stage of [kind]; without one, a fragment stage when [fragment] is
  /// true and a vertex stage otherwise.
  const MaterialStageSource({
    required this.name,
    bool fragment = false,
    ShaderStageKind? kind,
    required this.glsl,
  }) : assert(
         kind == null || !fragment || identical(kind, ShaderStageKind.fragment),
         'a stage named fragment and given another kind',
       ),
       kind =
           kind ??
           (fragment ? ShaderStageKind.fragment : ShaderStageKind.vertex),
       fragment = kind == null
           ? fragment
           : identical(kind, ShaderStageKind.fragment);

  /// The entry point's name: the material's, or for its vertex stages
  /// `<name>Vertex` and `<name>VertexSkinned`, and from version 3 of the
  /// language `<name>VertexInstanced` and `<name>VertexLightmapped`.
  final String name;

  /// What the stage runs as.
  final ShaderStageKind kind;

  /// Whether this is a fragment stage: [kind] is
  /// [ShaderStageKind.fragment].
  final bool fragment;

  /// The stage as GLSL 4.60, its `#include`s of the engine's headers left
  /// in place for [MaterialCompileRequest.engineSources] to resolve.
  final String glsl;
}

/// What a [MaterialCompiler] is asked to compile: one growing object, so a
/// later minor that hands a compiler something more adds a member here and
/// breaks no compiler.
final class MaterialCompileRequest {
  const MaterialCompileRequest({
    required this.name,
    required this.from,
    required this.source,
    required this.stages,
    this.engineSources = const <String, String>{},
    this.atRunTime = false,
    this.options = const <String, Object?>{},
  });

  /// The key of [options] under which a caller hands WebGPU's compiler the
  /// stages it already wrote as WGSL, a `Map<String, PackedStage>` by stage
  /// name: the build writes them with glslang and naga, `RuntimeShaders`
  /// from the material's tree.
  static const String webGpuStagesOption = 'webGpuStages';

  /// The material's name, which every stage's entry point starts with.
  final String name;

  /// Where the source came from — a path, a plugin's id — for messages.
  final String from;

  /// The `.f3dmat` source itself.
  final String source;

  /// The stages the engine's emitter wrote from [source], in GLSL.
  final List<MaterialStageSource> stages;

  /// The engine's GLSL headers by path, what the stages `#include`.
  final Map<String, String> engineSources;

  /// Whether the game is running: a compiler that cannot compile without
  /// a toolchain the game does not ship refuses here (see
  /// [MaterialCompiler.compilesAtRunTime]).
  final bool atRunTime;

  /// What the backend's own compiler takes beside the rest, by name — the
  /// engine stage a WebGPU material is spliced into, say. A compiler reads
  /// the keys it knows and ignores the others.
  final Map<String, Object?> options;
}

/// What a [MaterialCompiler] made of a [MaterialCompileRequest]: its bundle
/// section's bytes.
final class MaterialCompileResult {
  const MaterialCompileResult({
    required this.section,
    this.notes = const <String>[],
  });

  /// The bytes of the backend's section in the material's `ShaderBundle`,
  /// under [MaterialCompiler.bundleSection].
  final ByteData section;

  /// What the compiler wants a person to know about the result: a stage it
  /// left out, a precision it lowered.
  final List<String> notes;
}

/// A compiler that cannot compile what it was asked, with the sentence
/// that says why and what to do instead.
final class MaterialCompileException extends CapabilityException {
  const MaterialCompileException(this.message);

  @override
  final String message;

  @override
  String toString() => 'MaterialCompileException: $message';
}

/// How one backend turns a `.f3dmat` source into its section of a
/// material's shader bundle (D26).
///
/// **What lets a fifth backend draw the material language.** The build
/// hook that compiles a project's materials, and the run time that compiles
/// a data plugin's (`RuntimeShaders`), find a backend's compiler in a
/// [MaterialCompilerRegistry] by the backend's name, rather than switching
/// over the four the engine ships. A backend package exports one and an
/// application registers it, beside the device it opens.
///
/// Extendable outside this package, and stays so through 1.x: a member
/// added later arrives with a default, and [compile] takes one growing
/// request rather than a list of parameters.
abstract base class MaterialCompiler {
  const MaterialCompiler();

  /// The backend's id, exactly as its `GraphicsDevice.backendId` gives it:
  /// `webgpu`, `vulkan`. [MaterialCompilerRegistry.forBackend] compares it
  /// as written; the engine's four are `cpu`, `webgl`, `webgpu` and
  /// `impeller`.
  String get backend;

  /// The key of the section this compiler writes in a `ShaderBundle`, and
  /// that the backend's device reads back.
  String get bundleSection;

  /// Whether [compile] can run while a game runs, with no toolchain beside
  /// it. False by default: what needs glslang, naga or impellerc runs in
  /// the build only.
  bool get compilesAtRunTime => false;

  /// Whether a build writes this backend's section with a tool of its own
  /// rather than through [compile]: Impeller's, which `impellerc` writes in
  /// the build. False by default.
  ///
  /// A build that asks such a compiler and is refused keeps the section it
  /// wrote; a refusal from any other compiler fails the build with its
  /// sentence, whatever the build wrote under the same section.
  bool get isSectionWrittenByBuild => false;

  /// The section [request] compiles to. Throws a [MaterialCompileException]
  /// for a source this backend cannot draw, saying why.
  MaterialCompileResult compile(MaterialCompileRequest request);

  @override
  String toString() => 'MaterialCompiler($backend)';
}

/// The material compilers of one build or one engine, by backend.
///
/// **One per build and one per engine, not one per process**: an
/// application makes one, registers the compilers of the backends it ships,
/// and hands it to `RuntimeShaders`; a build hook makes its own. A compiler
/// registered for a backend that already has one replaces it until its
/// registration is cancelled, so an application can swap the engine's.
final class MaterialCompilerRegistry {
  MaterialCompilerRegistry([Iterable<MaterialCompiler> compilers = const []]) {
    compilers.forEach(register);
  }

  final List<MaterialCompiler> _compilers = <MaterialCompiler>[];

  /// Every compiler registered, the latest last.
  List<MaterialCompiler> get compilers =>
      List<MaterialCompiler>.unmodifiable(_compilers);

  /// The backends a compiler is registered for, each once.
  Set<String> get backends => <String>{
    for (final compiler in _compilers) compiler.backend,
  };

  /// The compiler for [backend] — the one registered last — or null.
  /// [backend] is a backend id, compared exactly.
  MaterialCompiler? forBackend(String backend) {
    for (final compiler in _compilers.reversed) {
      if (compiler.backend == backend) return compiler;
    }
    return null;
  }

  /// Makes [compiler] the one [forBackend] answers for its backend, until
  /// the result is cancelled.
  ///
  /// Throws an [ArgumentError] when another compiler for another backend
  /// already writes the same [MaterialCompiler.bundleSection]: two backends
  /// reading one section would read each other's bytes.
  Registration register(MaterialCompiler compiler) {
    for (final other in _compilers) {
      if (other.backend != compiler.backend &&
          other.bundleSection == compiler.bundleSection) {
        throw ArgumentError.value(
          compiler.bundleSection,
          'compiler',
          'is the section the ${other.backend} compiler writes; '
              '${compiler.backend} needs one of its own',
        );
      }
    }
    _compilers.add(compiler);
    return Registration(() => _compilers.remove(compiler));
  }
}
