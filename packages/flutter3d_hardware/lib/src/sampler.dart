import 'formats.dart';

/// The colour a sampler clamping to its border returns outside the texture.
///
/// The three every API that has a border agrees on. WebGPU and WebGL2 have
/// none — see `DeviceFeature.samplerBorderColor`.
enum SamplerBorderColor { transparentBlack, opaqueBlack, opaqueWhite }

/// How a texture is sampled.
///
/// The engine's counterpart to flutter_gpu's `SamplerDescriptor`, and it exists
/// for the same reason the enums beside it do: it is reachable from the public
/// API — five fields on `RenderMaterial` and the return of `samplerOptionsFor` — so a
/// consumer that wanted to describe a sampler had to name a flutter_gpu type.
///
/// Two deliberate differences from the type underneath, both because this one
/// is a *description* rather than a handle:
///
///  * It is immutable and `const`, so [linearRepeat] and [linearClamp] can be
///    compile-time constants rather than lazily built statics.
///  * It defines `==` and `hashCode`, so the translation layer can cache the
///    flutter_gpu object per distinct description instead of allocating one per
///    bind. Nothing in the engine mutates a sampler after building it, so
///    nothing loses by this.
///
/// The field set and the defaults are flutter_gpu's, unchanged.
final class SamplerDescriptor {
  const SamplerDescriptor({
    this.minFilter = MinMagFilter.nearest,
    this.magFilter = MinMagFilter.nearest,
    this.mipFilter = MipFilter.nearest,
    this.widthAddressMode = SamplerAddressMode.clampToEdge,
    this.heightAddressMode = SamplerAddressMode.clampToEdge,
    this.anisotropy = 1,
    this.depthAddressMode = SamplerAddressMode.clampToEdge,
    this.compare,
    this.lodMinClamp = 0,
    this.lodMaxClamp = 32,
    this.borderColor,
  }) : assert(anisotropy >= 1, 'anisotropy is a count of taps, one or more'),
       assert(
         lodMinClamp >= 0 && lodMaxClamp >= lodMinClamp,
         'a level-of-detail clamp is a range from zero up',
       ),
       assert(
         anisotropy == 1 ||
             (minFilter == MinMagFilter.linear &&
                 magFilter == MinMagFilter.linear &&
                 mipFilter == MipFilter.linear),
         'anisotropy above one needs linear min, mag and mip filters: it is '
         'taps across the mip chain, and there is nothing to spread over a '
         'nearest lookup',
       );

  final MinMagFilter minFilter;
  final MinMagFilter magFilter;

  /// Which levels of a mip chain are blended. See [MipFilter].
  ///
  /// Ignored by a texture with one level, which is every texture in this engine
  /// except the ones built with a chain on purpose.
  final MipFilter mipFilter;

  final SamplerAddressMode widthAddressMode;
  final SamplerAddressMode heightAddressMode;

  /// How many taps a sample may spread along the direction a texture is
  /// foreshortened in. One — the default — is isotropic filtering, which is
  /// every sampler the engine bound before this field existed.
  ///
  /// **What it is for.** A floor seen at a grazing angle covers a footprint
  /// that is a few texels wide and many texels long; a trilinear sampler
  /// picks one level for the whole footprint, and the level that stops the
  /// long axis aliasing blurs the short one. Anisotropic filtering takes
  /// several taps along the long axis from a sharper level instead, and the
  /// checkerboard on the far side of a room stays a checkerboard.
  ///
  /// **It needs the chain and the filters that blend it.** The taps are taken
  /// across mip levels, so above one this requires [minFilter], [magFilter]
  /// and [mipFilter] all linear — flutter_gpu refuses the bind otherwise, and
  /// the constructor asserts it here so the refusal arrives with a Dart stack
  /// at the place the sampler was built. A texture with no chain gains nothing
  /// from it, and a device that has none clamps it to one.
  ///
  /// Values above `GraphicsDevice.maxAnisotropy` are clamped by the backend,
  /// which is why asking for sixteen everywhere is safe and why nothing here
  /// has to know the device. Sixteen is what most hardware offers; eight is
  /// what the bridge asks for, being where the picture stops improving.
  final int anisotropy;

  /// What sampling outside 0..1 along a 3D texture's depth does. Ignored by
  /// every other shape. The default is the pre-0.9 behaviour, so no existing
  /// sampler changes.
  final SamplerAddressMode depthAddressMode;

  /// When set, this is a comparison sampler: a sample of a depth texture
  /// answers how much of the footprint passes `reference <compare> stored`,
  /// filtered — hardware percentage-closer filtering. Null for an ordinary
  /// sampler. Ask `DeviceFeature.samplerCompare`; a backend without it
  /// refuses the bind.
  final CompareFunction? compare;

  /// The finest mip level the sampler may read, as a level of detail.
  /// `DeviceFeature.samplerLodClamp`; the defaults clamp nothing. In mip
  /// levels, unitless: zero is the full-size image.
  final double lodMinClamp;

  /// The coarsest mip level the sampler may read. Thirty-two clamps nothing.
  /// In mip levels, unitless, as [lodMinClamp].
  final double lodMaxClamp;

  /// When set, every axis whose address mode is
  /// [SamplerAddressMode.clampToEdge] clamps to this colour instead of the
  /// edge texel. Null for the edge. A field rather than a fourth
  /// [SamplerAddressMode] because that enum mirrors flutter_gpu, which has no
  /// border. Ask `DeviceFeature.samplerBorderColor`; a backend without it
  /// refuses the bind.
  final SamplerBorderColor? borderColor;

  /// Whether this needs [DeviceFeature]s beyond the pre-0.9 sampler, so a
  /// backend can check once per bind: a comparison, a level clamp, a border.
  bool get usesExtendedState =>
      compare != null ||
      lodMinClamp != 0 ||
      lodMaxClamp != 32 ||
      borderColor != null;

  /// This sampler with its [anisotropy] replaced.
  ///
  /// A copy rather than a setter because the class is a value, and a
  /// method rather than a `copyWith` because this is the one field a caller
  /// ever decides at run time — the filters and wrap modes are a property of
  /// the asset, the tap count a property of the device it lands on.
  SamplerDescriptor withAnisotropy(int anisotropy) => SamplerDescriptor(
    minFilter: minFilter,
    magFilter: magFilter,
    mipFilter: mipFilter,
    widthAddressMode: widthAddressMode,
    heightAddressMode: heightAddressMode,
    anisotropy: anisotropy,
    depthAddressMode: depthAddressMode,
    compare: compare,
    lodMinClamp: lodMinClamp,
    lodMaxClamp: lodMaxClamp,
    borderColor: borderColor,
  );

  /// Smooth and tiling: the default for material textures.
  static const SamplerDescriptor linearRepeat = SamplerDescriptor(
    minFilter: MinMagFilter.linear,
    magFilter: MinMagFilter.linear,
    widthAddressMode: SamplerAddressMode.repeat,
    heightAddressMode: SamplerAddressMode.repeat,
  );

  /// Smooth and tiling, and blended between mip levels.
  ///
  /// **A second constant rather than a change to [linearRepeat]**, which is the
  /// default for every material texture in the engine. Turning the mip filter
  /// on there would have moved every textured golden — and would have moved
  /// them for textures that have no chain to blend, where the setting cannot
  /// help and can only cost. Something that wants trilinear filtering asks for
  /// it and supplies the chain to go with it.
  static const SamplerDescriptor trilinearRepeat = SamplerDescriptor(
    minFilter: MinMagFilter.linear,
    magFilter: MinMagFilter.linear,
    mipFilter: MipFilter.linear,
    widthAddressMode: SamplerAddressMode.repeat,
    heightAddressMode: SamplerAddressMode.repeat,
  );

  /// Smooth and clamped: the default for sampling a full-screen buffer, where
  /// wrapping would fold the far edge onto the near one.
  static const SamplerDescriptor linearClamp = SamplerDescriptor(
    minFilter: MinMagFilter.linear,
    magFilter: MinMagFilter.linear,
    widthAddressMode: SamplerAddressMode.clampToEdge,
    heightAddressMode: SamplerAddressMode.clampToEdge,
  );

  /// Unfiltered and clamped: for a buffer whose texels are *data* rather than
  /// colour.
  ///
  /// The surface buffer is the case this exists for. Its rg is an octahedral
  /// normal and its alpha is window depth, and the average of two of either is
  /// not a value of that kind — the average of two normals across a silhouette
  /// encodes no direction, and the average of a foreground depth and the
  /// cleared background is a depth at which nothing stands. It is the same
  /// argument that turns MSAA off for any pass that writes this buffer, applied
  /// to the read side, and skipping it draws a dark rim around every silhouette
  /// in the frame.
  static const SamplerDescriptor nearestClamp = SamplerDescriptor(
    minFilter: MinMagFilter.nearest,
    magFilter: MinMagFilter.nearest,
    widthAddressMode: SamplerAddressMode.clampToEdge,
    heightAddressMode: SamplerAddressMode.clampToEdge,
  );

  @override
  bool operator ==(Object other) =>
      other is SamplerDescriptor &&
      other.minFilter == minFilter &&
      other.magFilter == magFilter &&
      other.mipFilter == mipFilter &&
      other.widthAddressMode == widthAddressMode &&
      other.heightAddressMode == heightAddressMode &&
      other.anisotropy == anisotropy &&
      other.depthAddressMode == depthAddressMode &&
      other.compare == compare &&
      other.lodMinClamp == lodMinClamp &&
      other.lodMaxClamp == lodMaxClamp &&
      other.borderColor == borderColor;

  @override
  int get hashCode => Object.hash(
    minFilter,
    magFilter,
    mipFilter,
    widthAddressMode,
    heightAddressMode,
    anisotropy,
    depthAddressMode,
    compare,
    lodMinClamp,
    lodMaxClamp,
    borderColor,
  );

  // The pre-0.9 fields always, the rest only when set: a trace or a golden
  // message that printed a sampler before 0.9 prints it the same way now.
  @override
  String toString() =>
      'SamplerOptions(min: ${minFilter.name}, '
      'mag: ${magFilter.name}, mip: ${mipFilter.name}, '
      'u: ${widthAddressMode.name}, v: ${heightAddressMode.name}, '
      'anisotropy: $anisotropy'
      '${depthAddressMode == SamplerAddressMode.clampToEdge ? '' : ', w: ${depthAddressMode.name}'}'
      '${compare == null ? '' : ', compare: ${compare!.name}'}'
      '${lodMinClamp == 0 && lodMaxClamp == 32 ? '' : ', lod: $lodMinClamp..$lodMaxClamp'}'
      '${borderColor == null ? '' : ', border: ${borderColor!.name}'})';
}
