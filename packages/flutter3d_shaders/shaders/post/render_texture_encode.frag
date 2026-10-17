#version 460 core

// `P4`: what a `RenderTexture`'s camera saw, turned from linear light into
// the sRGB bytes a material's map is read as.
//
// **Encoded because every map is decoded.** A material reads its base colour
// and its emission through `SrgbToLinear`, so a texture holding linear light
// would be darkened a second time in every midtone by whatever showed it. In
// eight bits rather than half floats for the same reason: it is a picture,
// sampled like any other picture.
//
// **Exposure, and no tone map.** The texture is drawn into a frame that is
// tone mapped itself, so a curve applied here would be applied twice; what
// is above one after the camera's own exposure is clipped, as a screen
// clips it.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D source_texture;

uniform RenderTextureInfo {
  /// x: the exposure the light is multiplied by before it is clipped. y: one
  /// where the backend's first row is the bottom of a picture it draws. zw
  /// unused.
  vec4 params;
}
encode_info;

vec3 LinearToSrgb(vec3 linear) {
  return mix(
      linear * 12.92,
      1.055 * pow(max(linear, vec3(0.0)), vec3(1.0 / 2.4)) - vec3(0.055),
      step(vec3(0.0031308), linear));
}

void main() {
  // **Written with the top of the picture in the first row, on every
  // backend**, which is how a picture loaded from a file is uploaded and so
  // how every material reads its maps. WebGL2 draws a picture with its
  // bottom in the first row, so there the rows are turned over on the way
  // through; a copy that kept them would show a monitor upside down in the
  // browser alone.
  vec2 uv = v_uv;
  if (encode_info.params.y > 0.5) uv.y = 1.0 - uv.y;
  vec3 light = textureLod(source_texture, uv, 0.0).rgb * encode_info.params.x;
  frag_color = vec4(LinearToSrgb(clamp(light, vec3(0.0), vec3(1.0))), 1.0);
}
