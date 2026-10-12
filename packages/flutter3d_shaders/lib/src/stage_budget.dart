/// What one stage may bind: the budget a material's stages are held to.
library;

/// The textures, samplers and uniform blocks one stage of a pipeline may
/// bind, the engine's own bindings and a material's together (M3).
///
/// **WebGPU's guaranteed minimums, the tightest of the four backends.** A
/// WebGPU device may report more, and the engine asks the adapter for what
/// it has, but a bundle built for any browser can count only on what every
/// device gives: 16 sampled textures, 16 samplers and 12 uniform buffers in
/// a stage. A texture the material language binds is a texture and a
/// sampler on WebGPU, so a stage's textures count against both.
///
/// The build refuses a stage over the budget, naming it and the count
/// (`wgslSectionDocument`, which every writer of a WebGPU section calls), so
/// a material that would fail to make its pipeline on somebody's device
/// fails on the author's machine instead. The engine's stages leave a lit
/// model's own bindings what `docs/CONTRACTS.md` ("A material's own blocks
/// and textures") says.
abstract final class MaterialStageBudget {
  /// Sampled textures in one stage.
  static const int textures = 16;

  /// Samplers in one stage.
  static const int samplers = 16;

  /// Uniform blocks in one stage.
  static const int uniformBlocks = 12;

  /// Why a stage named [stage] that binds [textures] textures, [samplers]
  /// samplers and [uniformBlocks] uniform blocks is over the budget, or null
  /// when it is within it.
  static String? problem(
    String stage, {
    required int textures,
    required int samplers,
    required int uniformBlocks,
  }) {
    String over(int count, int budget, String what) =>
        'the stage "$stage" binds $count $what, and a stage may bind at most '
        '$budget on WebGPU, the engine\'s own bindings included: that is '
        'what every WebGPU device guarantees. Bind fewer in the material, '
        'or pack two maps into the channels of one';
    if (textures > MaterialStageBudget.textures) {
      return over(textures, MaterialStageBudget.textures, 'textures');
    }
    if (samplers > MaterialStageBudget.samplers) {
      return over(samplers, MaterialStageBudget.samplers, 'samplers');
    }
    if (uniformBlocks > MaterialStageBudget.uniformBlocks) {
      return over(
        uniformBlocks,
        MaterialStageBudget.uniformBlocks,
        'uniform blocks',
      );
    }
    return null;
  }
}
