/// What a shader is on a backend with no shading language.
///
/// The engine asks a library for entry points by name — `MeshVertex`, `Pbr`,
/// `Composite` — and nothing in `flutter3d_hardware` says those names have to
/// resolve to GLSL. `PipelineHandle.backend` is an `Object`. So here they
/// resolve to Dart, and whether that was ever really allowed is the question
/// this whole package exists to answer.
///
/// The four pieces of that answer are their own files, re-exported from here
/// so every existing `import 'cpu_shader.dart'` still sees all of them:
/// [ShaderBindings] reads what the engine bound (`cpu_shader_bindings.dart`);
/// [CpuTexture] and [BoundTexture] are a texture and a sampled one
/// (`cpu_texture.dart`); [CpuVertexShader], [FragmentContext],
/// [CpuFragmentShader] and [CpuStage] are the shapes a stage takes
/// (`cpu_shader_stage.dart`).
library;

export 'cpu_shader_bindings.dart';
export 'cpu_shader_stage.dart';
export 'cpu_texture.dart';
