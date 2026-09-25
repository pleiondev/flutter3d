// Metal-rough physically based shading: Cook-Torrance specular with the GGX
// distribution, height-correlated Smith visibility and a Schlick Fresnel.
//
// **The body of two stages.** `lighting/pbr.frag` is this and nothing else;
// `lighting/pbr_layered.frag` defines `F3D_LAYERED` first and gets the glTF
// layers on top — `M1`. Everything under `#ifdef F3D_LAYERED` is the layered
// stage's alone, and everything under its `#else` is what plain metal-rough
// always was, kept as it was so that stage compiles to what it compiled to.
// Formulations follow Filament, which is also what the glTF spec describes, so
// imported glTF materials will land on the same look.
//
// Image-based lighting is here when a scene supplies an environment, and the
// flat hemispheric ambient stands in when it does not. `frame_params.w` carries
// the number of levels in the environment cube and is zero when there is none —
// the slot that block reserved for exactly this kind of frame-wide parameter.
//
// **The environment sampler is always bound**, to a one-texel cube when a scene
// has no environment. A sampler a shader declares and nobody binds is a native
// crash on Metal rather than a black texture; the same rule keeps the sky's
// cube out of `sky.frag` and a white texel under the composite's occlusion.
// `L7`: rectangle lights integrate the GGX lobe; see `lib/ltc.glsl`.
#define F3D_LTC
#ifndef PBR_GLSL_
#define PBR_GLSL_

// `C8`: the layered stage reads each map through its own transform — see
// `MapUv` in `lib/surface.glsl`, and the definitions under `LayerInfo` below.
#ifdef F3D_LAYERED
#define F3D_TEXTURE_TRANSFORM
#endif

#include <lib/material_maps.glsl>
#include <lib/shadow.glsl>

#ifdef F3D_LAYERED
/// What a layered material adds to metal-rough — `M1`. A block of its own
/// rather than members appended to `FragInfo`: six stages share that block and
/// none of the other five reads a layer.
uniform LayerInfo {
  /// rgb: `KHR_materials_specular`'s colour, linear. w: its strength.
  vec4 specular;

  /// x: the clear coat, y: its perceptual roughness, z: the index of
  /// refraction, w: unused.
  vec4 coat;

  /// rgb: `KHR_materials_sheen`'s colour, linear. w: its roughness — `M2`.
  vec4 sheen;

  /// x: `KHR_materials_anisotropy`'s strength, y and z: the cosine and sine
  /// of its rotation from the tangent. w: unused.
  vec4 anisotropy;

  /// x: `KHR_materials_transmission`, y: the volume's thickness, z: its
  /// attenuation distance, nought for a medium that takes nothing away, w:
  /// `KHR_materials_dispersion` — `M3`.
  vec4 transmission;

  /// rgb: the volume's attenuation colour, linear. w: unused.
  vec4 attenuation;

  /// x: `KHR_materials_iridescence`, y: the film's index of refraction, z:
  /// its thickness in nanometres. w: unused.
  vec4 iridescence;

  /// `KHR_texture_transform` per map — `C8`: two rows of a 2×3 matrix each,
  /// the map's coordinate being `(dot(row0.xyz, uvw), dot(row1.xyz, uvw))`
  /// with `uvw = (u, v, 1)`, in the order `kMapBaseColor` and the rest count.
  /// The identity for a map that names none, which reads the coordinate
  /// unchanged to the bit: one times `u`, plus nought twice.
  ///
  /// **Here and not baked into the vertices**, which is what an atlas export
  /// gets: one set of coordinates can carry one transform, and this is the
  /// material whose maps disagree, or whose offset a clip moves.
  vec4 uv_transform[10];

  /// The copy of the scene behind the transmissive draws — `M3`. x: how many
  /// levels the copy has, its base included, and nought outside the pass
  /// that draws them, where the environment stands in as it always did. y,
  /// z: one over the copy's width and height in texels. w: unused.
  vec4 scene_colour;

  /// Where this view sits in the copy's base level, in its texture
  /// coordinates: xy the corner, zw the size.
  vec4 scene_viewport;

  /// Each level's rectangle in the copy, in its texture coordinates: xy the
  /// corner, zw the size. The levels share one texture side by side — see
  /// `SceneColourChain`.
  vec4 scene_levels[6];

  /// The view-projection the draw was made with, turned to the rows of the
  /// framebuffer as every screen-space pass turns it.
  mat4 scene_view_projection;
}
layer_info;

vec2 MapUv(int slot) {
  vec3 uvw = vec3(v_texcoord, 1.0);
  return vec2(dot(layer_info.uv_transform[slot * 2].xyz, uvw),
              dot(layer_info.uv_transform[slot * 2 + 1].xyz, uvw));
}

vec4 MapMatrix(int slot) {
  vec4 u = layer_info.uv_transform[slot * 2];
  vec4 v = layer_info.uv_transform[slot * 2 + 1];
  return vec4(u.x, u.y, v.x, v.y);
}

/// The coat map: r the clear coat, g its roughness, b the transmission and a
/// the thickness, each multiplying its factor — `M3` reads b and a. White when a
/// material has none. One texture where glTF gives up to four, because the
/// lit stages have two samplers left under WebGL2's sixteen.
uniform sampler2D coat_texture;

/// The sheen map — `M2`: rgb the sheen colour, sRGB as authored, and a its
/// roughness, each multiplying its factor. White when a material has none.
uniform sampler2D sheen_texture;

/// The scene as it stood before the transmissive draws, every level of it in
/// one texture — `M3`. Black, and never read, outside the pass that draws
/// them. The stage's sixteenth sampler, and the last WebGL2 promises.
uniform sampler2D scene_colour_texture;

/// The layers at this fragment, resolved once by [ReadLayers] and read by
/// every light: the dielectric's reflectance head-on and at grazing, and the
/// coat — how much, how rough, which way it faces, and what it leaves of what
/// is under it.
vec3 g_f0_dielectric = vec3(0.04);
float g_f90 = 1.0;
float g_coat = 0.0;
float g_coat_roughness = 0.02;
vec3 g_coat_n = vec3(0.0, 0.0, 1.0);
float g_coat_n_dot_v = 1.0;
float g_coat_through = 1.0;

/// The sheen — `M2`: its colour and roughness, and what its albedo leaves of
/// the layer beneath. And the anisotropy: how strong, and the frame the
/// highlight stretches along, on the normal the maps leave.
vec3 g_sheen = vec3(0.0);
float g_sheen_roughness = 0.07;
float g_sheen_albedo = 0.0;
float g_sheen_scale = 1.0;
float g_aniso = 0.0;
vec3 g_aniso_t = vec3(1.0, 0.0, 0.0);
vec3 g_aniso_b = vec3(0.0, 1.0, 0.0);

/// The transmission — `M3`: how much passes through, how thick the medium
/// is, and what of each colour survives that thickness. And the thin film:
/// how much, and the Fresnel its interference gives at this view.
float g_transmission = 0.0;
float g_thickness = 0.0;
vec3 g_transmittance = vec3(1.0);
float g_iridescence = 0.0;
vec3 g_irid_fresnel = vec3(0.04);

/// Fills the globals above from the block and the coat map.
///
/// Called before the normal map bends `s.n`, because the coat is lit on the
/// geometric normal: a lacquer over a bumpy base is smooth, and that is what
/// makes car paint read as car paint.
void ReadLayers(Surface s) {
  vec4 coatTexel = texture(coat_texture, v_texcoord, MaterialLodBias());
  vec4 sheenTexel = texture(sheen_texture, v_texcoord, MaterialLodBias());
  g_sheen = layer_info.sheen.rgb * SrgbToLinear(sheenTexel.rgb);
  // Floored where the Charlie lobe's exponent would outgrow a half float,
  // which is also where `tool/make_tables.dart` floors its albedo.
  g_sheen_roughness = clamp(layer_info.sheen.w * sheenTexel.a, 0.07, 1.0);
  // `KHR_materials_ior` and `KHR_materials_specular`: the reflectance a
  // dielectric of this index has head-on, tinted and scaled, and the
  // strength alone at grazing. 1.5, white and one give 0.04 and 1 — plain
  // metal-rough.
  float ior = max(layer_info.coat.z, 1.0);
  float r = (ior - 1.0) / (ior + 1.0);
  g_f0_dielectric =
      min(vec3(r * r) * layer_info.specular.rgb, vec3(1.0)) *
      layer_info.specular.w;
  g_f90 = layer_info.specular.w;
  g_coat = clamp(layer_info.coat.x * coatTexel.r, 0.0, 1.0);
  g_coat_roughness = clamp(layer_info.coat.y * coatTexel.g, 0.02, 1.0);
  // `M3`: the coat map's other two lanes.
  g_transmission = clamp(layer_info.transmission.x * coatTexel.b, 0.0, 1.0);
  g_thickness = max(layer_info.transmission.y * coatTexel.a, 0.0);
  // Beer's law over the thickness: what is left of each colour after the
  // attenuation distance is the attenuation colour.
  float distance = layer_info.transmission.z;
  g_transmittance =
      distance > 0.0
          ? pow(max(layer_info.attenuation.rgb, vec3(1e-4)),
                vec3(g_thickness / distance))
          : vec3(1.0);
  g_iridescence = clamp(layer_info.iridescence.x, 0.0, 1.0);
  g_coat_n = s.n;
  g_coat_n_dot_v = max(dot(s.n, s.v), 1e-4);
  // The coat is a dielectric of index 1.5, and what it reflects towards the
  // eye does not reach the layer under it: everything beneath is scaled by
  // what its Fresnel lets through.
  float fc = 0.04 + 0.96 * pow(1.0 - g_coat_n_dot_v, 5.0);
  g_coat_through = 1.0 - g_coat * fc;
}

/// The half of the layers that depends on the normal the maps leave: the
/// sheen's albedo at this view, and the anisotropy's frame. Called after
/// the maps, before any light.
void ReadLayersOnMaps(Surface s) {
  // `M2`: the sheen's directional albedo, from the LTC table's spare lane,
  // and what it leaves of everything under the sheen.
  g_sheen_albedo =
      textureLod(ltc_texture,
                 LtcUv(g_sheen_roughness,
                       sqrt(clamp(1.0 - s.n_dot_v, 0.0, 1.0)), 1.0),
                 0.0)
          .z;
  g_sheen_scale =
      1.0 - max(max(g_sheen.r, g_sheen.g), g_sheen.b) * g_sheen_albedo;

  // The tangent frame `ApplyNormalMap` builds, on the normal it left, turned
  // by the rotation. A surface without a usable tangent stays isotropic.
  vec3 t = v_tangent.xyz - s.n * dot(s.n, v_tangent.xyz);
  bool usable = dot(t, t) > 1e-12;
  t = usable ? normalize(t) : vec3(1.0, 0.0, 0.0);
  vec3 b = cross(s.n, t) * v_tangent.w;
  if (!gl_FrontFacing) t = -t;
  vec2 turn = layer_info.anisotropy.yz;
  vec3 along = t * turn.x + b * turn.y;
  g_aniso = usable && dot(along, along) > 1e-12
                ? clamp(layer_info.anisotropy.x, 0.0, 1.0)
                : 0.0;
  g_aniso_t = g_aniso > 0.0 ? normalize(along) : t;
  g_aniso_b = cross(s.n, g_aniso_t);
}
#endif  // F3D_LAYERED

/// The environment, convolved by roughness: level zero is a mirror and the last
/// is rough enough to stand in for irradiance. Built by `EnvironmentMap`.
uniform samplerCube environment_texture;

/// The split-sum BRDF, as arithmetic rather than as a lookup table.
///
/// The usual form of this is a 2D texture indexed by roughness and view angle.
/// Karis' analytic fit replaces it at a cost too small to see on anything but a
/// grazing mirror, and what it buys is a third texture binding this renderer
/// does not have to find, bind on every backend, and mirror in the software
/// rasteriser. Returns the scale and bias to apply to F0.
vec2 EnvBrdfApprox(float roughness, float n_dot_v) {
  const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
  const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
  vec4 r = roughness * c0 + c1;
  float a004 = min(r.x * r.x, exp2(-9.28 * n_dot_v)) * r.x + r.y;
  return vec2(-1.04, 1.04) * a004 + r.zw;
}

float D_GGX(float n_dot_h, float alpha) {
  float a = n_dot_h * alpha;
  float k = alpha / max(1.0 - n_dot_h * n_dot_h + a * a, 1e-6);
  return k * k * (1.0 / kPi);
}

float V_SmithGGXCorrelated(float n_dot_v, float n_dot_l, float alpha) {
  float a2 = alpha * alpha;
  float lambda_v = n_dot_l * sqrt(n_dot_v * n_dot_v * (1.0 - a2) + a2);
  float lambda_l = n_dot_v * sqrt(n_dot_l * n_dot_l * (1.0 - a2) + a2);
  return 0.5 / max(lambda_v + lambda_l, 1e-5);
}

vec3 F_Schlick(vec3 f0, float v_dot_h) {
  float f = pow(1.0 - v_dot_h, 5.0);
  return f0 + (vec3(1.0) - f0) * f;
}

#ifdef F3D_LAYERED
/// [F_Schlick] towards [f90] rather than towards one at grazing — what
/// `KHR_materials_specular`'s strength scales.
vec3 F_SchlickF90(vec3 f0, vec3 f90, float v_dot_h) {
  float f = pow(1.0 - v_dot_h, 5.0);
  return f0 + (f90 - f0) * f;
}

/// The clear coat's own GGX lobe for [light], on the coat's normal, with the
/// Fresnel of a dielectric of index 1.5. Scaled so that the loop's `n_dot_l`,
/// which is the base's, becomes the coat's: the coat faces the geometric
/// normal and the base may face the normal map's. A rectangle's `n_dot_l` is
/// a form factor rather than a cosine and is left as it is.
float CoatLobe(LightSample light) {
  float alpha = g_coat_roughness * g_coat_roughness;
  float n_dot_l = max(dot(g_coat_n, light.l), 0.0);
  float n_dot_h = max(dot(g_coat_n, light.h), 0.0);
  float d = D_GGX(n_dot_h, alpha);
  float vis = V_SmithGGXCorrelated(g_coat_n_dot_v, n_dot_l, alpha);
  float f = 0.04 + 0.96 * pow(1.0 - light.v_dot_h, 5.0);
  float scale = light.integrated > 0.5
                    ? 1.0
                    : n_dot_l / max(light.n_dot_l, 1e-6);
  return d * vis * f * frag_info.material.w * scale;
}

/// The Charlie sheen distribution, Estevez and Kulla's, with Filament's
/// floor on `sin²θ` so the power stays inside a half float.
float D_Charlie(float roughness, float n_dot_h) {
  float inv_alpha = 1.0 / (roughness * roughness);
  float sin2h = max(1.0 - n_dot_h * n_dot_h, 0.0078125);
  return (2.0 + inv_alpha) * pow(sin2h, inv_alpha * 0.5) / (2.0 * kPi);
}

/// What a thin film's interference does to the colours it reflects, at an
/// optical path difference [opd] in nanometres and a phase [shift]: the
/// spectral sensitivity of the eye, as Gaussians in XYZ, taken to linear
/// Rec. 709. Belcour and Barla, "A Practical Extension to Microfacet Theory
/// for the Modeling of Varying Iridescence", 2017, with the constants the
/// glTF sample viewer uses.
vec3 IridescenceSensitivity(float opd, vec3 shift) {
  float phase = 2.0 * kPi * opd * 1.0e-9;
  vec3 val = vec3(5.4856e-13, 4.4201e-13, 5.2481e-13);
  vec3 pos = vec3(1.6810e+06, 1.7953e+06, 2.2084e+06);
  vec3 variance = vec3(4.3278e+09, 9.3046e+09, 6.6121e+09);
  vec3 xyz = val * sqrt(2.0 * kPi * variance) * cos(pos * phase + shift) *
             exp(-(phase * phase) * variance);
  xyz.x += 9.7470e-14 * sqrt(2.0 * kPi * 4.5282e+09) *
           cos(2.2399e+06 * phase + shift.x) *
           exp(-4.5282e+09 * phase * phase);
  xyz /= 1.0685e-7;
  return mat3(3.2404542, -0.9692660, 0.0556434, -1.5371385, 1.8760108,
              -0.2040259, -0.4985314, 0.0415560, 1.0572252) *
         xyz;
}

/// The reflectance of a film of index [film] and [thickness] nanometres over
/// a base of reflectance [base], seen at [cos1] — the two-bounce Airy sum of
/// Belcour and Barla. Total internal reflection inside the film reflects
/// everything, chosen at the end rather than returned early.
vec3 FresnelIridescence(float film, float cos1, float thickness, vec3 base) {
  // A film thinning to nothing fades to the base, not to a step.
  float eta2 = mix(1.0, film, smoothstep(0.0, 0.03, thickness));
  float sin2Sq = (1.0 - cos1 * cos1) / (eta2 * eta2);
  float cos2Sq = 1.0 - sin2Sq;
  float cos2 = sqrt(max(cos2Sq, 0.0));

  float r0 = (eta2 - 1.0) / (eta2 + 1.0);
  float r12 = r0 * r0 + (1.0 - r0 * r0) * pow(1.0 - cos1, 5.0);
  float t121 = 1.0 - r12;
  float phi12 = eta2 < 1.0 ? kPi : 0.0;
  float phi21 = kPi - phi12;

  vec3 sqrtBase = sqrt(clamp(base, vec3(0.0), vec3(0.9999)));
  vec3 baseIor = (vec3(1.0) + sqrtBase) / (vec3(1.0) - sqrtBase);
  vec3 r1 = (baseIor - vec3(eta2)) / (baseIor + vec3(eta2));
  r1 *= r1;
  vec3 r23 = r1 + (vec3(1.0) - r1) * pow(1.0 - cos2, 5.0);
  vec3 phi23 = vec3(baseIor.x < eta2 ? kPi : 0.0, baseIor.y < eta2 ? kPi : 0.0,
                    baseIor.z < eta2 ? kPi : 0.0);

  float opd = 2.0 * eta2 * thickness * cos2;
  vec3 phi = vec3(phi21) + phi23;
  vec3 r123 = clamp(r12 * r23, vec3(1e-5), vec3(0.9999));
  vec3 rootR123 = sqrt(r123);
  vec3 rs = t121 * t121 * r23 / (vec3(1.0) - r123);
  vec3 total = vec3(r12) + rs;
  vec3 cm = rs - vec3(t121);
  for (int m = 1; m <= 2; m++) {
    cm *= rootR123;
    total += cm * 2.0 * IridescenceSensitivity(float(m) * opd, float(m) * phi);
  }
  return cos2Sq < 0.0 ? vec3(1.0) : max(total, vec3(0.0));
}

/// Fills the thin film's Fresnel for this fragment, on the base reflectance
/// the maps left. Called after `ReadLayersOnMaps`.
void ReadIridescence(Surface s) {
  vec3 f0 = mix(g_f0_dielectric, s.albedo, clamp(s.metallic, 0.0, 1.0));
  g_irid_fresnel = FresnelIridescence(layer_info.iridescence.y, s.n_dot_v,
                                      layer_info.iridescence.z, f0);
}

/// The environment seen through the surface — `M3`.
///
/// **The environment, where there is no scene to read.** What passes through
/// glass is read from the cube the reflections read, bent by the index when
/// the material has a volume and straight through when it is thin-walled, as
/// the volume extension distinguishes them. The objects behind the glass are
/// not in that cube; [SceneBehind] reads them instead wherever the frame made
/// a copy of the scene, and this is what a draw outside that pass — a probe's
/// capture, the view model — still sees. Dispersion spreads the index over
/// red, green and blue and reads each on its own ray.
vec3 TransmittedRadiance(Surface s, float levels) {
  float ior = max(layer_info.coat.z, 1.0);
  float spread = (ior - 1.0) * 0.025 * layer_info.transmission.w;
  // A rough glass blurs what is behind it more the denser it is.
  float lod = s.roughness * clamp(ior * 2.0 - 2.0, 0.0, 1.0) * levels;
  bool thin = g_thickness <= 0.0;
  vec3 red = thin ? -s.v : refract(-s.v, s.n, 1.0 / max(ior - spread, 1.0));
  vec3 green = thin ? -s.v : refract(-s.v, s.n, 1.0 / ior);
  vec3 blue = thin ? -s.v : refract(-s.v, s.n, 1.0 / (ior + spread));
  return vec3(textureLod(environment_texture, red, lod).r,
              textureLod(environment_texture, green, lod).g,
              textureLod(environment_texture, blue, lod).b);
}

/// Whether this draw has the copy of the scene to read — `M3`.
bool SceneColourBound() { return layer_info.scene_colour.x > 0.0; }

/// Level [level] of the copy at [uv], a coordinate of the picture as a whole.
/// Held half a texel inside the level's rectangle, so a bilinear tap never
/// reaches the level beside it in the same texture.
vec3 SceneColourLevel(vec2 uv, int level) {
  vec4 rect = layer_info.scene_levels[level];
  vec2 inset = 0.5 * layer_info.scene_colour.yz;
  vec2 at = rect.xy + clamp(uv * rect.zw, inset, max(rect.zw - inset, inset));
  return textureLod(scene_colour_texture, at, 0.0).rgb;
}

/// The copy where [world] lands on the screen, blurred to level [lod] and
/// blended between the two levels either side of it, as a trilinear sampler
/// would. Held inside this view, so a ray bent past its edge reads the edge
/// rather than the view beside it.
vec3 SceneColourAt(vec3 world, float lod) {
  vec4 clip = layer_info.scene_view_projection * vec4(world, 1.0);
  vec2 ndc = clip.xy / max(clip.w, 1e-6);
  vec2 view = clamp(vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5), vec2(0.0),
                    vec2(1.0));
  vec2 uv = layer_info.scene_viewport.xy + view * layer_info.scene_viewport.zw;
  float top = layer_info.scene_colour.x - 1.0;
  float level = clamp(lod, 0.0, top);
  float lower = floor(level);
  vec3 near = SceneColourLevel(uv, int(lower));
  vec3 far = SceneColourLevel(uv, int(min(lower + 1.0, top)));
  return mix(near, far, level - lower);
}

/// The scene seen through the surface — `M3`: where the ray the index bends
/// leaves the far side of the volume, as the copy made before this pass holds
/// it, at a level chosen by the roughness. A thin wall bends nothing and
/// reads what lies straight behind it.
///
/// **The level is log2 of the base width times the roughness**, the way the
/// glTF sample renderer reads its transmission target, and not the roughness
/// times the chain's own length. Each level is a box average of the scene,
/// as a mip level is, so level k is a blur of 2^k texels however long the
/// chain is, and the halvings a width has are what take roughness 1 to a
/// single texel. Scaled by the chain instead, a 0.5-rough glass at an index
/// of 1.5 read level 2.5 where it should read 5, a blur of about six texels
/// against thirty-two, and frosted glass looked nearly clear. The chain
/// still ends at `SceneColourChain.maxLevels`, where [SceneColourAt] clamps,
/// so at a thousand texels wide anything rougher than about half reads its
/// last level.
///
/// The width is the base level's, in texels: its rectangle's width over one
/// texel of the texture, which is the size of the scene the chain was copied
/// from.
///
/// **The thickness is in world units as authored.** glTF measures it in the
/// mesh's own space; a node scaled up or down refracts as if it were not,
/// because the stage has no model matrix to scale it by.
vec3 SceneBehind(Surface s) {
  float ior = max(layer_info.coat.z, 1.0);
  float spread = (ior - 1.0) * 0.025 * layer_info.transmission.w;
  float width =
      layer_info.scene_levels[0].z / max(layer_info.scene_colour.y, 1e-9);
  float lod = log2(max(width, 1.0)) * s.roughness *
              clamp(ior * 2.0 - 2.0, 0.0, 1.0);
  bool thin = g_thickness <= 0.0;
  vec3 red = thin ? -s.v : refract(-s.v, s.n, 1.0 / max(ior - spread, 1.0));
  vec3 green = thin ? -s.v : refract(-s.v, s.n, 1.0 / ior);
  vec3 blue = thin ? -s.v : refract(-s.v, s.n, 1.0 / (ior + spread));
  return vec3(SceneColourAt(v_world_position + red * g_thickness, lod).r,
              SceneColourAt(v_world_position + green * g_thickness, lod).g,
              SceneColourAt(v_world_position + blue * g_thickness, lod).b);
}

/// Neubelt and Pettineo's visibility for cloth.
float V_Neubelt(float n_dot_v, float n_dot_l) {
  return 1.0 / (4.0 * (n_dot_l + n_dot_v - n_dot_l * n_dot_v));
}

/// GGX stretched along [t] — `KHR_materials_anisotropy`, the form its
/// specification gives: [at] the roughness along the tangent, [ab] across.
float D_GGXAnisotropic(float n_dot_h, float t_dot_h, float b_dot_h, float at,
                       float ab) {
  float a2 = at * ab;
  vec3 f = vec3(ab * t_dot_h, at * b_dot_h, a2 * n_dot_h);
  float w2 = a2 / max(dot(f, f), 1e-12);
  return a2 * w2 * w2 / kPi;
}

float V_GGXAnisotropic(float n_dot_l, float n_dot_v, float b_dot_v,
                       float t_dot_v, float t_dot_l, float b_dot_l, float at,
                       float ab) {
  float ggx_v = n_dot_l * length(vec3(at * t_dot_v, ab * b_dot_v, n_dot_v));
  float ggx_l = n_dot_v * length(vec3(at * t_dot_l, ab * b_dot_l, n_dot_l));
  return clamp(0.5 / max(ggx_v + ggx_l, 1e-5), 0.0, 1.0);
}
#endif  // F3D_LAYERED

float LightVisibility(Surface s, LightSample light, int index) {
  return ShadowFactor(s, light, index);
}

/// Whether the energy lost to single scattering is put back — `L1`,
/// `RenderSettings.energyCompensation`, in `FragInfo.target_origin.z`.
bool EnergyCompensation() { return frag_info.target_origin.z > 0.5; }

/// The light GGX loses on a rough metal, returned as the factor its single
/// scattering has to be multiplied by: one plus f0 times the share of the
/// hemisphere the single-scattering albedo misses. Fdez-Agüera's term, with
/// the albedo the split sum already computes.
vec3 MultiscatterScale(vec3 f0, Surface s) {
  vec2 ab = EnvBrdfApprox(s.roughness, s.n_dot_v);
  float ess = max(ab.x + ab.y, 1e-4);
  return vec3(1.0) + f0 * (1.0 / ess - 1.0);
}

/// Whether the diffuse lobe is EON rather than Lambert — `L8`,
/// `RenderSettings.diffuseModel`, in `FragInfo.ambient_sky.w`.
bool EonDiffuse() { return frag_info.ambient_sky.w > 0.5; }

/// The two constants of the Fujii Oren–Nayar lobe EON is built on:
/// `1/2 − 2/(3π)`, which normalises its A term, and `2/3 − 28/(15π)`, which
/// with it gives the lobe's albedo averaged over the hemisphere.
const float kFonA = 0.5 - 2.0 / (3.0 * kPi);
const float kFonAverage = 2.0 / 3.0 - 28.0 / (15.0 * kPi);

/// The Fujii Oren–Nayar lobe's directional albedo at a cosine [mu] and
/// roughness [r]: Portsmouth, Kutz and Hill's quartic fit of the exact
/// integral, which trades an `acos` and a division by [mu] for four
/// multiply-adds.
float FonAlbedo(float mu, float r) {
  float m = 1.0 - mu;
  float g = m * (0.0571085289 +
                 m * (0.491881867 + m * (-0.332181442 + m * 0.0714429953)));
  return (1.0 + r * g) / (1.0 + kFonA * r);
}

/// The single-scattering lobe's albedo averaged over the hemisphere.
float FonAverage(float r) {
  return (1.0 + kFonAverage * r) / (1.0 + kFonA * r);
}

/// The albedo the light bouncing between the facets comes back with: one
/// more factor of [rho] per bounce, summed. This is what saturates a rough
/// colour, and what makes a white surface keep every bit of the light.
vec3 EonMultiAlbedo(vec3 rho, float average) {
  return rho * rho * average / (vec3(1.0) - rho * (1.0 - average));
}

/// EON, "An energy-preserving Oren–Nayar model", Portsmouth, Kutz and Hill,
/// 2024: the Fujii Oren–Nayar lobe for one bounce off the facets, plus a
/// lobe shaped by what that one misses at each end for the rest. [rho] the
/// diffuse colour, [r] the roughness, [mu_i] and [mu_o] the cosines to the
/// light and to the eye, [l_dot_v] the cosine between them. Divided by π,
/// as `diffuseColor / kPi` is, so it stands in for it.
vec3 EonLobe(vec3 rho, float r, float mu_i, float mu_o, float l_dot_v) {
  // Oren–Nayar's `s / t`: how far the light and the eye stand on the same
  // side of the normal, which is where the facets turned to both are seen.
  float s = l_dot_v - mu_i * mu_o;
  float s_over_t = s > 0.0 ? s / max(mu_i, mu_o) : s;
  float af = 1.0 / (1.0 + kFonA * r);
  vec3 single = rho * (af * (1.0 + r * s_over_t));
  float average = FonAverage(r);
  vec3 multi = EonMultiAlbedo(rho, average) *
               (max(1.0 - FonAlbedo(mu_o, r), 1e-7) *
                max(1.0 - FonAlbedo(mu_i, r), 1e-7) /
                max(1.0 - average, 1e-7));
  return (single + multi) / kPi;
}

/// [EonLobe] integrated over the hemisphere of light at a cosine [mu] to the
/// eye: what it reflects of light that comes from everywhere alike, as an
/// ambient, an environment's irradiance and a lightmap are taken to.
vec3 EonAlbedo(vec3 rho, float r, float mu) {
  float e = FonAlbedo(mu, r);
  return rho * e + EonMultiAlbedo(rho, FonAverage(r)) * (1.0 - e);
}

vec3 ShadeLight(Surface s, LightSample light) {
  // Perceptual roughness is squared to get the GGX alpha; this is what makes
  // the roughness slider feel linear.
  float alpha = s.roughness * s.roughness;

  // Dielectrics reflect ~4% at normal incidence; metals tint the reflection
  // with their own albedo and have no diffuse response.
#ifdef F3D_LAYERED
  // The dielectric's own reflectance, from its index and specular layer.
  vec3 f0 = mix(g_f0_dielectric, s.albedo, s.metallic);
  vec3 f90 = vec3(mix(g_f90, 1.0, s.metallic));
#else
  vec3 f0 = mix(vec3(0.04), s.albedo, s.metallic);
#endif
  vec3 diffuseColor = s.albedo * (1.0 - s.metallic);

  float d = D_GGX(light.n_dot_h, alpha);
  float vis = V_SmithGGXCorrelated(s.n_dot_v, light.n_dot_l, alpha);
#ifdef F3D_LAYERED
  if (g_aniso > 0.0) {
    // `M2`: the lobe stretched along the tangent, as far as the strength
    // says; across it, the roughness as it was.
    float at = mix(alpha, 1.0, g_aniso * g_aniso);
    float ab = max(alpha, 1e-3);
    d = D_GGXAnisotropic(light.n_dot_h, dot(g_aniso_t, light.h),
                         dot(g_aniso_b, light.h), at, ab);
    vis = V_GGXAnisotropic(light.n_dot_l, s.n_dot_v, dot(g_aniso_b, s.v),
                           dot(g_aniso_t, s.v), dot(g_aniso_t, light.l),
                           dot(g_aniso_b, light.l), at, ab);
  }
  vec3 f = F_SchlickF90(f0, f90, light.v_dot_h);
  // `M3`: the thin film's colours in place of the plain Fresnel.
  f = mix(f, g_irid_fresnel, g_iridescence);
#else
  vec3 f = F_Schlick(f0, light.v_dot_h);
#endif

  vec3 specular = d * vis * f * frag_info.material.w;
  if (light.integrated > 0.5) {
    // `L7`: the lobe already integrated over the rectangle, with the fit's
    // own Fresnel. Divided by `n_dot_l` because the loop multiplies by it,
    // and that is the diffuse form factor, not a term of this; the `kPi` the
    // return applies is the same calibration the diffuse gets.
#ifdef F3D_LAYERED
    specular = light.ltc.x * (f0 * light.ltc.y + (f90 - f0) * light.ltc.z) *
               frag_info.material.w / max(light.n_dot_l, 1e-6);
#else
    specular = light.ltc.x * (f0 * light.ltc.y + (1.0 - f0) * light.ltc.z) *
               frag_info.material.w / max(light.n_dot_l, 1e-6);
#endif
  }
  if (EnergyCompensation()) specular *= MultiscatterScale(f0, s);
  // Energy left over after reflection is what scatters diffusely.
  vec3 diffuse = diffuseColor * (vec3(1.0) - f) / kPi;
  if (EonDiffuse()) {
    // `L8`: on the direction to the light rather than `n_dot_l`, which for
    // a rectangle is a form factor and not a cosine.
    diffuse = EonLobe(diffuseColor, s.roughness,
                      clamp(dot(s.n, light.l), 1e-4, 1.0), s.n_dot_v,
                      dot(light.l, s.v)) *
              (vec3(1.0) - f);
  }
#ifdef F3D_LAYERED
  // `M3`: what passes through is not scattered back; a light on the viewer's
  // side reaches the eye through transmission only by the environment.
  diffuse *= 1.0 - g_transmission;
#endif

  // The pi puts the result back on the scale the tone mapper and the exposure
  // default were calibrated against.
#ifdef F3D_LAYERED
  // Under the sheen, what its albedo leaves; under the coat, what its
  // Fresnel lets through; on top, the coat's own lobe.
  vec3 sheen = g_sheen * D_Charlie(g_sheen_roughness, light.n_dot_h) *
               V_Neubelt(s.n_dot_v, light.n_dot_l);
  return (((diffuse + specular) * g_sheen_scale + sheen) * g_coat_through +
          vec3(g_coat * CoatLobe(light))) *
         kPi;
#else
  return (diffuse + specular) * kPi;
#endif
}

void main() {
  Surface s = ReadSurface();
#ifdef F3D_LAYERED
  ReadLayers(s);
#endif
  ApplyCommonMaps(s);
  ApplyMetallicRoughnessMap(s);
#ifdef F3D_LAYERED
  ReadLayersOnMaps(s);
  ReadIridescence(s);
#endif

  float metallic = clamp(s.metallic, 0.0, 1.0);
  vec3 diffuseColor = s.albedo * (1.0 - metallic);
  // `L8`: light that arrives from everywhere alike — the flat ambient, the
  // environment's irradiance, a lightmap, and under glass what passes
  // through — is reflected by the EON lobe's albedo at this view rather than
  // by the colour itself.
  if (EonDiffuse()) {
    diffuseColor = EonAlbedo(diffuseColor, s.roughness, s.n_dot_v);
  }

  // Ambient occlusion darkens indirect light. It is applied to the direct term
  // too, which is not physical, but with no environment the flat ambient is far
  // too weak for an occlusion map to be visible otherwise.
  vec3 ambient = diffuseColor * s.ambient * s.occlusion;
#ifdef F3D_LAYERED
  // `M3`: without an environment the light passing through is the flat
  // ambient too, less what the medium takes — unless the scene behind is
  // there to be read, when that share is the scene instead (below).
  ambient *= mix(vec3(1.0), SceneColourBound() ? vec3(0.0) : g_transmittance,
                 g_transmission);
#endif

  float levels = frag_info.frame_params.w;
#ifdef F3D_LAYERED
  // What the coat reflects of the environment; nothing without one, since
  // the flat ambient has no specular part for it to have. The sheen's
  // incoming light, which without an environment is the flat ambient.
  vec3 coatAmbient = vec3(0.0);
  vec3 sheenIncoming = s.ambient;
#endif
  if (levels > 0.0) {
    // **This is the term that made metal black.** A metal has no diffuse
    // response at all, so with nothing to reflect it was lit by direct light
    // alone and read as very nearly unlit — which is why the games reached for
    // dark dielectrics wherever they wanted gunmetal.
#ifdef F3D_LAYERED
    vec3 f0 = mix(g_f0_dielectric, s.albedo, metallic);
    float f90 = mix(g_f90, 1.0, metallic);
    // `M2`: an anisotropic surface reflects along a normal bent towards the
    // stretch, the specification's own approximation.
    vec3 bent = s.n;
    if (g_aniso > 0.0) {
      vec3 across = cross(g_aniso_t, s.v);
      vec3 anisoN = cross(across, g_aniso_t);
      float bend = 1.0 - g_aniso * (1.0 - s.roughness);
      float bend4 = bend * bend * bend * bend;
      bent = normalize(mix(anisoN, s.n, bend4));
    }
    vec3 reflected = reflect(-s.v, bent);
#else
    vec3 f0 = mix(vec3(0.04), s.albedo, metallic);
    vec3 reflected = reflect(-s.v, s.n);
#endif

    // The roughest level stands in for irradiance. Not a true Lambert
    // convolution — see `EnvironmentMap.diffuseLevel`, which says the same
    // thing from the other side and states what it costs.
    vec3 irradiance = textureLod(environment_texture, s.n, levels).rgb;
    vec3 prefiltered =
        textureLod(environment_texture, reflected, s.roughness * levels).rgb;
    vec2 ab = EnvBrdfApprox(s.roughness, s.n_dot_v);

    // Scaled by the strength in the slot the flat term above reads, which is
    // why the two are interchangeable rather than additive: whichever term
    // runs, it runs at `material.z`. **What that number is depends on what is
    // bound.** A scene's own environment is scaled by `Scene.ambientIntensity`,
    // the same knob the flat term uses, so a scene that dials its indirect
    // light down dials both; a reflection probe brings its own
    // `ReflectionProbeNode.intensity` instead, because a probe is the room's
    // light already measured. The renderer decides which — see `_encodeNode`
    // in renderer_mesh_encode.dart — and this stage cannot tell them apart.
#ifdef F3D_LAYERED
    vec3 specular =
        prefiltered * (mix(f0, g_irid_fresnel, g_iridescence) * ab.x + f90 * ab.y);
#else
    vec3 specular = prefiltered * (f0 * ab.x + ab.y);
#endif
    if (EnergyCompensation()) {
      // Fdez-Agüera: the single-scattered part as it was, and the multiple
      // scattering it misses added from the irradiance, tinted by the average
      // Fresnel — `L1`.
#ifdef F3D_LAYERED
      vec3 single = f0 * ab.x + f90 * ab.y;
#else
      vec3 single = f0 * ab.x + ab.y;
#endif
      float missed = 1.0 - (ab.x + ab.y);
      vec3 average = f0 + (vec3(1.0) - f0) / 21.0;
      vec3 multiple = single * average / (vec3(1.0) - missed * average);
      specular += multiple * missed * irradiance;
    }
    ambient = (diffuseColor * irradiance + specular) * frag_info.material.z *
              s.occlusion;
#ifdef F3D_LAYERED
    // `M3`: the transmitted share of the diffuse light is the environment
    // behind the surface instead, less what the dielectric reflects and what
    // the medium takes, tinted by the base colour as glTF tints it.
    // With the scene behind to read, the environment's share is taken away
    // and the scene's added below.
    vec3 reflects =
        mix(g_f0_dielectric, g_irid_fresnel, g_iridescence) * ab.x + g_f90 * ab.y;
    vec3 through = SceneColourBound()
                       ? vec3(0.0)
                       : TransmittedRadiance(s, levels) * g_transmittance *
                             (vec3(1.0) - min(reflects, vec3(1.0)));
    ambient += diffuseColor * (through - irradiance) * g_transmission *
               frag_info.material.z * s.occlusion;
    // The coat reflects the environment too, on its own normal and at its
    // own roughness, over what it lets through of the layer beneath.
    vec3 coatPrefiltered = textureLod(environment_texture,
                                      reflect(-s.v, g_coat_n),
                                      g_coat_roughness * levels)
                               .rgb;
    vec2 coatAb = EnvBrdfApprox(g_coat_roughness, g_coat_n_dot_v);
    coatAmbient = coatPrefiltered * (0.04 * coatAb.x + coatAb.y) * g_coat *
                  frag_info.material.z * s.occlusion;
    sheenIncoming =
        textureLod(environment_texture, s.n, g_sheen_roughness * levels).rgb *
        frag_info.material.z;
#endif
  }
#ifdef F3D_LAYERED
  // `M3`: the transmitted share is the scene behind, where the pass has a
  // copy of it — less what the dielectric reflects and what the medium
  // takes, tinted by the base colour. Light already, so neither the ambient
  // strength nor the occlusion scales it.
  if (SceneColourBound()) {
    vec2 sceneAb = EnvBrdfApprox(s.roughness, s.n_dot_v);
    vec3 sceneReflects =
        mix(g_f0_dielectric, g_irid_fresnel, g_iridescence) * sceneAb.x +
        g_f90 * sceneAb.y;
    ambient += diffuseColor * SceneBehind(s) * g_transmittance *
               (vec3(1.0) - min(sceneReflects, vec3(1.0))) * g_transmission;
  }
#endif
  // The light the level's walls throw on each other, baked: diffuse only,
  // since a lightmap holds irradiance and a metal has no diffuse response.
  // Zero from the one-texel black a material without a map is bound to.
  //
  // **Added rather than chosen between, and the choosing happens above this
  // shader.** A lightmap and an environment's roughest level are two answers
  // to the same question — how much indirect light reaches this point — so a
  // draw that had both would count it twice. There is no flag here to branch
  // on: a material without a map is bound the neutral black by design (see
  // material_maps.glsl), which is what makes this a plain add. The renderer
  // keeps the two apart instead, by handing no reflection probe to a
  // lightmapped draw; see `_encodeNode` in renderer_mesh_encode.dart. A sky
  // environment over a lightmapped level still adds, and should: sky light
  // is not what the bake measured.
  ambient += diffuseColor * SampleLightmap() * s.occlusion;

#ifdef F3D_LAYERED
  // What shines from under the coat is dimmed by it on the way out, the
  // emission included — glTF's own layering. The direct light was scaled in
  // `ShadeLight`.
  vec3 sheenAmbient = g_sheen * g_sheen_albedo * sheenIncoming * s.occlusion;
  WriteSurface(
      AccumulateLights(s) * s.occlusion +
          (ambient * g_sheen_scale + sheenAmbient + s.emissive) *
              g_coat_through +
          coatAmbient,
      s.alpha,
      s.roughness);
#else
  WriteSurface(
      AccumulateLights(s) * s.occlusion + ambient + s.emissive,
      s.alpha,
      s.roughness);
#endif
}

#endif  // PBR_GLSL_
