/// A `flutter3d_hardware` backend that rasterises in Dart.
///
/// Two hardware backends agreeing proves less than it looks like: both are
/// driven by a C API and both rasterise on a GPU, so an assumption shared by
/// graphics hardware would be invisible to the pair of them. This one shares
/// nothing with either — no driver, no shading language, no command buffer.
///
/// Whether that was really allowed is what running it answers.
library;

export 'src/cpu_backend_registration.dart';
export 'src/cpu_device.dart' show CpuDevice;
export 'src/cpu_png.dart';
export 'src/cpu_shader.dart';
export 'src/cpu_shader_library.dart'
    show CpuLoadedShaderLibrary, CpuMaterialCompiler, CpuShaderLibrary;
export 'src/cpu_shaders_builtin.dart' show builtinCpuShaders;
export 'src/frame_difference.dart';

// The engine's own stages (`PbrShader`, `SkyShader` and some eighty more),
// the helpers they share (`accumulateLights`, `writeLit`, …), the encoders
// and the vertex fetch are not exported since 1.0: they are this backend's
// translation of the engine's shaders, and a change to any of them would
// otherwise be a major release. What is exported is the kit a stage is
// written with — `CpuStage`, the shader base classes, `ShaderBindings`,
// `FragmentContext` and the texture types — and the device.
