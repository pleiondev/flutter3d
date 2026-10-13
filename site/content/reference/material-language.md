---
description: The .f3dmat material language, version 3. Surfaces, the light, ambient and composite hooks, plugin light types, the vertex block that also moves the shadow, state in the file, the scene behind a translucent surface, a material's own version and updates, full-screen stages for render steps, computed textures lowered to the kernel language, typed accessors, and what each backend does with each construct.
---

# The material language

A `.f3dmat` file is one stage written once. The build compiles it for Impeller, WebGL2 and WebGPU, and the software backend runs the same tree in Dart, so no backend has a transcription of its own that could drift. The vocabulary is GLSL's (`mix`, `clamp`, swizzles, `vec3 * float`). What it leaves out is anything a material must not do: sample a texture nobody binds, loop, or write a global. A material's own blocks and textures are declared in the language (version 2), so the engine binds them as it binds its own.

```text
f3dmat 2
material Kelp {
  uniform float time = 0.0;
  state { blend mask; cutoff 0.4; alphaToCoverage on; doubleSided on; }
  vertex {
    let sway = 0.15 * sin(time + origin.x + origin.z) * position.y;
    out position = position + vec3(sway, 0.0, 0.0);
  }
  light { return albedo; }
  fragment { return vec4(lit, alpha); }
}
```

Put it under `assets_src/` and the build hook compiles it into `flutter3d_generated/`. A mistake fails the build with the file, line and column. See [the asset pipeline](/reference/asset-pipeline/).

## Versions

The first line may name the version: `f3dmat 1`, `f3dmat 2` or `f3dmat 3`. A file without that line is version 1. A build reads every version up to its own `materialLanguageVersion`, which is 3 in 1.0, and refuses a newer file with the version that reads it.

Each construct below is read only in a file whose version has it. A version 1 file keeps every name it used, so a `let sceneDepth` written before version 2 still compiles.

- **Version 2** adds the `state`, `vertex`, `ambient` and `composite` blocks, the `fullscreen` and `compute` kinds, the scene inputs (`sceneDepth`, `viewDepth`, `scenePosition`), and a material's own blocks and textures: `uniform(Hair) vec3 tint = ...;` is a member of a block called `Hair`, and `texture fur;` a texture of the material's own, bound as `material_fur`. It reserves names starting `f3d_` for the generated stage.
- **Version 3** adds what a light block knows of the light (`lightKind`, `lightParams` and `lighttype`), the `instance` input of the vertex block, which is then drawn on instanced and lightmapped draws too, and a material's own version with its `updates`.

A material's own version is not the language's. `material Hatch version 3 { ... }` counts the changes to one material's parameters, and its `updates` block says how a value an instance set for an older version carries forward:

```text
f3dmat 3
material Hatch version 3 {
  uniform vec3 inkColor = vec3(0.1);
  uniform float roughness = 0.5;
  updates {
    2: rename ink -> inkColor;
    3: scale roughness 0.5;
  }
  light { return albedo * nDotL; }
  fragment { return vec4(lit, alpha); }
}
```

An update is `rename a -> b`, `scale a <factor>` or `remove a`, under the version it leads to. `MaterialProgram.lift` applies them, and a level or a saved instance that names an older version is read through them rather than under the new meaning.

## What a source holds

A source is one of three kinds, each named by the word it opens with:

| Kind | Opens with | Bodies | Becomes |
|---|---|---|---|
| Surface | `material` | `fragment`, and optionally `light`, `ambient`, `composite`, `vertex`, `state`, `updates` | a lighting model a `RenderMaterial` draws with |
| Full-screen | `fullscreen` | `fragment` | a stage a `FullscreenEffect` or a plugin's render step draws |
| Compute | `compute` | `kernel`, optionally `workgroup` | a texture computed texel by texel, lowered to the kernel language |

Every kind takes declarations:

- `param float x = 1.0;` is a constant folded into the stage. A variant changes it.
- `uniform vec3 c = vec3(1.0);` is a member of the `MaterialParams` block, set at run time through `RenderMaterial.parameters` or a [typed accessor](#typed-accessors).
- `texture base = base_color_texture;` is a slot. In a surface it must be a slot the engine binds: `base_color_texture`, `normal_texture`, `occlusion_texture`, `emissive_texture` or `metallic_roughness_texture`. In a full-screen stage or a kernel the name is yours, and whoever draws it binds the texture by that name.

## Surfaces

The `fragment` body returns a `vec4`: the light the surface gives off in rgb, and its opacity in a. It reads the surface as `ReadSurface` left it: `albedo`, `alpha`, `normal`, `view`, `nDotV`, `metallic`, `roughness`, `occlusion`, `emissive`, `ambient`, `uv`, `world` and `instance`.

### The light hooks

`light { ... }` runs once per light and returns a `vec3`, how the surface answers that one light. The engine multiplies it by the light's radiance, n·l and shadow, as it does for its own lit models. It reads `lightDir`, `halfDir`, `nDotL`, `nDotH` and `vDotH` besides the surface. The fragment body reads the sum as `lit`. A material with a light block is a lit model: it applies the normal, occlusion and emissive maps and binds the shadows and the light list.

Without hooks, `lit` is `(direct + indirect) * occlusion + emissive`, where `direct` is the lights gathered through the block and `indirect` is `albedo * (ambient + lightmap)`. Version 2 adds two hooks, both allowed only beside a `light` block:

- `ambient { return ...; }` replaces `indirect`. It reads the surface and `lightmap`, the level's baked light at the fragment.
- `composite { return ...; }` replaces the whole sum. It reads the surface, `direct` and `indirect`, the latter two not yet multiplied by the occlusion. What it returns is `lit`.

Version 3 lets the light block know which light it shades. `lightKind` is the light's type code: 0 directional, 1 point, 2 spot, 3 area, and a plugin's own light type from 16. `lightParams` is the last `vec4` of the light's row, which a plugin's `LightTypeHook` packs. `lighttype tube = acme.tube;` declares a name the block reads as one while it shades a light of the plugin type `acme.tube` and as nought otherwise, so a block need not know the code the renderer gave the type. A block that reads any of the three gathers its lights through the material's own loop, which hands it a plugin's light rather than skipping it.

```text
f3dmat 2
material Hatch {
  state { environment off; }
  light { return albedo * step(0.5, nDotL) / max(nDotL, 0.001); }
  composite { return floor(direct * 4.0) / 4.0 + emissive; }
  fragment { return vec4(lit, alpha); }
}
```

These hooks are how a [registered lighting model](/core/rendering/) is written: `MaterialBindings.lightingModel` builds a `LightingModel` from the source, and `LightingModels.register` makes its name one a material file may use.

### State

The `state` block says how the surface is drawn. Each setting appears at most once, and anything left out keeps `RenderMaterial`'s default:

| Setting | Values | Becomes |
|---|---|---|
| `blend` | `opaque`, `mask`, `hashed`, `alpha`, `additive`, `premultiplied` | `RenderMaterial.alphaMode` and `RenderMaterial.blendMode` |
| `cutoff` | 0 to 1, with `blend mask` only | `alphaCutoff` |
| `alphaToCoverage` | `on`/`off`, with `blend mask` only | `alphaToCoverage` |
| `depthWrite` | `on`/`off` | `depthWrite` |
| `depthTest` | `off` is a test that always passes | `depthCompare` |
| `depthCompare` | `never`, `less`, `equal`, `lessEqual`, `greater`, `notEqual`, `greaterEqual`, `always` | `depthCompare` |
| `doubleSided` | `on`/`off` | `doubleSided` |
| `depthLayer` | a whole number from −16 to 16 | `RenderMaterial.depthLayer` |
| `effectsDepth` | `on`/`off`, translucent blends only | `RenderMaterial.effectsDepth` |
| `environment` | `off` leaves the hemisphere, the irradiance field and the lightmap out of `lit` | a switch in the stage |
| `directional` | `off` leaves the directional lights, the sun, out of `lit` | a switch in the stage |

`BundledMaterials.read(bytes).material(name)` (the `BundledMaterialLooks` extension of `package:flutter3d_core`) makes a `RenderMaterial` with the lighting model, the uniforms at their defaults and all the draw state above. Every field can still be changed in Dart afterwards. `environment` and `directional` are compiled into the stage, so nothing at run time turns them back on. A stage with a switch still keeps every sampler the engine binds to a lit stage, behind a branch no frame takes, so the binding stays the same as for any other lit model.

**Blend modes.** `alpha` is over on straight colour, glTF's blend. `additive` adds the colour times its alpha to what is already there. `premultiplied` is over on a colour the body already multiplied by its alpha: the stage leaves the colour exactly as returned, so one surface can both add light and cover what is behind it. On the engine's own lighting models `RenderMaterial.blendMode = premultiplied` draws the same as `alpha`, because those stages weight their colour by alpha themselves. Under weighted blended transparency every translucent surface is a layer of the weighted average, and the blend mode is not used.

**Depth layers.** Of two coplanar surfaces, the one with the higher layer wins: a decal on a wall, markings on a road, a puddle on a floor. Where the device has `DeviceFeature.depthBias` (WebGL2, WebGPU and the software rasteriser), a layered draw is pulled towards the eye by four of the depth format's smallest steps and one slope per layer. The bias is turned round for reversed-Z, as every bias is. Where it does not (Impeller today), the opaque half draws layered surfaces after the rest, lowest layer first, and tests them `lessEqual`, so the later of two equal depths wins. Both rules apply wherever both are possible. Layers affect the scene pass only. A level document carries them per brush, and brushes on different layers are never batched together.

**Effects depth.** A translucent surface normally stays out of the surface buffer, the normals and depths that depth of field, ambient occlusion, the fog march, outlines and soft particles read. With `effectsDepth on`, it writes its normal and depth into that buffer whole while its colour blends, so water the camera focuses on stays sharp and the smoke over it fades against the water rather than the river bed. This needs `DeviceFeature.independentBlend` and a frame that sorts its transparency. Elsewhere it is not honoured.

### The vertex block

`vertex { ... }` moves the geometry. It holds `let` bindings and `out` outputs, and reads the vertex once the engine has morphed it, and skinned it on a skinned draw:

- `position` and `objectNormal`: in the mesh's own space, which is the pose's space for a skinned mesh
- `world` and `normal`: after the model transform
- `uv`, `color`: the first texture coordinate and the vertex colour
- `origin`: where the object stands, the model transform's translation

It writes `out position = ...` (in mesh space, before the model transform) or `out world = ...` (after it), not both, and optionally `out normal = ...`. An output it does not write keeps the engine's value. It cannot sample a texture.

The build turns the block into two vertex stages, `<Name>Vertex` and `<Name>VertexSkinned`, and the material's lighting model names them. **The depth pre-draw and the shadow passes draw through the same stage** (`LightingModel.vertexStageInDepthPasses`), both cascades and point-light cubes, so geometry the block moves casts the shadow it draws. A block that writes `world` is projected through `MaterialVertexInfo.view_projection`, which the renderer binds with the matrix of whichever pass is drawing.

From version 3 the block also runs on instanced and lightmapped draws, as `<Name>VertexInstanced` and `<Name>VertexLightmapped`, and reads `instance`, the instance's own four numbers (`InstancedMeshNode.setInstanceData`), nought on any other draw. On a lightmapped draw `color` is white, because the attribute holds the lightmap's coordinate there. Below version 3, instanced and lightmapped draws keep the engine's own vertex stages. The pick pass and the velocity pass keep them at every version: picking reads the unmoved surface, and motion blur and temporal anti-aliasing see the object move but not what the block does to its vertices.

### The scene behind

A translucent surface (`blend alpha`, `additive` or `premultiplied`) reads the opaque scene behind it in its fragment body:

- `sceneDepth`: how far the opaque surface behind this fragment is along the view axis, in metres. It reads a million where nothing was drawn, which means the sky.
- `viewDepth`: this fragment's own depth along the same axis, so `sceneDepth - viewDepth` is the thickness of what lies between. Any surface can read this one.
- `scenePosition`: where in the world that opaque surface is.

```text
f3dmat 2
material Shallows {
  uniform vec3 deep = vec3(0.02, 0.12, 0.15);
  state { blend alpha; depthWrite off; effectsDepth on; }
  fragment {
    let thickness = sceneDepth - viewDepth;
    let shore = clamp(thickness * 3.0, 0.0, 1.0);
    let fog = 1.0 - exp(-0.4 * thickness);
    return vec4(mix(albedo, deep, fog), shore * alpha);
  }
}
```

A frame with such a surface splits, as it does for soft particles. The opaque half is drawn first, then these surfaces are drawn in the pass after the transparent half, with the surface buffer bound rather than attached. Each frame keeps one sample per pixel, and `FrameResult.msaaDeclined` says why. A device with one colour attachment has no surface buffer, so there the surface reads the sky.

## Full-screen stages

```text
f3dmat 2
fullscreen DepthFog {
  uniform vec3 colour = vec3(0.6, 0.7, 0.8);
  uniform float density = 0.02;
  fragment {
    let c = sample(scene, uv);
    let t = 1.0 - exp(-density * sceneDepth);
    return vec4(mix(c.rgb, colour, t), c.a);
  }
}
```

A full-screen stage reads `uv`, from the top left, and the picture as the texture `scene`, which it must sample. It may also read `sceneDepth`, the scene's depth at the pixel. Its declared textures are bound by the names it gives them, and every one must be sampled, because a stage that drops a sampler which the engine still binds crashes natively on Metal. `describeMaterial(...).readsSurfaceBuffer` says whether it reads the depth, which is `FullscreenEffect.readsSurface`. Such an effect needs the surface buffer, and on a device without one the frame skips it and reports why.

A plugin's render step can be one of these: in a `.f3dplugin`, `"shaders": {"material": "fog.f3dmat"}` in place of a stage per backend. `RuntimeShaders` builds it for whatever backend the engine draws with, its uniforms at their defaults under `MaterialParams`. On WebGPU this needs `webGpuFullscreenUvLocation()` from `flutter3d_webgpu`.

## Computed textures

```text
f3dmat 2
compute Ripples {
  uniform float time = 0.0;
  workgroup 8 8;
  kernel {
    let d = length(uv - vec2(0.5));
    return vec4(vec3(0.5 + 0.5 * sin(40.0 * d - time)), 1.0);
  }
}
```

A `compute` stage computes a texture texel by texel. Its kernel runs once per texel of the storage texture bound as `target` and writes what it returns there. It reads `cell` (the texel), `size` (the target in texels) and `uv` (the texel's centre, from nought to one). `workgroup x y` or `workgroup x y z` is at most 256 invocations in all and 64 along z, eight by eight by one by default.

**It is the short form of a kernel.** The engine has one compute language, the kernel language a `ComputeStep` hands its kernels in (`ComputeKernel` in `package:flutter3d_shaders/kernel.dart`), with buffers, textures, images, loops and branches. `lowerMaterialCompute(program)` writes a `compute` stage in it, and the build and `RuntimeShaders` carry that kernel in the bundle's kernel section. So the stage runs wherever a kernel runs, on WebGPU, on the wgpu sidecar and on the software backend, through the same two translations, and it is versioned as the kernel language is: the lowered source opens with `kernel 1`. The lowering decides four things:

- a `uniform` is read from an `f32` buffer called `params`, each uniform's components one after another in the order the source declares them. `MaterialComputeKernel.parameterBytes` packs it; a `param` is folded at its default;
- `sample(t, uv)` is bilinear between the four texels around `uv` of the texture's base level, clamped to its edge, with the texture bound under its binding name;
- `mix`, `smoothstep`, `step`, `fract`, `dot`, `length` and `normalize` are written out in arithmetic, and `sin`, `cos` and `pow` are the kernel language's own;
- an invocation past the target's edge does nothing, so the target need not be a multiple of the workgroup.

The material receives the result as an input. The texture the stage writes is an ordinary texture, bound to a surface's own `texture` slot like any other.

```dart
final ripples = lowerMaterialCompute(parseMaterial(source));
final stage = await ripples.load(device); // bind target, params; dispatch
```

**Impeller and WebGL2 have no compute pipelines.** There `MaterialComputeKernel.load` and `RuntimeShaders` refuse the stage with an `UnsupportedCapabilityException` naming `DeviceFeature.compute`. The fallback is to compute the texture on the CPU at load: `ripples.bake(width, height, parameters: ...)` runs the same kernel in Dart and answers its RGBA8 texels, which are uploaded as any texture is. A uniform that changes every frame has no such fallback.

## Typed accessors

The build writes `lib/materials.g.dart`, with an extension type per material that declares a `uniform`. It is a typed view over the same `RenderMaterial.parameters` map:

```dart
import 'package:flutter3d_effects/flutter3d_effects.dart';

final seabed = SeabedParameters(material.parameters)
  ..time = seconds
  ..eye = camera.position
  ..level = 0.0;
```

A misspelt member is a compile error rather than a uniform that silently never moves. Each member says its GLSL type and default, and `SeabedParameters.defaults()` is a fresh map of the defaults. The file is generated only in a package whose pubspec names `vector_math`. The string map stays, because it is what the renderer binds and what a data plugin, which has no Dart, writes. `flutter3d_effects` ships `SeabedParameters` and `LiquidParameters`, which `SeabedLook` and `LiquidLook` use internally.

## What each backend does

"Build" means the bundle the build hook makes. "Run time" means `RuntimeShaders` compiling a plugin's source while the game runs.

| Construct | Impeller | WebGL2 | WebGPU | Software |
|---|---|---|---|---|
| Surface, `light` | build | build, run time | build; run time without `light` | build, run time |
| `ambient`, `composite`, `environment`, `directional` | build | build, run time | build; run time refused (lit stage) | build, run time |
| `vertex` | build | build, run time | build; run time refused: no vertex stage to splice into | build, run time |
| `blend` modes, depth state | yes | yes | yes | yes |
| `alphaToCoverage` | drawn with the hard cutoff | yes | yes | drawn with the hard cutoff |
| `depthLayer` | stable order and `lessEqual` (no depth bias in flutter_gpu) | bias and order | bias and order | bias and order |
| `effectsDepth` | where `independentBlend` | where `independentBlend` | yes | where `independentBlend` |
| `sceneDepth`, `scenePosition` | build | build, run time | build; run time refused: the host stage binds no scene depth | build, run time |
| `viewDepth` | build | build, run time | build, run time | build, run time |
| `fullscreen` | build; run time refused (`impellerc` does not ship with a game) | build, run time | build, run time | build, run time |
| `compute` | refused, naming `DeviceFeature.compute`; baked on the CPU at load | refused, naming `DeviceFeature.compute`; baked on the CPU at load | build, run time, lowered to the kernel language | build, run time, lowered to the kernel language |

Every refusal is an exception or a `RuntimeShaders.statuses` entry with the sentence from this table. Nothing is ever silently drawn wrong.
