/// Attaching a [TextureHandle] to whichever framebuffer target is bound.
///
/// One function rather than a method on [WebGlDevice], because both
/// [WebGlDevice] (presenting, reading pixels back) and [WebGlEncoder] (opening
/// and resolving a pass) need it, and neither owns the other's `WebGLRenderingContext`
/// reference beyond the one it was handed — there is nothing private here for
/// a method to reach that a parameter does not already carry.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

import 'webgl_types.dart';

/// Attaches [handle] as [attachment] of the framebuffer bound to [target].
///
/// A texture attaches as a texture; a renderbuffer — a multisampled or
/// `deviceTransient` target, see [WebGlTexture] — attaches as a renderbuffer.
/// Which of the two [handle] is was decided once, when it was created, and
/// this is the one place both paths meet.
///
/// [face] picks the face of a cube and [mipLevel] the level, the way
/// `ColorTarget` names them. The six face targets are consecutive constants
/// from `TEXTURE_CUBE_MAP_POSITIVE_X` in the order +X, −X, +Y, −Y, +Z, −Z —
/// the same order the upload walks them — so a face is an addition rather than
/// a table. A 2D texture ignores [face], as the interface says it may.
///
/// [layer] picks the layer of a 2D array or the slice of a 3D texture —
/// `framebufferTextureLayer`, which is how WebGL2 attaches either. A layer
/// past what the texture holds throws an [ArgumentError] here rather than
/// leaving the framebuffer incomplete, and so does a layer above zero on a
/// texture that has no layers.
void attachToFramebuffer(
  web.WebGL2RenderingContext gl,
  int target,
  int attachment,
  TextureHandle handle, {
  int face = 0,
  int mipLevel = 0,
  int layer = 0,
}) {
  final backend = handle.backend as WebGlTexture;
  final layered =
      backend.target == web.WebGL2RenderingContext.TEXTURE_2D_ARRAY ||
      backend.target == web.WebGL2RenderingContext.TEXTURE_3D;
  final layers = backend.target == web.WebGL2RenderingContext.TEXTURE_3D
      ? (handle.depthOrArrayLayers >> mipLevel).clamp(1, 1 << 30)
      : handle.depthOrArrayLayers;
  if (layer < 0 || (layer > 0 && !layered) || layer >= layers) {
    throw ArgumentError.value(
      layer,
      'layer',
      layered
          ? 'is past the $layers layer(s) of this texture at level $mipLevel'
          : 'names a layer of a texture that has none',
    );
  }
  if (backend.texture != null && layered) {
    gl.framebufferTextureLayer(
      target,
      attachment,
      backend.texture,
      mipLevel,
      layer,
    );
  } else if (backend.texture != null) {
    gl.framebufferTexture2D(
      target,
      attachment,
      backend.target == web.WebGLRenderingContext.TEXTURE_CUBE_MAP
          ? web.WebGLRenderingContext.TEXTURE_CUBE_MAP_POSITIVE_X + face
          : web.WebGLRenderingContext.TEXTURE_2D,
      backend.texture,
      mipLevel,
    );
  } else {
    gl.framebufferRenderbuffer(
      target,
      attachment,
      web.WebGLRenderingContext.RENDERBUFFER,
      backend.renderbuffer,
    );
  }
}
