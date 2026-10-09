/// What the engine's renderer and its four backends read about the shaders:
/// which blocks and samplers each stage binds ([stageBindings]), every
/// uniform block's layout as the compiler laid it out ([uniformBlocks]), and
/// a typed block per uniform struct (`FrameInfoBlock` and the rest).
///
/// **For engine backends; not covered by semver for applications.** These
/// tables follow the shaders: a stage that gains a sampler or a block that
/// gains a member changes them in any release. They are a library of their
/// own rather than `src/` imports so the backends and `flutter3d_core`
/// depend on something the API snapshot sees — a change here shows up in
/// review — but an application that binds the engine's own blocks by these
/// names is reaching into the engine, and a minor may move what it reads.
library;

export 'src/stage_bindings.dart';
export 'src/typed_blocks.dart';
// The layout record is `UniformMemberLayout` from flutter3d_hardware, the
// same shape; this file's own typedef of it stays private to the table.
export 'src/uniform_blocks.dart' show uniformBlocks;
