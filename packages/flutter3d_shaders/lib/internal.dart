/// What the engine's renderer (`flutter3d_core`) reads about the shaders: a
/// typed block per uniform struct (`FrameInfoBlock` and the rest). No
/// backend imports it: which blocks and samplers each stage binds, and every
/// block's layout, are the backend author's contract in
/// `package:flutter3d_shaders/backend.dart`.
///
/// **For the engine's renderer; not covered by semver for applications.**
/// These tables follow the shaders: a stage that gains a sampler or a block
/// that gains a member changes them in any release. They are a library of
/// their own rather than `src/` imports so `flutter3d_core` depends on
/// something the API snapshot sees, and a change here shows up in review;
/// an application that binds the engine's own blocks by these names is
/// reaching into the engine, and a minor may move what it reads.
///
/// The engine's packages ask for each other within one minor
/// (`'>=1.0.0 <1.1.0'`), so a shaders 1.1 that moves these tables never
/// resolves under a renderer 1.0 built against the tables before them.
library;

export 'src/typed_blocks.dart';
