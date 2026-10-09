import 'package:flutter3d_hardware/flutter3d_hardware.dart' show TextureHandle;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;
import 'package:vector_math/vector_math.dart';

import 'scene.dart';
import 'scene_node.dart';

/// A picture projected onto whatever geometry stands inside a box — `P3`.
///
/// **The box is this node's unit cube**, from minus a half to a half on every
/// axis, so its position, rotation and scale are the decal's: scale x and z
/// for the size of the picture and y for how deep it reaches. The picture is
/// stamped down the box's y axis and faces up it, so a decal with no rotation
/// lies on a floor; to put one on a wall, rotate the box until its up points
/// out of the wall.
///
/// **It paints the surface's colour, not the light on it.** The renderer
/// reads back the light each pixel was lit by and lays [color] (times
/// [texture]) under that same light, so a decal in a shadow is in the shadow.
/// It does not change a normal or a roughness; see `decal.frag` for what the
/// light that is read back cannot say.
///
/// Drawn only while `RenderSettings.decals` is on, which it is not by
/// default, and only on a device that opens three colour attachments: the
/// renderer needs the scene's surface and albedo buffers. Reading those turns
/// multisampling off for the frame.
final class DecalNode extends SceneNode {
  DecalNode({
    this.texture,
    this.color = LinearColor.white,
    this.emissive = LinearColor.black,
    Vector4? region,
    this.order = 0,
    this.angleLimit = 1.3,
    this.angleFade = 0.2,
    this.depthFade = 0.1,
    super.name,
  }) : region = region ?? Vector4(0.0, 0.0, 1.0, 1.0),
       assert(angleLimit >= 0.0, 'an angle limit is an angle'),
       assert(angleFade >= 0.0, 'a fade is a width'),
       assert(depthFade >= 0.0 && depthFade <= 1.0, 'a share of the box');

  /// The picture, sRGB-encoded as a base colour map is. Null paints [color]
  /// alone, which is what a stain or a scorch with no detail needs.
  ///
  /// Mipmapped if it was uploaded with a chain: the level is chosen from how
  /// much of the picture one pixel covers, as a material's would be.
  TextureHandle? texture;

  /// The tint, linear like `RenderMaterial.baseColor`, and in its alpha the
  /// opacity the picture's own alpha is multiplied by.
  LinearColor color;

  /// Light the painted colour gives off, as a multiple of it. Zero, the
  /// default, emits nothing; a glowing sign wants a few.
  LinearColor emissive;

  /// The part of [texture] this decal shows: x and y where it starts in
  /// texture coordinates, z and w how far it reaches. The whole picture by
  /// default; a sheet of decals in one atlas names its cell.
  Vector4 region;

  /// Which decal is painted over which where two overlap: higher over lower,
  /// and attachment order between equals.
  int order;

  /// The angle, in radians from the box's up, past which a surface takes
  /// none of the decal. Seventy-five degrees by default, so a decal on a
  /// floor stays off the walls around it rather than smearing down them.
  double angleLimit;

  /// How many radians inside [angleLimit] the decal fades in over, so the
  /// edge where a surface turns away is soft rather than cut.
  double angleFade;

  /// The share of the box's half height, from its top and bottom faces, the
  /// decal fades out over, so geometry that only just enters the box is not
  /// painted with a hard edge.
  double depthFade;

  @override
  void onAttachedToScene(Scene scene) => scene.registerDecal(this);

  @override
  void onDetachedFromScene(Scene scene) => scene.unregisterDecal(this);
}
