/// WebGPU's compiler for the material language (D26).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:flutter3d_shaders/translate.dart'
    show
        PackedStage,
        StageAgreementException,
        WgslSectionException,
        wgslSectionDocument;

/// Packs WebGPU's section of a material's bundle from stages already written
/// as WGSL, with their reflection.
///
/// **What it reads.** The material language's WGSL is written from the
/// material's tree by `RuntimeShaders` (spliced into `webGpuMaterialHost()`'s
/// stage, or a full-screen stage written whole), and handed over under the
/// option [stagesOption] as a `Map<String, PackedStage>` by stage name. This
/// compiler packs them into the section document the device reads, holding
/// a vertex stage to its fragment stage as every section writer does.
///
/// **What it does not do is run glslang or naga**, which make the engine's
/// WGSL in the build and ship with no game: a request without the stages is
/// refused, and the build writes the section with those two programs
/// (`flutter3d_build`'s material step).
///
/// Registered with `MaterialCompilerRegistry.register` beside the device, as
/// `compilers.register(const WebGpuSectionCompiler())`.
final class WebGpuSectionCompiler extends MaterialCompiler {
  const WebGpuSectionCompiler();

  /// The option a [MaterialCompileRequest] carries the written stages under.
  static const String stagesOption = 'webGpuStages';

  @override
  String get backend => 'webgpu';

  @override
  String get bundleSection => ShaderBundle.webgpuSection;

  @override
  bool get compilesAtRunTime => true;

  @override
  MaterialCompileResult compile(MaterialCompileRequest request) {
    final stages = request.options[stagesOption];
    if (stages is! Map<String, PackedStage>) {
      throw const MaterialCompileException(
        'WebGPU packs stages already written as WGSL, and this request '
        'carries none: glslang and naga, which write them from GLSL, run in '
        'the build only. Hand RuntimeShaders webGpuMaterialHost() as '
        'webGpuHost so the material is written into the engine\'s stage, or '
        'put it in assets_src/ and let flutter3d_build compile it into the '
        'bundle',
      );
    }
    final fragments = <String>{
      for (final stage in request.stages)
        if (stage.fragment) stage.name,
    };
    final String document;
    try {
      document = wgslSectionDocument(
        vertex: <String, PackedStage>{
          for (final MapEntry(:key, :value) in stages.entries)
            if (!fragments.contains(key)) key: value,
        },
        fragment: <String, PackedStage>{
          for (final MapEntry(:key, :value) in stages.entries)
            if (fragments.contains(key)) key: value,
        },
      );
    } on WgslSectionException catch (error) {
      throw MaterialCompileException(error.message);
    } on StageAgreementException catch (error) {
      throw MaterialCompileException(error.message);
    }
    return MaterialCompileResult(
      section: Uint8List.fromList(utf8.encode(document)).buffer.asByteData(),
    );
  }
}
