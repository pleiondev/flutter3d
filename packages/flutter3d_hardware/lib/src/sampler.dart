import 'formats.dart';

/// How a texture is sampled.
///
/// The engine's counterpart to flutter_gpu's `SamplerOptions`, and it exists
/// for the same reason the enums beside it do: it is reachable from the public
/// API — five fields on `Material` and the return of `samplerOptionsFor` — so a
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
final class SamplerOptions {
  const SamplerOptions({
    this.minFilter = MinMagFilter.nearest,
    this.magFilter = MinMagFilter.nearest,
    this.mipFilter = MipFilter.nearest,
    this.widthAddressMode = SamplerAddressMode.clampToEdge,
    this.heightAddressMode = SamplerAddressMode.clampToEdge,
    this.anisotropy = 1,
  }) : assert(anisotropy >= 1, 'anisotropy is a count of taps, one or more'),
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

  /// This sampler with its [anisotropy] replaced.
  ///
  /// A copy rather than a setter because the class is a value, and a
  /// method rather than a `copyWith` because this is the one field a caller
  /// ever decides at run time — the filters and wrap modes are a property of
  /// the asset, the tap count a property of the device it lands on.
  SamplerOptions withAnisotropy(int anisotropy) => SamplerOptions(
    minFilter: minFilter,
    magFilter: magFilter,
    mipFilter: mipFilter,
    widthAddressMode: widthAddressMode,
    heightAddressMode: heightAddressMode,
    anisotropy: anisotropy,
  );

  /// Smooth and tiling: the default for material textures.
  static const SamplerOptions linearRepeat = SamplerOptions(
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
  static const SamplerOptions trilinearRepeat = SamplerOptions(
    minFilter: MinMagFilter.linear,
    magFilter: MinMagFilter.linear,
    mipFilter: MipFilter.linear,
    widthAddressMode: SamplerAddressMode.repeat,
    heightAddressMode: SamplerAddressMode.repeat,
  );

  /// Smooth and clamped: the default for sampling a full-screen buffer, where
  /// wrapping would fold the far edge onto the near one.
  static const SamplerOptions linearClamp = SamplerOptions(
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
  static const SamplerOptions nearestClamp = SamplerOptions(
    minFilter: MinMagFilter.nearest,
    magFilter: MinMagFilter.nearest,
    widthAddressMode: SamplerAddressMode.clampToEdge,
    heightAddressMode: SamplerAddressMode.clampToEdge,
  );

  @override
  bool operator ==(Object other) =>
      other is SamplerOptions &&
      other.minFilter == minFilter &&
      other.magFilter == magFilter &&
      other.mipFilter == mipFilter &&
      other.widthAddressMode == widthAddressMode &&
      other.heightAddressMode == heightAddressMode &&
      other.anisotropy == anisotropy;

  @override
  int get hashCode => Object.hash(
    minFilter,
    magFilter,
    mipFilter,
    widthAddressMode,
    heightAddressMode,
    anisotropy,
  );

  @override
  String toString() =>
      'SamplerOptions(min: ${minFilter.name}, '
      'mag: ${magFilter.name}, mip: ${mipFilter.name}, '
      'u: ${widthAddressMode.name}, v: ${heightAddressMode.name}, '
      'anisotropy: $anisotropy)';
}
