/// WebGL2's compiler for the material language (D26).
library;

import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:flutter3d_shaders/translate.dart'
    show
        GlslTranslateException,
        StageAgreementException,
        encodeWebGlSection,
        translateGlsl;

/// Writes WebGL2's section of a material's bundle: each stage the engine's
/// emitter wrote, translated to GLSL ES 3.00 against the engine's headers.
///
/// **Text in, text out, so it runs while a game runs.** The browser is the
/// compiler; what has to be done ahead of it is the translation, and that
/// needs nothing but [MaterialCompileRequest.engineSources] — the headers
/// the stages `#include`, which a browser has no disk to read them from.
/// Without them the request is refused, saying so.
///
/// The section is the one `tool/pack_shaders.dart` writes for a bundle an
/// application packs, so its stages are held to each other the same way: a
/// vertex stage that disagrees with its fragment stage is refused with both
/// names.
///
/// Registered by `registerWebGlBackend(compilers:)` beside the device.
final class WebGlSectionCompiler extends MaterialCompiler {
  /// Holds no state; `registerWebGlBackend` registers one beside the device.
  const WebGlSectionCompiler();

  @override
  String get backend => 'webgl';

  @override
  String get bundleSection => ShaderBundle.webglSection;

  @override
  bool get compilesAtRunTime => true;

  @override
  MaterialCompileResult compile(MaterialCompileRequest request) {
    if (request.engineSources.isEmpty) {
      throw const MaterialCompileException(
        'a material is translated to GLSL ES against the engine\'s own GLSL '
        'headers, and this request carries none. Hand RuntimeShaders the '
        'headers (flutter3d_shaders\' sources, shipped as assets) as '
        'engineSources',
      );
    }
    try {
      String translate(MaterialStageSource stage) => translateGlsl(
        stage.glsl,
        request.engineSources,
        from: request.from,
        fragment: stage.fragment,
      );
      return MaterialCompileResult(
        section: encodeWebGlSection(
          vertex: <String, String>{
            for (final stage in request.stages)
              if (!stage.fragment) stage.name: translate(stage),
          },
          fragment: <String, String>{
            for (final stage in request.stages)
              if (stage.fragment) stage.name: translate(stage),
          },
        ),
      );
    } on GlslTranslateException catch (error, stack) {
      Error.throwWithStackTrace(MaterialCompileException(error.message), stack);
    } on StageAgreementException catch (error, stack) {
      Error.throwWithStackTrace(MaterialCompileException(error.message), stack);
    }
  }
}
