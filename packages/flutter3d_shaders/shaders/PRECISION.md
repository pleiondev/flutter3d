# Precision in the material stages

`A1.1` of `tasks/0.10-plan.md`. This is the contract: what a lit material
stage may compute at mediump, what it must keep at highp, and why. It sits
beside the shaders because it is a rule about them.

## Which stages

The twelve lit material stages define `F3D_MEDIUMP` before their includes:
`Pbr`, `PbrLayered`, `BlinnPhong`, `Lambert`, `Toon` and `Unlit`, and the
opaque variant of each (`A1.2`). No other stage defines it. Post passes,
particles, splats, the sky, the probes and every shadow stage compile exactly
as they did, at highp throughout.

## The rule: highp, with mediump stretches

Every header is written at highp. A function whose numbers are all colours,
unit vectors or factors between nought and one sits in a **mediump
stretch**:

```glsl
#ifdef F3D_MEDIUMP
precision mediump float;
#endif
vec3 F_Schlick(vec3 f0, float v_dot_h) { ... }
precision highp float;
```

A precision statement applies to everything declared after it, so the
function's parameters, its return value and its locals are mediump in a
material stage, and the stretch ends by coming back to highp. Outside a
material stage the `#ifdef` is empty and the stretch is highp like the rest.
A local may also be qualified `mediump` where the rest of its function cannot
be; `Toon`'s band arithmetic is.

**Why the stretches are the exception rather than the rule.** A function
nobody has looked at is highp, so a line added later is safe until somebody
decides it can be cheaper. The opposite arrangement — mediump everywhere and
highp marked — fails quietly: a new helper that subtracts two positions loses
its centimetres on a phone and nowhere else.

## What stays highp, and why

- **Declarations.** Every uniform block, varying, output, sampler and global
  is declared at highp. A vertex stage declares the same blocks at highp, and
  GLSL ES refuses to link a block whose members differ in precision between
  stages. Nothing in a block or a varying carries a qualifier of its own; the
  WebGPU translator and the stage tables read those lines.
- **Function prototypes and their definitions** — `ShadeLight`,
  `LightVisibility`, `MapUv`, `MapMatrix`. A prototype and its body must
  agree on precision, and the prototypes are declared beside the blocks.
- **Positions.** A half float holds eleven significant bits: a metre at a
  kilometre from the origin, which is where a level's corner is. Anything a
  world position is subtracted from — the view direction, a light's
  direction, a cluster lookup, the irradiance field's cell — is highp until
  it has been normalised.
- **Texture coordinates.** A coordinate at mediump is a texel off on a
  2048-texel map. The coordinates come from highp varyings and are passed
  straight to the sampler.
- **Depth.** `ViewDepth`, `EyeDistance`, the shadow map's light-space
  coordinates and every comparison in `ShadowFactor`, `ShadowStored` and
  `ShadowStoredStep`. A shadow bias is a few thousandths of a cascade's
  range; mediump has fewer.
- **Light.** Everything that carries light: a light's radiance, the sums of
  `AccumulateLights`, the ambient, the lightmap, the emissive after its
  strength, the colour handed to `WriteSurface` and `WriteDebugView`. The
  physical sky's sun is a hundred thousand lux before exposure, and a half
  float stops at 65504; past it the pixel is infinite, then NaN, then the
  bloom spreads it.
- **The GGX lobe.** `D_GGX` and the visibility terms divide by alpha
  squared, which is 4·10⁻⁶ at the least roughness the lobe is evaluated at
  and below mediump's smallest normal number. The guards in them are at
  1e-7 and 1e-5, and a guard mediump cannot represent guards nothing.
- **Noise.** `ShadowNoise`, the Vogel disc's turn, the hashed alpha, the
  interleaved gradient noise and the blue noise all take `fract` of a large
  product. At mediump the product has no fraction left and the pattern
  collapses into stripes.
- **Anything with a Dart twin** outside the software backend whose parity is
  a float32 contract — the environment prefilter, the sky, the tone curves.
  None of those are in the material stretches, and none may be.

## What is mediump

- `SrgbToLinear` — an authored colour, a texel or a tint in, a reflectance
  out. `EncodeOctahedral` — a unit normal into the half-float surface buffer,
  which keeps eleven bits anyway.
- `ApplyMetallicRoughnessMap`, `ApplyOcclusionMap`, `ApplyEmissiveMap` — the
  factors a map multiplies. The emissive light itself is made of highp
  uniforms, so it is computed at highp whatever the stretch says.
- `F_Schlick`, `F_SchlickF90`, `MultiscatterScale` — Fresnel and the energy
  factor, all between nought and a few.
- `Toon`'s bands, as locals.

That is deliberately little. The rest of a lit stage is position, depth,
light or noise.

## What each backend does with it

- **WebGL2.** The translator copies the source with its precision statements
  and qualifiers. A phone's GPU honours mediump and runs those stretches at
  half precision. A desktop browser compiles through ANGLE, which computes
  both at full precision, so the desktop golden sets do not move.
- **Impeller.** impellerc compiles the desktop GLSL 4.60 source with glslang,
  which does carry the precision through: the SPIR-V marks the mediump values
  `RelaxedPrecision` (74 decorations in `Toon`, 0 in `Xray`, measured with
  `spirv-dis` on impellerc's own output). Vulkan consumes that SPIR-V, and
  Mali, Adreno and PowerVR drivers run relaxed values at half precision; the
  OpenGL ES output says `precision mediump float;` and qualifies everything
  else highp. On Metal the output has no `half` in it, so Apple's GPUs are
  unchanged, and so are desktop Vulkan drivers, which ignore the decoration.
- **WebGPU.** glslang's SPIR-V goes through naga to WGSL, which has no
  sixteen-bit float without `shader-f16`, and naga drops the decoration.
  Unchanged.
- **The software rasteriser** runs its Dart transcriptions in doubles and
  stores float32, as it always has. Unchanged.

## The switch back

`WebGlDevice.open(highpMaterials: true)` turns every `mediump` in a stage's
source into `highp` before the browser compiles it: the arithmetic every
release before 1.0 ran. It is a device's option rather than a frame's
setting because a stage is compiled once per device. Impeller has no such
switch; a bundle built without `F3D_MEDIUMP` defined is the old one.

## Adding a material stage

1. Define `F3D_MEDIUMP` before the includes, as the twelve do.
2. Declare anything new — a block, a sampler, a global — at highp, outside
   every stretch.
3. Put a function in a mediump stretch only if every number in it is a
   colour, a unit vector or a factor of a size a half float carries, and
   nothing in it is compared with a threshold below 6·10⁻⁵.
4. Compile the stage as GLSL ES 3.00 and link it with `mesh.vert`; a
   precision mismatch between the stages shows there and nowhere else.

## Still to do

The frame time before and after on the A55 and in a browser on a phone,
which `A1.1` asks for and nothing here has measured. Mediump buys most where
a GPU runs half precision at twice the rate, and these stretches are a small
share of a lit stage; the measurement says whether to widen them.
