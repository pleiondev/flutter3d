/// The software device's half of the material language: the stages that run
/// a material written as source on `CpuDevice`.
///
///     import 'package:flutter3d_app/software.dart';
///
/// A second entry point rather than more exports on the main barrel, for
/// the reason `native.dart` is one. [MaterialProgramStage],
/// [MaterialVertexStage] and [MaterialFullscreenStage] are stages of the
/// software rasterizer, and naming them from the main barrel made its stage
/// interface (`CpuFragmentShader`, `ShaderBindings`, `FragmentContext`) part
/// of every application's import, so a change to how that rasterizer runs a
/// fragment would be a major release of this package. `openDevice` builds
/// them for a material on its own; a test or a tool that puts one into a
/// `CpuShaderLibrary` by hand imports this, and `flutter3d_cpu` beside it.
library;

export 'src/materials/material_language_stage.dart';
