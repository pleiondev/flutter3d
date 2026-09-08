/// Every point of `flutter3d_hardware` this spike could not implement without
/// something changing, and what each one would cost.
///
/// **The answer the spike was written to produce, kept as data rather than as
/// prose.** A list a test can count is a list that cannot quietly grow a
/// fourteenth entry while the README goes on saying thirteen — which is the
/// failure `tool/structure.dart` exists for, applied to a document too small to
/// deserve a rule of its own. `webgpu_contract_gaps_test.dart` holds the README
/// to this list.
///
/// **What is deliberately not here.** Everything WebGPU does differently and
/// answers for itself: the framebuffer origin, the depth range, the row padding
/// a readback has to undo, rasteriser state moving into the pipeline object.
/// Those are the contract working — it asks rather than assumes, or it states a
/// rule the backend has to keep, and the backend keeps it. A list that included
/// them would say the contract is OpenGL-shaped by counting the places it is
/// not.
///
/// The winding is not here either, and it was going to be: the argument from
/// coordinate systems predicts that WebGPU calls the engine's front faces back
/// ones, and a draw on a real GPU says it does not. See `gpuFrontFace`.
library;

/// What it would take to close one gap.
///
/// An enum in a program under `tool/`, which is the one place in this repository
/// an enum is not a promise to anybody: nothing outside this directory can
/// `switch` on it, so adding a value breaks nothing. See the
/// "an enum in a published package is machinery or is not an enum" rule for why
/// that sentence has to be said.
enum GapCost {
  /// A line added to `flutter3d_hardware`. The three backends that exist do not
  /// read it and do not change.
  byAddition,

  /// A term of the contract that would have to mean something else, which the
  /// three existing backends are written against.
  byRewriting,
}

/// One thing the contract owes a WebGPU implementation.
final class ContractGap {
  const ContractGap({
    required this.point,
    required this.cost,
    required this.why,
  });

  /// The member, type or constant, spelled as `flutter3d_hardware` spells it.
  final String point;

  final GapCost cost;

  /// What goes wrong without it, in one sentence a reader can act on.
  final String why;

  @override
  String toString() => '$point (${cost.name}): $why';
}

/// The gaps, most expensive first.
///
/// Four, and only one of them is a rewrite.
const List<ContractGap> webgpuContractGaps = <ContractGap>[
  ContractGap(
    point: 'BlendFactor.blendAlpha, BlendFactor.oneMinusBlendAlpha',
    cost: GapCost.byRewriting,
    why:
        'OpenGL, Metal and Vulkan all split the blend constant into a '
        'per-channel colour and a broadcast alpha, and these two are the alpha '
        'half of that split. WebGPU has "constant" and "one-minus-constant" '
        'and no third spelling, so the alpha half cannot be formed in the '
        'colour equation at all. GraphicsDevice.supportsBlendColor is one '
        'answer for all four factors, so a WebGPU backend that has two of them '
        'has no way to say so: it answers false, refuses the two it could have '
        'honoured, and the four values go back to being the dead corner the '
        'capability was added to revive. Splitting the capability, or letting a '
        'backend refuse a named factor, is the change — and it changes what '
        'true means, which the three existing backends are written against.',
  ),
  ContractGap(
    point: 'ShaderBundle.webgpuSection',
    cost: GapCost.byAddition,
    why:
        'The bundle names one section per backend that needs compiled code and '
        'has two constants for the two that do. A WebGPU backend reads WGSL, '
        'which is a third. One const String beside impellerSection and '
        'webglSection, and nothing else in the package moves.',
  ),
  ContractGap(
    point:
        'ShaderBundle: reflection beside the code — block, sampler and '
        'attribute names',
    cost: GapCost.byAddition,
    why:
        'PassEncoder.bindUniformBlock takes a block name, bindTexture takes a '
        'sampler name, and InputAttribute.name says explicitly that a name is '
        'used because "the two hardware backends disagree about which is '
        'authoritative and both agree about names". WGSL has neither at run '
        'time: a binding is @group and @binding, an attribute is @location, and '
        'GPUShaderModule exposes nothing about either. Impeller reads its '
        'reflection out of impellerc\'s flatbuffer and WebGL2 asks the context, '
        'so both get this for free from their own compiled form; a WebGPU '
        'section has to carry it. That is a property of the section, so it fits '
        'inside the constant above — but it is listed apart because it is what '
        'the work actually is, and because a section carrying WGSL and nothing '
        'else would look complete and answer no name.',
  ),
  ContractGap(
    point: 'GraphicsDevice.createPipeline, the null layout',
    cost: GapCost.byAddition,
    why:
        'A null layout means "the backend works it out from the shader", which '
        'is what every pipeline in the engine still passes. Impeller works it '
        'out from reflection and WebGL2 from getActiveAttrib; WebGPU has no '
        'reflection to work it out from, so a null layout is a pipeline that '
        'cannot be built. Closed by the same reflection sidecar as the entry '
        'above — the alternative, making the layout required, would change '
        'every call site in the engine rather than one package.',
  ),
];
