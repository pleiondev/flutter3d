/// What a render pass draws into, in the engine's own vocabulary: a rectangle,
/// a blend equation, a stencil configuration, and the colour and depth
/// attachments a [RenderPassDescriptor] bundles them into.
///
/// Split out of `command_encoder.dart` because these are value types with no
/// behaviour beyond equality — [PassEncoder] and [CommandEncoder] are the
/// verbs this file's nouns are for.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor, UnsupportedCapabilityException;
import 'package:meta/meta.dart';

import 'capabilities.dart';
import 'device_exceptions.dart';
import 'format_info.dart';
import 'formats.dart';
import 'resources.dart';
import 'texture.dart';

/// A rectangle of a render target, in whole pixels: the scissor, a readback
/// region, an overwrite's region.
///
/// **The viewport is a [PassViewport] since 1.0.0-rc.1+2**, with a rectangle in
/// doubles and a depth range, which is what WebGPU and flutter_gpu set; the
/// scissor stays whole pixels on every API. [PassViewport.ofRect] turns one of
/// these into the viewport over the same pixels.
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

/// Where the rasteriser maps clip space: a rectangle of the target in pixels,
/// which may be fractional, and the window depth range clip depth maps onto —
/// `PassEncoder.setViewport`.
///
/// **A rectangle in doubles and a depth range**, the two things every native
/// viewport has that a [ScreenRect] cannot say. Clip depth from the device's
/// `GraphicsDevice.depthRange` maps linearly onto [minDepth]..[maxDepth],
/// both in `[0, 1]`; the defaults are the whole range, which is what every
/// pass had before. A rectangle that is not whole pixels needs
/// `DeviceFeature.fractionalViewport` ([checkFeatures]); the depth range
/// needs nothing.
@immutable
final class PassViewport {
  /// The viewport [width] by [height] pixels from ([x], [y]), mapping depth
  /// onto [minDepth]..[maxDepth].
  const PassViewport({
    this.x = 0,
    this.y = 0,
    required this.width,
    required this.height,
    this.minDepth = 0,
    this.maxDepth = 1,
  }) : assert(
         0 <= minDepth && minDepth <= maxDepth && maxDepth <= 1,
         'a depth range lies in [0, 1] and starts at or below where it ends',
       ),
       assert(width >= 0 && height >= 0, 'a viewport has no negative size');

  /// The viewport over the whole of [texture], with the whole depth range.
  factory PassViewport.of(TextureHandle texture) => PassViewport(
    width: texture.width.toDouble(),
    height: texture.height.toDouble(),
  );

  /// The viewport over exactly the pixels of [rect], with the whole depth
  /// range — what a pass that sets its viewport and its scissor to the same
  /// rectangle says for the first.
  factory PassViewport.ofRect(ScreenRect rect) => PassViewport(
    x: rect.x.toDouble(),
    y: rect.y.toDouble(),
    width: rect.width.toDouble(),
    height: rect.height.toDouble(),
  );

  /// The left edge, in pixels from the target's left.
  final double x;

  /// The top edge, in pixels from row zero (see `FramebufferOrigin`).
  final double y;

  /// How wide, in pixels.
  final double width;

  /// How high, in pixels.
  final double height;

  /// The window depth the near end of clip depth maps to: a depth from 0 to
  /// 1, unitless.
  final double minDepth;

  /// The window depth the far end of clip depth maps to: a depth from 0 to
  /// 1, unitless.
  final double maxDepth;

  /// Whether the rectangle lies on whole pixels — what a backend whose API
  /// takes integers can set exactly.
  bool get isWholePixels =>
      x == x.roundToDouble() &&
      y == y.roundToDouble() &&
      width == width.roundToDouble() &&
      height == height.roundToDouble();

  /// Whether the depth range is the whole of `[0, 1]`.
  bool get coversFullDepth => minDepth == 0 && maxDepth == 1;

  /// The rectangle rounded to whole pixels — for a backend whose API takes
  /// integers, once [checkFeatures] has let it through.
  ScreenRect get rect => ScreenRect(
    x: x.round(),
    y: y.round(),
    width: width.round(),
    height: height.round(),
  );

  /// Throws [UnsupportedCapabilityException] when this viewport needs a
  /// feature [features] lacks: a rectangle that is not whole pixels
  /// (`fractionalViewport`).
  ///
  /// **For a backend's `setViewport`**, so that every backend refuses the
  /// same viewports in the same words, and a field a minor adds with its
  /// feature is refused by a backend written before it rather than ignored.
  void checkFeatures(DeviceFeatures features, {required String backend}) {
    if (!isWholePixels) {
      features.require(
        DeviceFeature.fractionalViewport,
        backend: backend,
        reason: 'the viewport $this is not whole pixels',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PassViewport &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.minDepth == minDepth &&
      other.maxDepth == maxDepth;

  @override
  int get hashCode => Object.hash(x, y, width, height, minDepth, maxDepth);

  @override
  String toString() =>
      'PassViewport($x, $y, ${width}x$height'
      '${coversFullDepth ? '' : ', depth $minDepth..$maxDepth'})';
}

/// What a colour attachment is cleared to: four channels of one kind.
///
/// **An immutable value of doubles, since 1.0.0-rc.1+2.** It was a
/// `vector_math` `Vector4`: mutable inside an immutable descriptor, the one
/// third-party type in the contract, and float32, so an integer target (an
/// `r32UInt` id buffer) cleared exactly only up to 2^24. A double holds every
/// 32-bit integer exactly, and the three constructors say which kind of
/// target the value is for: [ClearColor.new] for float and normalised
/// formats, [ClearColor.uint] and [ClearColor.sint] for the integer ones.
@immutable
final class ClearColor {
  /// A float clear, for a float, normalised or sRGB target. Linear light,
  /// not sRGB, for anything written into an HDR target.
  const ClearColor(
    double this.red,
    double this.green,
    double this.blue,
    double this.alpha,
  ) : kind = ClearColorKind.float;

  /// An unsigned integer clear, for a `…UInt` target. Each channel is
  /// written as it is, in the target's own width.
  const ClearColor.uint(
    int this.red,
    int this.green,
    int this.blue,
    int this.alpha,
  ) : kind = ClearColorKind.uint,
      assert(
        red >= 0 && green >= 0 && blue >= 0 && alpha >= 0,
        'an unsigned clear has no negative channel',
      );

  /// A signed integer clear, for a `…SInt` target.
  const ClearColor.sint(
    int this.red,
    int this.green,
    int this.blue,
    int this.alpha,
  ) : kind = ClearColorKind.sint;

  /// A float clear to [color], channel for channel.
  factory ClearColor.fromLinear(LinearColor color) =>
      ClearColor(color.r, color.g, color.b, color.a);

  /// Transparent black, which is what a null `ColorTarget.clearValue` means.
  static const ClearColor transparentBlack = ClearColor(0, 0, 0, 0);

  /// Which kind of target the channels are for.
  final ClearColorKind kind;

  /// The red channel: a double for [ClearColorKind.float], an int otherwise.
  final num red;

  /// The green channel, as [red].
  final num green;

  /// The blue channel, as [red].
  final num blue;

  /// The alpha channel, as [red].
  final num alpha;

  /// The four channels as doubles, in order — exact for every kind, since a
  /// double holds every 32-bit integer.
  List<double> get channels => <double>[
    red.toDouble(),
    green.toDouble(),
    blue.toDouble(),
    alpha.toDouble(),
  ];

  @override
  bool operator ==(Object other) =>
      other is ClearColor &&
      other.kind == kind &&
      other.red == red &&
      other.green == green &&
      other.blue == blue &&
      other.alpha == alpha;

  @override
  int get hashCode => Object.hash(kind, red, green, blue, alpha);

  @override
  String toString() => 'ClearColor.${kind.name}($red, $green, $blue, $alpha)';
}

/// Which kind of target a [ClearColor] is for.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
@immutable
final class ClearColorKind {
  const ClearColorKind._(this.name);

  /// Float, normalised and sRGB formats.
  static const ClearColorKind float = ClearColorKind._('float');

  /// Unsigned integer formats.
  static const ClearColorKind uint = ClearColorKind._('uint');

  /// Signed integer formats.
  static const ClearColorKind sint = ClearColorKind._('sint');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<ClearColorKind> values = <ClearColorKind>[
    float,
    uint,
    sint,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static ClearColorKind? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name. Never renamed within a major.
  final String name;

  @override
  String toString() => 'ClearColorKind.$name';
}

/// The features a [PrimitiveType] needs — since 1.0.0-rc.1+2.
extension PrimitiveTypeFeatures on PrimitiveType {
  /// Throws [UnsupportedCapabilityException] when [features] lacks what
  /// this topology needs: a strip (`primitiveStrips`) or points
  /// (`pointPrimitives`). Triangle and line lists need nothing.
  ///
  /// **For a backend's `setPrimitiveType`**, so that every backend refuses
  /// the same topologies in the same words, and a topology a minor adds with
  /// its feature is refused by a backend written before it rather than
  /// assembled as something else.
  void checkFeatures(DeviceFeatures features, {required String backend}) {
    if (this == PrimitiveType.triangleStrip ||
        this == PrimitiveType.lineStrip) {
      features.require(
        DeviceFeature.primitiveStrips,
        backend: backend,
        reason: 'it assembles no strips',
      );
    } else if (this == PrimitiveType.point) {
      features.require(
        DeviceFeature.pointPrimitives,
        backend: backend,
        reason: 'it draws no points',
      );
    }
  }

  /// Whether this is a strip, where an all-ones index restarts.
  bool get isStrip =>
      this == PrimitiveType.triangleStrip || this == PrimitiveType.lineStrip;
}

/// The features an [IndexType] needs, and its restart value — since
/// 1.0.0-rc.1+2.
extension IndexTypeFeatures on IndexType {
  /// Throws [UnsupportedCapabilityException] when [features] lacks what
  /// this index width needs: 32-bit indices (`indexUint32`).
  ///
  /// **For a backend's `bindIndexBuffer` and `bindIndexData`**, for the
  /// reason [PrimitiveTypeFeatures.checkFeatures] gives.
  void checkFeatures(DeviceFeatures features, {required String backend}) {
    if (this == IndexType.int32) {
      features.require(
        DeviceFeature.indexUint32,
        backend: backend,
        reason: 'its indices are 16 bits',
      );
    }
  }

  /// The all-ones index that ends a strip and starts the next: `0xFFFF` for
  /// [IndexType.int16], `0xFFFFFFFF` for [IndexType.int32].
  int get restartIndex => this == IndexType.int16 ? 0xFFFF : 0xFFFFFFFF;
}

/// How a draw is combined with what the attachment already holds.
///
/// A value type with `==`, so a backend can cache one native object per
/// distinct state and a test can assert on the state a pass was left in — the
/// same two reasons `SamplerDescriptor` is one.
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

  /// Whether any of the four factors reads the constant
  /// `PassEncoder.setBlendColor` sets.
  ///
  /// Asked by a backend that has no constant, so it can refuse the state
  /// instead of evaluating the term as zero — which is what two of the three
  /// did for as long as nothing could set one. One place decides which factors
  /// those are, because a backend that spelled the list out itself would go on
  /// accepting a value the enum grew afterwards.
  /// Four questions rather than a list and `any`: the backend that refuses
  /// asks this from `setBlend`, which is once per mesh per pass, and a list
  /// literal built from four instance fields is an allocation on the draw path
  /// every time. [_readsConstant] keeps the one place the four are named.
  bool get usesBlendColor =>
      _readsConstant(sourceColorFactor) ||
      _readsConstant(destinationColorFactor) ||
      _readsConstant(sourceAlphaFactor) ||
      _readsConstant(destinationAlphaFactor);

  /// Whether any factor is [BlendFactor.blendAlpha] or
  /// [BlendFactor.oneMinusBlendAlpha], which read the constant's alpha for
  /// every channel — what a backend without
  /// `DeviceFeature.blendConstantAlpha` refuses. Since 1.0.0-rc.1+2.
  bool get usesBlendAlpha =>
      _readsConstantAlpha(sourceColorFactor) ||
      _readsConstantAlpha(destinationColorFactor) ||
      _readsConstantAlpha(sourceAlphaFactor) ||
      _readsConstantAlpha(destinationAlphaFactor);

  /// Whether any factor reads the fragment's second output — what a backend
  /// without `DeviceFeature.dualSourceBlending` refuses.
  bool get usesDualSource =>
      sourceColorFactor.isDualSource ||
      destinationColorFactor.isDualSource ||
      sourceAlphaFactor.isDualSource ||
      destinationAlphaFactor.isDualSource;

  /// Whether either operation is [BlendOperation.min] or
  /// [BlendOperation.max] — what a backend without
  /// `DeviceFeature.minMaxBlend` refuses.
  bool get usesMinMax =>
      extendedBlendOperations.contains(colorOperation) ||
      extendedBlendOperations.contains(alphaOperation);

  /// Throws [UnsupportedCapabilityException] when this state needs a feature
  /// [features] lacks: a factor that reads the blend constant
  /// (`blendConstant`), one that reads the constant's alpha for every channel
  /// (`blendConstantAlpha`, asked after `blendConstant`), a min or max
  /// operation (`minMaxBlend`), a factor that reads a second fragment output
  /// (`dualSourceBlending`).
  ///
  /// **For a backend's `setBlend`**, so that every backend refuses the same
  /// states in the same words, and an operation a minor adds with its
  /// feature is refused by a backend written before it rather than ignored.
  /// [backend] names the backend as a person would.
  void checkFeatures(DeviceFeatures features, {required String backend}) {
    if (usesBlendColor) {
      features.require(
        DeviceFeature.blendConstant,
        backend: backend,
        reason: 'the blend state reads the blend constant',
      );
    }
    if (usesBlendAlpha) {
      features.require(
        DeviceFeature.blendConstantAlpha,
        backend: backend,
        reason: "the blend state reads the blend constant's alpha",
      );
    }
    if (usesMinMax) {
      features.require(
        DeviceFeature.minMaxBlend,
        backend: backend,
        reason: 'the blend state names min or max',
      );
    }
    if (usesDualSource) {
      features.require(
        DeviceFeature.dualSourceBlending,
        backend: backend,
        reason: 'the blend state reads a second fragment output',
      );
    }
  }

  /// Whether one factor multiplies by the blend constant.
  static bool _readsConstant(BlendFactor factor) => switch (factor) {
    BlendFactor.blendColor ||
    BlendFactor.oneMinusBlendColor ||
    BlendFactor.blendAlpha ||
    BlendFactor.oneMinusBlendAlpha => true,
    _ => false,
  };

  /// Whether one factor multiplies by the constant's alpha alone.
  static bool _readsConstantAlpha(BlendFactor factor) =>
      factor == BlendFactor.blendAlpha ||
      factor == BlendFactor.oneMinusBlendAlpha;

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
    this.face = 0,
    this.mipLevel = 0,
    this.layer = 0,
  }) : assert(face >= 0 && face < 6, 'a texture has at most six faces'),
       assert(layer >= 0, 'a layer counts up from the first'),
       assert(mipLevel >= 0, 'a mip level counts down from the base'),
       // **Checked here rather than by each backend, because no backend was
       // checking.** The doc on [resolveTexture] said "the backend checks" and
       // named a promise nobody kept: Impeller forwards both fields to
       // flutter_gpu and asks nothing, WebGL2 reads the resolve target and
       // never looks at the store action, and the software rasteriser has no
       // multisampling to resolve. So a resolve target with `StoreAction.store`
       // beside it was three different silences — and the symptom is a
       // multisampled attachment that never reaches the texture the next pass
       // samples, which is a black or stale picture rather than an error.
       //
       // One assert in the constructor is the same shape as
       // `StencilState.narrowReference` and `readbackRegionOf`: a rule the
       // three would otherwise each have to keep, decided once above them.
       assert(
         resolveTexture == null ||
             storeAction == StoreAction.multisampleResolve ||
             storeAction == StoreAction.storeAndMultisampleResolve,
         'a ColorTarget with a resolveTexture must store through it: '
         'StoreAction.multisampleResolve, or storeAndMultisampleResolve when '
         'the multisampled texture is wanted afterwards too. With '
         'StoreAction.store the resolve never happens and whatever samples the '
         'resolve target reads what was in it before.',
       );

  /// Where the rasteriser writes. Multisampled when [resolveTexture] is set.
  final TextureHandle texture;

  /// Which face of a cube [texture] the pass draws into, in the order every
  /// backend uploads them: **+X, −X, +Y, −Y, +Z, −Z**. Zero for a 2D texture,
  /// which has only the one.
  ///
  /// This is what makes a reflection probe a *pass* rather than a readback: a
  /// probe is the scene seen from a point, and six views drawn straight into
  /// the six faces of one cube is the whole of it. The face is chosen at the
  /// attachment rather than by a viewport into an atlas — the point-light
  /// shadows do that — because a sampler's cube lookup is the reader here, and
  /// a sampler reads faces, not tiles.
  final int face;

  /// Which level of [texture]'s mip chain the pass draws into. Zero is the base.
  ///
  /// The viewport a pass starts with covers the *level*, not the base: a
  /// 64-pixel cube at level two is sixteen pixels across, and a backend reports
  /// that size for the pass. A depth attachment beside it has to be that size
  /// too, and is a plain 2D texture at its own base level.
  ///
  /// Ask `features.has(DeviceFeature.renderToMipLevel)` before asking for anything but
  /// zero. The one backend that cannot — flutter_gpu on OpenGL ES — refuses
  /// at the attachment, which is louder than drawing into the base level and
  /// leaving the chain as it was allocated.
  final int mipLevel;

  /// Which layer of an array [texture], which cube of a cube array (its
  /// faces then chosen by [face]), or which slice of a 3D texture the pass
  /// draws into. Zero for every texture that has one.
  ///
  /// Ask `DeviceFeature.renderToArrayLayer` before naming anything but zero:
  /// a backend without it throws `UnsupportedCapabilityException` from
  /// `beginRenderPass` rather than drawing into layer zero.
  final int layer;

  /// Where a multisampled [texture] is resolved to when the pass ends.
  ///
  /// Setting this means [storeAction] must be a resolving one, and the
  /// constructor above asserts it — not the backend, which is what this used to
  /// say and what none of the three did. Attachments in one pass must agree on
  /// sample count, which is the constraint that makes the scene pass drop
  /// multisampling entirely whenever the surface buffer is wanted.
  final TextureHandle? resolveTexture;

  /// [LoadAction.clear] covers the **whole attachment** however the viewport
  /// and the scissor are set. The shadow atlas depends on that: it loads, and
  /// blanks one tile by drawing inside it.
  final LoadAction loadAction;
  final StoreAction storeAction;

  /// Null clears to transparent black ([ClearColor.transparentBlack]).
  /// Linear light, not sRGB, for anything written into an HDR target; an
  /// integer target takes a [ClearColor.uint] or [ClearColor.sint].
  final ClearColor? clearValue;
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
/// Almost every pass here clears depth on entry and discards it on exit, and
/// those are the defaults. The one pass that asked for more is weighted
/// blended transparency (`R8`): its transparent draws go into targets of their
/// own, in passes after the opaque ones, and have to be tested against the
/// depth those left — so the opaque pass stores its depth and the transparent
/// passes load it. [loadAction] and [storeAction] are that request, and
/// nothing else sets them.
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
    this.loadAction = LoadAction.clear,
    this.storeAction = StoreAction.dontCare,
    this.stencilLoadAction = LoadAction.clear,
    this.stencilStoreAction = StoreAction.dontCare,
    this.stencilClearValue = 0,
    this.mipLevel = 0,
    this.layer = 0,
    this.face = 0,
    this.depthReadOnly = false,
    this.stencilReadOnly = false,
  }) : assert(face >= 0 && face < 6, 'a texture has at most six faces'),
       assert(layer >= 0, 'a layer counts up from the first');

  final TextureHandle texture;

  /// Which level of [texture] is the attachment — for a depth pyramid, or a
  /// shadow drawn into one level of a chain. Ask
  /// `DeviceFeature.renderToMipLevel` before naming anything but zero.
  final int mipLevel;

  /// Which layer of an array [texture] is the attachment — a cascaded or
  /// point-light shadow drawn layer by layer. Ask
  /// `DeviceFeature.renderToArrayLayer` before naming anything but zero.
  ///
  /// Counted as `ColorTarget.layer` counts: on a cube array it is the cube,
  /// and [face] is the face of it, so a colour and a depth attachment that
  /// name the same `layer` and `face` are the same plane.
  final int layer;

  /// Which face of a cube or cube-array [texture] is the attachment, in
  /// `ColorTarget.face`'s order. Zero for every other shape.
  final int face;

  /// The pass tests against the depth but never writes it, so the same
  /// texture may be sampled by the pass at the same time. WebGPU's
  /// `depthReadOnly`; the load and store actions are then ignored.
  final bool depthReadOnly;

  /// As [depthReadOnly], for the stencil.
  final bool stencilReadOnly;

  /// The far plane. One under this engine's `[0, 1]` depth convention; a
  /// reversed-Z backend would want zero, which is why it is a parameter.
  /// A depth from 0 to 1, unitless.
  final double clearValue;

  /// What the depth holds when the pass opens: [clearValue] everywhere, or
  /// with [LoadAction.load] what the last pass that stored it left.
  final LoadAction loadAction;

  /// Whether the depth survives the pass. [StoreAction.dontCare] lets a tiler
  /// keep it in tile memory and throw it away, which is what every pass that
  /// no later pass loads wants.
  ///
  /// **A texture another pass loads must be stored and must not be
  /// `StorageMode.deviceTransient`**: on Apple GPUs that is memoryless, and
  /// there is nothing to load.
  final StoreAction storeAction;

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
  const RenderPassDescriptor({
    required this.colors,
    this.depth,
    this.label,
    this.occlusionQuerySet,
    this.timestampWrites,
    this.viewMask,
  }) : assert(
         viewMask == null || (viewMask > 0 && viewMask <= 0xFFFFFFFF),
         'a view mask names at least one view, in 32 bits',
       );

  /// The views this pass draws at once, one bit per view: bit `i` set draws
  /// view `i` into layer `i` of every attachment, and a stage reads which
  /// view it is drawing as its view index. Null draws one view, the
  /// attachments' own [ColorTarget.layer]s, as every pass did before 1.0.
  ///
  /// `DeviceFeature.multiview` (WebGL2 with `OVR_multiview2`); a device without
  /// it refuses the pass from `beginRenderPass` with the feature named.
  /// [views] and [forView] are how a caller draws the same views one pass
  /// at a time instead, and `ViewPasses` decides between the two.
  final int? viewMask;

  /// The view indices [viewMask] names, lowest first; `[0]` without one.
  List<int> get views {
    final mask = viewMask;
    if (mask == null) return const <int>[0];
    return <int>[
      for (var i = 0; i < 32; i++)
        if (mask & (1 << i) != 0) i,
    ];
  }

  /// This pass drawing only [view], into layer [view] of each attachment and
  /// with no [viewMask]: the fallback for a device without multiview. Every
  /// attachment keeps its texture, its actions and its clear value.
  ///
  /// A view above zero needs `DeviceFeature.renderToArrayLayer`, which
  /// [checkFeatures] asks of the pass this returns, as of any other.
  RenderPassDescriptor forView(int view) {
    RangeError.checkValueInInterval(view, 0, 31, 'view');
    final depth = this.depth;
    return RenderPassDescriptor(
      colors: <ColorTarget>[
        for (final c in colors)
          ColorTarget(
            texture: c.texture,
            resolveTexture: c.resolveTexture,
            loadAction: c.loadAction,
            storeAction: c.storeAction,
            clearValue: c.clearValue,
            face: c.face,
            mipLevel: c.mipLevel,
            layer: view,
          ),
      ],
      depth: depth == null
          ? null
          : DepthTarget(
              texture: depth.texture,
              clearValue: depth.clearValue,
              loadAction: depth.loadAction,
              storeAction: depth.storeAction,
              stencilLoadAction: depth.stencilLoadAction,
              stencilStoreAction: depth.stencilStoreAction,
              stencilClearValue: depth.stencilClearValue,
              mipLevel: depth.mipLevel,
              layer: view,
              face: depth.face,
              depthReadOnly: depth.depthReadOnly,
              stencilReadOnly: depth.stencilReadOnly,
            ),
      label: label == null ? null : '$label (view $view)',
      occlusionQuerySet: occlusionQuerySet,
      timestampWrites: timestampWrites,
    );
  }

  /// The [QueryType.occlusion] set `PassEncoder.beginOcclusionQuery` writes
  /// into, or null for a pass that asks none. `DeviceFeature.occlusionQuery`.
  final QuerySet? occlusionQuerySet;

  /// Where the pass writes its start and end GPU times, or null.
  /// `DeviceFeature.timestampQuery`.
  final PassTimestampWrites? timestampWrites;

  /// What the pass is called, for a GPU debugger and for
  /// `GraphicsDevice.onGpuTimings` — `H2`. The renderer passes its frame
  /// graph node's name. A backend with nowhere to put it ignores it.
  final String? label;

  /// In shader output order. Two of them exactly once — the scene pass, which
  /// writes lit colour and the surface buffer together.
  ///
  /// A pipeline may declare more outputs than the target has attachments and
  /// the extra is discarded, which is what lets the scene shaders write the
  /// surface buffer unconditionally and this list decide whether anyone is
  /// listening. See ARCHITECTURE.md §2.
  final List<ColorTarget> colors;

  final DepthTarget? depth;

  /// Throws [UnsupportedCapabilityException] when this pass needs a feature
  /// [features] lacks: a colour or depth attachment at a layer above zero
  /// (`renderToArrayLayer`), at a mip level above zero (`renderToMipLevel`),
  /// an occlusion query set (`occlusionQuery`), timestamp writes
  /// (`timestampQuery`) or a view mask (`multiview`).
  ///
  /// **For a backend's `beginRenderPass`, beside [checkAttachmentLimit]**,
  /// so that every backend refuses the same descriptors in the same words.
  void checkFeatures(DeviceFeatures features, {required String backend}) {
    void need(bool used, DeviceFeature feature, String what) {
      if (used) features.require(feature, backend: backend, reason: what);
    }

    final depth = this.depth;
    need(
      colors.any((ColorTarget c) => c.layer > 0) || (depth?.layer ?? 0) > 0,
      DeviceFeature.renderToArrayLayer,
      'this pass draws into a layer above zero',
    );
    need(
      colors.any((ColorTarget c) => c.mipLevel > 0) ||
          (depth?.mipLevel ?? 0) > 0,
      DeviceFeature.renderToMipLevel,
      'this pass draws into a mip level above the base',
    );
    need(
      occlusionQuerySet != null,
      DeviceFeature.occlusionQuery,
      'this pass names an occlusion query set',
    );
    need(
      timestampWrites != null,
      DeviceFeature.timestampQuery,
      'this pass names timestamp writes',
    );
    // 1.0: a multiview pass on a device without it is refused here, in the
    // same words on every backend; `ViewPasses` draws the views instead.
    need(
      viewMask != null,
      DeviceFeature.multiview,
      'this pass names a view mask; draw its views one pass each through '
      'ViewPasses',
    );
  }

  /// Throws a [DeviceResourceException] (operation `beginRenderPass`) when
  /// this opens more colour attachments than [limit] allows — `gfx-50n`.
  ///
  /// **Every backend calls this on the way into `beginRenderPass`, and the
  /// reason it is shared is that the answer has to be the same everywhere.**
  /// A refusal that one backend made and another did not would be worse than
  /// no refusal at all: an application would be written against whichever
  /// device the author had, and the one that aborts would be the one the
  /// author did not have.
  ///
  /// [limit] is `GraphicsDevice.limits.maxColorAttachments`. Passed rather
  /// than taken from a device, because this file may not know what a device
  /// is — the descriptor is what a caller builds before it has opened
  /// anything. A limit is not a feature, so the refusal is the one a device
  /// gives for a request it has the feature for and still cannot honour.
  void checkAttachmentLimit(int limit, {required String backend}) {
    if (colors.length <= limit) return;
    throw DeviceResourceException(
      operation: 'beginRenderPass',
      backend: backend,
      reason:
          'it opens at most $limit colour '
          '${limit == 1 ? "attachment" : "attachments"} and this pass asks '
          'for ${colors.length}. Ask `GraphicsDevice.limits.'
          'maxColorAttachments` before building a pass that wants more than '
          'one: this throw is the whole point of the number, because the '
          'alternative on at least one backend is that the process aborts.',
    );
  }
}
