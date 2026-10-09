/// The numbers `.f3d` writes for the engine's enums, and back.
///
/// A file stores a code, never a Dart enum's `.index`: reordering or adding a
/// case in a major must not change what an existing file means. Each table
/// below is the code a `.f3d` written since version 1 carries; the codes are
/// what the ordinals happened to be when the format was frozen, so no file
/// changed when the tables replaced them.
///
/// The writers are exhaustive `switch`es, so a new enum case does not compile
/// until it is given a code here. The readers answer null for a code this
/// build does not know, and each caller says what that means for its record.
///
/// The structure rule `.f3d writes codes, not enum ordinals` keeps `.index`
/// and `values[` out of the format's code.
library;

import '../animation/animation_track.dart';
import '../surface_material.dart';

/// `material.alphaMode`.
int alphaModeCode(SurfaceAlphaMode mode) => switch (mode) {
  SurfaceAlphaMode.opaque => 0,
  SurfaceAlphaMode.mask => 1,
  SurfaceAlphaMode.blend => 2,
};

/// The [SurfaceAlphaMode] for [code], or null for a code this build lacks.
SurfaceAlphaMode? alphaModeOf(int code) => switch (code) {
  0 => SurfaceAlphaMode.opaque,
  1 => SurfaceAlphaMode.mask,
  2 => SurfaceAlphaMode.blend,
  _ => null,
};

/// A sampler's `wrapS`/`wrapT`, two bits each in `F3dSamplingFlags`.
int textureWrapCode(TextureWrap wrap) => switch (wrap) {
  TextureWrap.repeat => 0,
  TextureWrap.clampToEdge => 1,
  TextureWrap.mirroredRepeat => 2,
};

/// The [TextureWrap] for [code], or null for a code this build lacks.
TextureWrap? textureWrapOf(int code) => switch (code) {
  0 => TextureWrap.repeat,
  1 => TextureWrap.clampToEdge,
  2 => TextureWrap.mirroredRepeat,
  _ => null,
};

/// A track's `path`.
int animationPathCode(AnimationPath path) => switch (path) {
  AnimationPath.translation => 0,
  AnimationPath.rotation => 1,
  AnimationPath.scale => 2,
  AnimationPath.weights => 3,
  AnimationPath.pointer => 4,
};

/// The [AnimationPath] for [code], or null for a code this build lacks.
AnimationPath? animationPathOf(int code) => switch (code) {
  0 => AnimationPath.translation,
  1 => AnimationPath.rotation,
  2 => AnimationPath.scale,
  3 => AnimationPath.weights,
  4 => AnimationPath.pointer,
  _ => null,
};

/// A track's `interpolation`.
int interpolationCode(AnimationInterpolation interpolation) =>
    switch (interpolation) {
      AnimationInterpolation.step => 0,
      AnimationInterpolation.linear => 1,
      AnimationInterpolation.cubicSpline => 2,
    };

/// The [AnimationInterpolation] for [code], or null for a code this build
/// lacks.
AnimationInterpolation? interpolationOf(int code) => switch (code) {
  0 => AnimationInterpolation.step,
  1 => AnimationInterpolation.linear,
  2 => AnimationInterpolation.cubicSpline,
  _ => null,
};
