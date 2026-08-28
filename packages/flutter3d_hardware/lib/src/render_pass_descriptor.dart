/// What a render pass draws into, in the engine's own vocabulary: a rectangle,
/// a blend equation, and the colour and depth attachments a
/// [RenderPassDescriptor] bundles them into.
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

/// The depth attachment of a pass.
///
/// Far narrower than what the backend offers, and that is the engine's model
/// rather than an omission: every pass here clears depth on entry, discards it
/// on exit, and uses no stencil at all. There is nothing to configure, so
/// nothing is offered. A pass that wanted to *load* depth would be asking for
/// something no pass in this engine has ever asked for, and the interface
/// should grow when one does.
final class DepthTarget {
  const DepthTarget({required this.texture, this.clearValue = 1.0});

  final TextureHandle texture;

  /// The far plane. One under this engine's `[0, 1]` depth convention; a
  /// reversed-Z backend would want zero, which is why it is a parameter.
  final double clearValue;
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
