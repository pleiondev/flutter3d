/// Where each level of the copy of the scene sits in its one texture — `M3`.
library;

import 'dart:math' as math;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// The copy of the scene the transmissive draws read, as a chain of levels
/// laid side by side in one texture.
///
/// **One texture rather than a mip chain, and the reason is the interface.**
/// A 2D render target has no levels here: `RenderTargetSpec` carries none and
/// only a cube is made with a chain (`createCubeRenderTarget`). And a set of
/// textures, one per level the way bloom keeps its pyramid, would cost the
/// lit stage a sampler a level where it has one left under WebGL2's sixteen.
/// So the base sits at the left at the scene's size, and every level after
/// it — half the one before, a pixel at the least — is stacked down a column
/// to its right, which fits: the column is half the scene wide, and the
/// levels in it add up to less than its height. Drawing into a rectangle of
/// level zero is something every device does, so there is no device that
/// gets a single level instead.
///
/// The lit stage blends two levels itself, clamped half a texel inside each
/// rectangle so a bilinear tap never reaches the level beside it — see
/// `SceneColourAt` in `lib/pbr.glsl`.
final class SceneColourChain {
  /// The chain for a scene [width] by [height] texels.
  SceneColourChain(this.width, this.height)
    : assert(width > 0 && height > 0),
      levels = 1 + math.min(maxLevels - 1, _floorLog2(math.min(width, height)));

  /// The most levels a chain has, its base included: five halvings, a
  /// thirty-second of the scene, which is as blurred as the roughest glass
  /// reads it. Also the length of `LayerInfo.scene_levels`.
  static const int maxLevels = 6;

  /// The scene's size, and the base level's.
  final int width;
  final int height;

  /// How many levels this chain has, its base included: fewer than
  /// [maxLevels] only for a scene too small to halve that often.
  final int levels;

  /// The texture's size: the base, and the column of the rest beside it.
  int get atlasWidth => width + math.max(1, width >> 1);
  int get atlasHeight => height;

  /// Where [level] sits in the texture, counted from its top left, as every
  /// rectangle in this engine is.
  ScreenRect rect(int level) {
    assert(level >= 0 && level < levels);
    if (level == 0) return ScreenRect(width: width, height: height);
    var y = 0;
    for (var k = 1; k < level; k++) {
      y += math.max(1, height >> k);
    }
    return ScreenRect(
      x: width,
      y: y,
      width: math.max(1, width >> level),
      height: math.max(1, height >> level),
    );
  }

  /// The bilinear taps along each side that make one texel of [level] the
  /// mean of the scene's texels under it: one for the base, which is a
  /// copy, and half the level's scale after it.
  int taps(int level) => level == 0 ? 1 : 1 << (level - 1);

  static int _floorLog2(int n) => n < 1 ? 0 : n.bitLength - 1;
}
