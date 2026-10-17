/// The shader contract a backend is written against (D27): what the
/// engine's stages bind, how the engine's uniform blocks are laid out, how a
/// backend compiles the material language, and the check that a pipeline's
/// stages agree.
///
/// **For a backend's author, inside this repository or outside it.** A
/// fifth backend — Vulkan or Metal through FFI, Direct3D, a headless server
/// renderer — reads here:
///
/// - [stageBindings]: the uniform blocks and samplers each of the engine's
///   stages keeps once compiled, which a draw through it must bind and may
///   bind — the table every in-repo backend binds by;
/// - [uniformBlocks]: every uniform block's members, offsets and sizes as the
///   compiler laid them out (std140);
/// - [MaterialCompiler] and [MaterialCompilerRegistry]: how the backend turns
///   a `.f3dmat` source into its section of a shader bundle, for the build
///   hook and for `RuntimeShaders` alike (D26);
/// - [ShaderTarget] and `compileStage` (`package:flutter3d_shaders/compile.dart`,
///   which needs glslang and naga on the machine): a stage's SPIR-V and its
///   text in the backend's language;
/// - [MaterialStageBudget]: the textures, samplers and uniform blocks one
///   stage may bind, the engine's and a material's together;
/// - [StageInterface] and [checkStageAgreement]: the varyings, attributes and
///   blocks two stages of a pipeline must agree on.
///
/// The entry points the engine asks a bundle for are `requiredShaders` and
/// `computeShaders` in `package:flutter3d_shaders/flutter3d_shaders.dart`;
/// the `F3D_*` defines the engine's GLSL is compiled with, and the bindings
/// a plugin's lit model adds, are written down in `docs/CONTRACTS.md`
/// ("The shader ABI").
///
/// **What changes in a minor.** The tables follow the shaders: a stage that
/// gains a sampler or a block that gains a member changes them in any
/// release, and a backend that binds by the tables follows without a code
/// change. The types here are the contract and only grow.
library;

export 'src/material_compiler.dart';
export 'src/shader_target.dart';
export 'src/stage_bindings.dart';
export 'src/stage_budget.dart';
export 'src/stage_interface.dart';
// The layout record is `UniformMemberLayout` from flutter3d_hardware, which
// the table names; it has no second declaration here.
export 'src/uniform_blocks.dart' show uniformBlocks;
