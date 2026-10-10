#version 460 core

// The sky as air: sunlight scattered once by molecules (Rayleigh) and by haze
// (Mie) along the view ray, dimmed by those two and by ozone, which absorbs
// without scattering; the sun's disc seen through what the air leaves of it,
// stars at night, and the ground below the horizon.
//
// The output is luminance. `v_sun.w` is the sunlight's lux on the renderer's
// luminance scale, and a coefficient per kilometre times lengths in kilometres
// times a phase function per steradian leaves candela per square metre.
//
// **Marched per pixel rather than read from a precomputed table.** A table is
// what a sky this size usually becomes, and it is two render passes into
// float targets before the scene, plus a sampler the sky's pipeline would have
// to be measured taking — `sky.vert` says why nothing is assumed about what
// reaches it. Sixteen samples along the view and eight towards the sun at each
// is 144 exponentials a pixel, paid only where no geometry covers the sky,
// because the stage runs after the opaque half and fails the depth test under
// it. `SkySettings.physical` documents the cost where a caller will read it.
//
// **Single scattering only**, and that is visible: the horizon at noon comes
// out a pale cyan rather than white, because light scattered twice is what
// whitens it. Measured against a 128 × 64 march of the same model, the
// march here is within two per cent of it at the zenith and four at the
// horizon. Two choices buy that. The view samples are spaced quadratically,
// short near the eye where a horizontal ray spends its densest air; spaced
// evenly, sixteen of them put the noon horizon's blue at less than half of
// what it is. And each sample is dimmed by the air up to its middle rather
// than its far end, which was another fifteen per cent.
//
// The same arithmetic runs in Dart twice: `PhysicalSky.radiance`, for a fog
// colour, a sunlight colour and an environment map built from the sky, and
// `SkyPhysicalShader` in the software rasteriser. A test evaluates both.
precision highp float;

in vec3 v_ray;
in vec4 v_rayleigh;
in vec4 v_mie;
in vec4 v_sun;
in vec4 v_planet;
in vec4 v_stars;
in vec4 v_disc;

layout(location = 0) out vec4 frag_color;

// No surface output, for the reason `sky.frag` records at length: on Impeller,
// a second output in a single-attachment pass took the process down.

const int kViewSteps = 16;
const int kLightSteps = 8;
const float kPi = 3.14159265;

// Ozone's absorption at the peak of its layer, per km, at the Earth's amount
// (Bruneton 2017, for 680, 550 and 440 nm); `v_stars.w` scales it. The layer
// peaks 25 km up and thins linearly to nothing 15 km either side.
const vec3 kOzone = vec3(0.650e-3, 1.881e-3, 0.085e-3);
const float kOzonePeak = 25.0;
const float kOzoneHalfWidth = 15.0;

/// The ozone at [h] km above the ground, as a share of its peak.
float OzoneDensity(float h) {
  return max(0.0, 1.0 - abs(h - kOzonePeak) / kOzoneHalfWidth);
}

/// The air at [h] km: x molecules and y haze relative to the ground, z ozone
/// relative to its peak.
vec3 AirAt(float h) {
  return vec3(exp(-h / vec2(v_rayleigh.w, v_mie.z)), OzoneDensity(h));
}

/// How far a ray from radius [r], at cosine [mu] to the local up, runs before
/// it leaves a sphere of [radius]; negative when it misses.
///
/// `(r - radius) * (r + radius)` rather than `r * r - radius * radius`: the
/// two squares are 4·10⁷ km² apiece and their difference near the ground is a
/// few hundred, which the subtraction of the squares loses most of in single
/// precision.
float Leave(float r, float mu, float radius) {
  float b = r * mu;
  float d = b * b - (r - radius) * (r + radius);
  return d < 0.0 ? -1.0 : -b + sqrt(d);
}

/// How far the same ray runs before it meets the ground, negative when it
/// does not.
float Meet(float r, float mu, float radius) {
  float b = r * mu;
  float d = b * b - (r - radius) * (r + radius);
  return d < 0.0 ? -1.0 : -b - sqrt(d);
}

/// The air between [p] and space towards [s]: x molecules, y haze, each as a
/// length of air at ground density, and z ozone as a length at its peak.
vec3 SunwardAir(vec3 p, vec3 s) {
  float r = length(p);
  float span = Leave(r, dot(p, s) / r, v_planet.y);
  float stride = span / float(kLightSteps);
  vec3 air = vec3(0.0);
  for (int j = 0; j < kLightSteps; j++) {
    vec3 q = p + s * ((float(j) + 0.5) * stride);
    air += AirAt(length(q) - v_planet.x) * stride;
  }
  return air;
}

/// What a length of air lets through, per channel.
vec3 Through(vec3 air) {
  return exp(-(v_rayleigh.rgb * air.x + vec3(v_mie.y * air.y) +
               kOzone * (v_stars.w * air.z)));
}

/// A hash of three small whole numbers into [0, 1), with no sine in it.
///
/// `fract(sin(x) * 43758.5)` is the usual one and it is wrong here: the sine
/// of a large argument is computed differently by every GPU and by the
/// software rasteriser, so the stars would be in different places on each
/// backend. This is products and `fract`s of numbers below a few thousand,
/// which single precision answers alike everywhere to the last few bits.
float Hash(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.zyx + 31.32);
  return fract((p.x + p.y) * p.z);
}

/// The stars in direction [d]: a grid of cells on each face of a cube, a share
/// [v_stars.y] of them holding a star at a place and a brightness of its own.
float StarField(vec3 d) {
  vec3 a = abs(d);
  float face;
  vec2 uv;
  if (a.x >= a.y && a.x >= a.z) {
    face = d.x > 0.0 ? 0.0 : 1.0;
    uv = d.zy / a.x;
  } else if (a.y >= a.z) {
    face = d.y > 0.0 ? 2.0 : 3.0;
    uv = d.xz / a.y;
  } else {
    face = d.z > 0.0 ? 4.0 : 5.0;
    uv = d.xy / a.z;
  }
  vec2 grid = (uv * 0.5 + 0.5) * v_stars.z;
  vec2 cell = floor(grid);
  vec3 key = vec3(cell, face);
  if (Hash(key) >= v_stars.y) return 0.0;
  vec2 centre = vec2(Hash(key + vec3(17.0, 0.0, 0.0)),
                     Hash(key + vec3(0.0, 29.0, 0.0))) * 0.6 + 0.2;
  float off = length(grid - cell - centre);
  float magnitude = Hash(key + vec3(0.0, 0.0, 13.0));
  return (1.0 - smoothstep(0.0, 0.35, off)) *
         (0.15 + 0.85 * magnitude * magnitude * magnitude);
}

void main() {
  vec3 d = normalize(v_ray);
  vec3 s = v_sun.xyz;
  vec3 eye = vec3(0.0, v_planet.z, 0.0);

  float ground = Meet(v_planet.z, d.y, v_planet.x);
  bool grounded = ground > 0.0;
  float span = grounded ? ground : Leave(v_planet.z, d.y, v_planet.y);

  vec3 seenAir = vec3(0.0);
  vec3 molecules = vec3(0.0);
  vec3 haze = vec3(0.0);
  for (int i = 0; i < kViewSteps; i++) {
    float a0 = float(i) / float(kViewSteps);
    float a1 = float(i + 1) / float(kViewSteps);
    float t = span * 0.5 * (a0 * a0 + a1 * a1);
    float stride = span * (a1 * a1 - a0 * a0);
    vec3 p = eye + d * t;
    float r = length(p);
    vec3 air = AirAt(r - v_planet.x) * stride;
    seenAir += air;
    // In the planet's shadow: this sample is lit by nothing.
    if (Meet(r, dot(p, s) / r, v_planet.x) > 0.0) continue;
    vec3 through = Through(seenAir - 0.5 * air + SunwardAir(p, s));
    molecules += air.x * through;
    haze += air.y * through;
  }

  float mu = dot(d, s);
  float g = v_mie.w;
  float gg = g * g;
  float rayleighPhase = 3.0 / (16.0 * kPi) * (1.0 + mu * mu);
  // Cornette–Shanks, which is Henyey–Greenstein with the Rayleigh term's
  // shape folded in. g is held below one by the renderer, so the base of the
  // power never reaches nought.
  float miePhase = 3.0 / (8.0 * kPi) * ((1.0 - gg) * (1.0 + mu * mu)) /
                   ((2.0 + gg) * pow(1.0 + gg - 2.0 * g * mu, 1.5));

  // Luminance: see the note at the top on `v_sun.w`.
  vec3 colour = v_sun.w * (molecules * v_rayleigh.rgb * rayleighPhase +
                           haze * (v_mie.x * miePhase));
  vec3 seen = Through(seenAir);

  if (grounded) {
    // The ground, lit by what the air leaves of the sun and seen through the
    // air in front of it. Lambertian, and with no light from the sky itself,
    // so a ground in the sun's shadow is black; it is what fills the lower
    // half of an environment map built from this sky, not a terrain.
    vec3 p = eye + d * span;
    float lit = dot(normalize(p), s);
    if (lit > 0.0) {
      colour += seen * Through(SunwardAir(p, s)) *
                (v_planet.w / kPi * lit * v_sun.w);
    }
  } else {
    // The disc, through the air in front of it: this is what turns it red
    // at sunset with no colour anybody chose. `sky.frag` explains the
    // guard and why the soft edge travels as a difference.
    float disc = v_disc.y > 0.0
        ? smoothstep(v_disc.x - v_disc.y, v_disc.x, mu)
        : step(v_disc.x, mu);
    colour += seen * (disc * v_disc.z);

    // Stars, as the sun goes down: a fade from the sun six degrees above
    // the horizon to eleven below, rather than the sky's own brightness,
    // which would need the exposure this stage does not know.
    float night = 1.0 - smoothstep(-0.2, 0.1, s.y);
    if (v_stars.x > 0.0 && night > 0.0) {
      colour += seen * (v_stars.x * night * StarField(d));
    }
  }

  frag_color = vec4(colour, 1.0);
}
