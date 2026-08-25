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
  });

  final MinMagFilter minFilter;
  final MinMagFilter magFilter;

  /// Which levels of a mip chain are blended. See [MipFilter].
  ///
  /// Ignored by a texture with one level, which is every texture in this engine
  /// except the ones built with a chain on purpose.
  final MipFilter mipFilter;

  final SamplerAddressMode widthAddressMode;
  final SamplerAddressMode heightAddressMode;

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
      other.heightAddressMode == heightAddressMode;

  @override
  int get hashCode => Object.hash(
        minFilter,
        magFilter,
        mipFilter,
        widthAddressMode,
        heightAddressMode,
      );

  @override
  String toString() => 'SamplerOptions(min: ${minFilter.name}, '
      'mag: ${magFilter.name}, mip: ${mipFilter.name}, '
      'u: ${widthAddressMode.name}, v: ${heightAddressMode.name})';
}
