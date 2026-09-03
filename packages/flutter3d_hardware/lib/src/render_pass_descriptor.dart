/// What a render pass draws into, in the engine's own vocabulary: a rectangle,
/// a blend equation, a stencil configuration, and the colour and depth
/// attachments a [RenderPassDescriptor] bundles them into.
///
/// Split out of `command_encoder.dart` because these are value types with no
/// behaviour beyond equality — [PassEncoder] and [CommandEncoder] are the
/// verbs this file's nouns are for.
library;

import 'package:vector_math/vector_math.dart' as vm;

import 'formats.dart';
import 'texture.dart';

/// A rectangle of a render target, in pixels.
///
/// One type for both the viewport and the scissor, because every site in this
/// engine sets them to the same rectangle — with one exception, the composite's
/// overlay loop, which re-aims the viewport per view inside a scissor that
/// already covers the whole frame. That exception is why they are still two
/// methods and not one.
final class ScreenRect {
  const ScreenRect({
    this.x = 0,
    this.y = 0,
    required this.width,
    required this.height,
  });

  /// The whole of a texture.
  factory ScreenRect.of(TextureHandle texture) =>
      ScreenRect(width: texture.width, height: texture.height);

  final int x;
  final int y;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is ScreenRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'ScreenRect($x, $y, ${width}x$height)';
}

/// How a draw is combined with what the attachment already holds.
///
/// A value type with `==`, so a backend can cache one native object per
/// distinct state and a test can assert on the state a pass was left in — the
/// same two reasons `SamplerOptions` is one.
///
/// The field set and the defaults are flutter_gpu's, unchanged, which is what
/// makes [alphaBlend] exactly the equation the engine used to get by
/// constructing an empty `ColorBlendEquation`.
final class BlendState {
  const BlendState({
    this.colorOperation = BlendOperation.add,
    this.sourceColorFactor = BlendFactor.one,
    this.destinationColorFactor = BlendFactor.oneMinusSourceAlpha,
    this.alphaOperation = BlendOperation.add,
    this.sourceAlphaFactor = BlendFactor.one,
    this.destinationAlphaFactor = BlendFactor.oneMinusSourceAlpha,
  });

  /// Source over destination, with the source colour taken as premultiplied —
  /// the source factor is [BlendFactor.one] and not `sourceAlpha`. What
  /// transparent materials draw with.
  static const BlendState alphaBlend = BlendState();

  /// Both terms added. What particles and the bloom upsample draw with.
  ///
  /// Addition is commutative, which is what lets a thousand particles composite
  /// correctly in one unsorted batch.
  static const BlendState additive = BlendState(
    sourceColorFactor: BlendFactor.one,
    destinationColorFactor: BlendFactor.one,
    sourceAlphaFactor: BlendFactor.one,
    destinationAlphaFactor: BlendFactor.one,
  );

  /// The attachment kept exactly as it was: nothing of the source, all of the
  /// destination.
  ///
  /// **A draw that exists for its side effects.** flutter_gpu has no colour
  /// write mask, and a fragment that `discard`s writes neither depth nor
  /// stencil — so a pass that wants to mark the stencil where a mesh is, and
  /// leave the picture alone, has exactly one way to say so, and this is it.
  /// The x-ray stage's marking draw is the caller; a backend has to honour
  /// the zero and one factors for it, which the software rasteriser did not
  /// until it had a reason to.
  static const BlendState keepDestination = BlendState(
    sourceColorFactor: BlendFactor.zero,
    destinationColorFactor: BlendFactor.one,
    sourceAlphaFactor: BlendFactor.zero,
    destinationAlphaFactor: BlendFactor.one,
  );

  final BlendOperation colorOperation;
  final BlendFactor sourceColorFactor;
  final BlendFactor destinationColorFactor;
  final BlendOperation alphaOperation;
  final BlendFactor sourceAlphaFactor;
  final BlendFactor destinationAlphaFactor;

  @override
  bool operator ==(Object other) =>
      other is BlendState &&
      other.colorOperation == colorOperation &&
      other.sourceColorFactor == sourceColorFactor &&
      other.destinationColorFactor == destinationColorFactor &&
      other.alphaOperation == alphaOperation &&
      other.sourceAlphaFactor == sourceAlphaFactor &&
      other.destinationAlphaFactor == destinationAlphaFactor;

  @override
  int get hashCode => Object.hash(
    colorOperation,
    sourceColorFactor,
    destinationColorFactor,
    alphaOperation,
    sourceAlphaFactor,
    destinationAlphaFactor,
  );
}

/// One colour attachment of a pass.
final class ColorTarget {
  const ColorTarget({
    required this.texture,
    this.resolveTexture,
    this.loadAction = LoadAction.clear,
    this.storeAction = StoreAction.store,
    this.clearValue,
  });

  /// Where the rasteriser writes. Multisampled when [resolveTexture] is set.
  final TextureHandle texture;

  /// Where a multisampled [texture] is resolved to when the pass ends.
  ///
  /// Setting this means [storeAction] must be a resolving one; the backend
  /// checks. Attachments in one pass must agree on sample count, which is the
  /// constraint that makes the scene pass drop multisampling entirely whenever
  /// the surface buffer is wanted.
  final TextureHandle? resolveTexture;

  /// [LoadAction.clear] covers the **whole attachment** however the viewport
  /// and the scissor are set. The shadow atlas depends on that: it loads, and
  /// blanks one tile by drawing inside it.
  final LoadAction loadAction;
  final StoreAction storeAction;

  /// Null clears to transparent black. Linear light, not sRGB, for anything
  /// written into an HDR target.
  final vm.Vector4? clearValue;
}

/// How the stencil test treats the draws that follow, for one face.
///
/// A value type with `==`, like [BlendState] and for the same two reasons: a
/// backend can cache one native object per distinct state, and a test can
/// assert on the state a pass was left in.
///
/// The field set is flutter_gpu's `StencilConfig`. The defaults are the test
/// switched off — always passes, nothing written — which is what every pass
/// that never mentions the stencil gets, and what [disabled] names so a pass
/// that *did* mention it can say it is done.
///
/// **The masks default to eight bits, not thirty-two.** flutter_gpu's own
/// default is `0xFFFFFFFF`, and the difference is invisible on it: every
/// stencil format `TextureFormat` names holds eight bits, so the high bits of
/// a mask meet nothing. The narrower default is stated because a backend
/// exists — WebGL2 — whose `stencilMask` is *specified* against the
/// attachment's bit depth, and a value the specification calls out of range
/// is a value somebody will eventually have to explain.
final class StencilState {
  const StencilState({
    this.compare = CompareFunction.always,
    this.failOp = StencilOperation.keep,
    this.depthFailOp = StencilOperation.keep,
    this.passOp = StencilOperation.keep,
    this.readMask = 0xFF,
    this.writeMask = 0xFF,
  });

  /// The test off: every fragment passes it and none changes the buffer.
  static const StencilState disabled = StencilState();

  /// The eight bits a stencil reference has, out of whatever it was handed.
  ///
  /// Every backend narrows through this rather than each in its own way, and
  /// the reason is that the three ways do not agree. A software rasteriser
  /// that masks wraps 0x101 to 1; WebGL2's `stencilFunc` is specified to
  /// *clamp* the reference to the attachment's range, so the same value
  /// becomes 255 there; flutter_gpu passes it to a descriptor field and says
  /// nothing. One call site behind all three makes the answer the contract's
  /// rather than the backend's — which matters the day something wants a
  /// second marked layer and starts counting references upward.
  ///
  /// **A mask rather than an assert**, which was the other candidate. Eight
  /// bits is a fact about every stencil attachment the engine can allocate,
  /// not a house rule a caller is breaking, and an assert would have left the
  /// three backends disagreeing in a release build — which is the half of the
  /// problem that cannot be caught by running the tests.
  static int narrowReference(int value) => value & 0xFF;

  /// How the reference value is compared against what is stored. The
  /// reference is the *new* value in [CompareFunction]'s wording: `less`
  /// passes when the reference is below the stored value.
  final CompareFunction compare;

  /// What happens to the stored value when the stencil test fails.
  final StencilOperation failOp;

  /// What happens when the stencil test passes and the depth test fails.
  final StencilOperation depthFailOp;

  /// What happens when both tests pass.
  final StencilOperation passOp;

  /// Which bits of the stored value and the reference take part in the
  /// comparison.
  final int readMask;

  /// Which bits of the stored value an operation may change.
  final int writeMask;

  @override
  bool operator ==(Object other) =>
      other is StencilState &&
      other.compare == compare &&
      other.failOp == failOp &&
      other.depthFailOp == depthFailOp &&
      other.passOp == passOp &&
      other.readMask == readMask &&
      other.writeMask == writeMask;

  @override
  int get hashCode =>
      Object.hash(compare, failOp, depthFailOp, passOp, readMask, writeMask);

  @override
  String toString() =>
      'StencilState(${compare.name}, fail: ${failOp.name}, '
      'depthFail: ${depthFailOp.name}, pass: ${passOp.name}, '
      'read: 0x${readMask.toRadixString(16)}, '
      'write: 0x${writeMask.toRadixString(16)})';
}

/// The depth and stencil attachment of a pass.
///
/// Narrower than what the backend offers, and that is the engine's model
/// rather than an omission: every pass here clears depth on entry and
/// discards it on exit, so those two have nothing to configure and nothing is
/// offered. A pass that wanted to *load* depth would be asking for something
/// no pass in this engine has ever asked for, and the interface should grow
/// when one does.
///
/// The stencil half *is* configurable, because the x-ray stage asked: it
/// marks the stencil inside the scene pass and reads the marks back a few
/// draws later, which needs the buffer cleared to a known value on entry. The
/// three fields are flutter_gpu's own, and their defaults — clear to zero,
/// throw away at the end — are what every pass that never mentions the
/// stencil has always had.
final class DepthTarget {
  const DepthTarget({
    required this.texture,
    this.clearValue = 1.0,
    this.stencilLoadAction = LoadAction.clear,
    this.stencilStoreAction = StoreAction.dontCare,
    this.stencilClearValue = 0,
  });

  final TextureHandle texture;

  /// The far plane. One under this engine's `[0, 1]` depth convention; a
  /// reversed-Z backend would want zero, which is why it is a parameter.
  final double clearValue;

  /// What the stencil holds when the pass opens. [LoadAction.clear] fills it
  /// with [stencilClearValue] across the whole attachment, as every clear
  /// here does; [LoadAction.load] keeps what the last pass stored.
  final LoadAction stencilLoadAction;

  /// Whether the stencil survives the pass. Nothing in this engine reads one
  /// across passes yet, so the default discards it, which is free on tile
  /// memory and merely honest elsewhere.
  final StoreAction stencilStoreAction;

  /// Eight bits, masked to the attachment's depth by the backend.
  final int stencilClearValue;
}

/// Everything a pass draws into.
final class RenderPassDescriptor {
  const RenderPassDescriptor({required this.colors, this.depth});

  /// In shader output order. Two of them exactly once — the scene pass, which
  /// writes lit colour and the surface buffer together.
  ///
  /// A pipeline may declare more outputs than the target has attachments and
  /// the extra is discarded, which is what lets the scene shaders write the
  /// surface buffer unconditionally and this list decide whether anyone is
  /// listening. See ARCHITECTURE.md §2.
  final List<ColorTarget> colors;

  final DepthTarget? depth;
}
