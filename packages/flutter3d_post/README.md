# flutter3d_post

Post-processing for flutter3d, one library per family of effects, and the standard preset of all six. Every effect is a plugin and the switch of its own render step, and discovery installs them all from this package's `flutter3d_plugins:` markers, one per library. `package:flutter3d_post/flutter3d_post.dart` exports every family and the preset.

An application that wants only some of them leaves the rest out in its own pubspec, by library or by class:

```yaml
flutter3d_plugins:
  exclude: [flutter3d_post/motion.dart, flutter3d_post/style.dart#ToonLightingAddon]
```

`flutter3d_plugin_api`'s README describes `include:` and `exclude:`.

| Library | Was | What it is |
| --- | --- | --- |
| `light.dart` | `flutter3d_addon_light` | The light family of flutter3d's post-processing |
| `shading.dart` | `flutter3d_addon_shading` | The shading family of flutter3d's post-processing |
| `reflections.dart` | `flutter3d_addon_reflections` | The reflections family of flutter3d's post-processing |
| `atmosphere.dart` | `flutter3d_addon_atmosphere` | The atmosphere family of flutter3d's post-processing |
| `motion.dart` | `flutter3d_addon_motion` | The motion family of flutter3d's post-processing |
| `style.dart` | `flutter3d_addon_style` | The style family of flutter3d's post-processing |
| `standard.dart` | `flutter3d_addons_standard` | The `standard` preset of flutter3d's post-processing |

## `light.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_light`.*

The light family of flutter3d's post-processing: bloom, the lens flare, auto
and local exposure, the colour grade, the lens's distortion, the vignette and
the grain. Each effect is a plugin on
[`flutter3d_plugin_api`](https://pub.dev/packages/flutter3d_plugin_api) and
the switch of its own render step.

| Plugin | Id | Step | Configured by |
|---|---|---|---|
| `BloomAddon` | `flutter3d_addon_light.bloom` | `bloom` | `RenderSettings.bloom` |
| `LensFlareAddon` | `flutter3d_addon_light.lens_flare` | `lens flare` | `BloomSettings.lensFlare` |
| `AutoExposureAddon` | `flutter3d_addon_light.auto_exposure` | `auto exposure` | `RenderSettings.autoExposure` |
| `LocalExposureAddon` | `flutter3d_addon_light.local_exposure` | `local exposure` | `RenderSettings.localExposure` |
| `ColorGradeAddon` | `flutter3d_addon_light.colour_grade` | `colour grade` | `RenderSettings.look` |
| `LensDistortionAddon` | `flutter3d_addon_light.lens_distortion` | `lens distortion` | `LookSettings.distortion`, `chromaticAberration` |
| `VignetteAndGrainAddon` | `flutter3d_addon_light.vignette_and_grain` | `vignette and grain` | `LookSettings.vignette`, `grain` |

### Manifest

Every plugin here has the same shape:

- **apiVersion** 1.0;
- **touches** `view`, so switching one is not written into a replay;
- **backends** all of them;
- **permissions** none;
- **dependsOn**: the lens flare names the bloom, whose glow it is drawn
  from; the others name nothing.

The pubspec marks all seven with `flutter3d_plugins:`, so an application
that depends on this package gets them from `plugins.g.dart`.

### Example

```dart
import 'package:flutter3d_post/light.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

final loop = EngineLoop(
  input: input,
  registries: <PluginRegistry>[renderer.renderSteps],
  plugins: lightAddons,
);

// The frame with the glow.
renderer.render(
  width: 1280,
  height: 720,
  scene: scene,
  views: views,
  settings: const RenderSettings(bloom: BloomSettings(intensity: 0.6)),
);

// From the next step boundary on, every frame is drawn without the film.
loop.plugins.disable(const VignetteAndGrainAddon().id);
```

### What installing it does to the frame

Nothing. While a plugin is on, its step is drawn as `RenderSettings` says,
exactly as with no plugin installed. Switched off, the step is withdrawn:
every frame of that renderer is drawn `RenderSettings.without` it, together
with whatever needs it, and `FrameResult.skipped` reports it as switched
off. Switched back on, it is drawn again.

A renderer with no addon installed draws every step as its settings say.
That is the 1.0 promise, and the reason the `standard` preset
([`flutter3d_post/standard.dart`](https://pub.dev/packages/flutter3d_post))
changes no golden.

### Where the code is

The passes are still drawn by the renderer in `flutter3d_core`, at the
anchors they always stood at: `beforeAutoExposure`, `beforeLocalExposure`,
`beforeBloom`, `beforeLensFlare`, and the composite for the grade, the lens
and the film. Each pass reads the renderer's private pipelines, its pooled
targets and the uniforms the composite shares with tone mapping, so it
moves here once those are public. The settings types (`BloomSettings`,
`LookSettings` and the rest) are defined in the kernel, because `RenderSettings` holds a field of each, and a game imports them from `flutter3d_core` or through `flutter3d`.

## `shading.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_shading`.*

The shading family of flutter3d's post-processing: screen-space ambient
occlusion and contact shadows. Each effect is a plugin on
[`flutter3d_plugin_api`](https://pub.dev/packages/flutter3d_plugin_api) and
the switch of its own render step.

| Plugin | Id | Step | Configured by |
|---|---|---|---|
| `AmbientOcclusionAddon` | `flutter3d_addon_shading.ambient_occlusion` | `ambient occlusion` | `RenderSettings.ambientOcclusion` |
| `ContactShadowsAddon` | `flutter3d_addon_shading.contact_shadows` | `contact shadows` | `RenderSettings.contactShadows` |

### Manifest

Both plugins have the same shape:

- **apiVersion** 1.0;
- **touches** `view`, so switching one is not written into a replay;
- **backends** all of them;
- **permissions** none;
- **dependsOn** nothing.

The pubspec marks both with `flutter3d_plugins:`, so an application that
depends on this package gets them from `plugins.g.dart`.

### Example

```dart
import 'package:flutter3d_post/shading.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

final loop = EngineLoop(
  input: input,
  registries: <PluginRegistry>[renderer.renderSteps],
  plugins: shadingAddons,
);

const settings = RenderSettings(
  ambientOcclusion: AmbientOcclusionSettings(enabled: true),
  contactShadows: ContactShadowSettings(enabled: true),
);

// A low-power mode: from the next step boundary on, no occlusion.
loop.plugins.disable(const AmbientOcclusionAddon().id);
```

### What installing it does to the frame

Nothing. While a plugin is on, its step is drawn as `RenderSettings` says,
exactly as with no plugin installed. Switched off, the step is withdrawn:
every frame of that renderer is drawn `RenderSettings.without` it, and
`FrameResult.skipped` reports its passes as switched off. The temporal
resolve's history of the effect starves with it.

A renderer with no addon installed draws every step as its settings say.
That is the 1.0 promise, and the reason the `standard` preset
([`flutter3d_post/standard.dart`](https://pub.dev/packages/flutter3d_post))
changes no golden.

### Where the code is

The passes (`ssao`, `ssao blur`, `contact shadows`,
`contact shadow resolve`) are still drawn by the renderer in
`flutter3d_core`, between `beforeAmbientOcclusion` and
`afterContactShadows`. They read the surface buffer the scene pass writes,
the renderer's half-resolution targets and its blue-noise table, and the
lit passes read what they write back through the renderer's own bindings,
so they move here once those are public. The settings types are defined in the kernel, because `RenderSettings` holds a field of each, and a game imports them from `flutter3d_core` or through `flutter3d`.

## `reflections.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_reflections`.*

The reflections family of flutter3d's post-processing: screen-space
reflections, planar reflections and reflection probes. Each effect is a
plugin on [`flutter3d_plugin_api`](https://pub.dev/packages/flutter3d_plugin_api)
and the switch of its own render step.

| Plugin | Id | Step | Configured by |
|---|---|---|---|
| `ReflectionProbesAddon` | `flutter3d_addon_reflections.probes` | `reflection probes` | `RenderSettings.reflectionProbes`, `ReflectionProbeNode` |
| `PlanarReflectionsAddon` | `flutter3d_addon_reflections.planar` | `planar reflections` | `RenderSettings.planarReflections`, `PlanarReflectorNode` |
| `ScreenSpaceReflectionsAddon` | `flutter3d_addon_reflections.screen_space` | `reflections` | `RenderSettings.reflections` |

### Manifest

All three plugins have the same shape:

- **apiVersion** 1.0;
- **touches** `view`, so switching one is not written into a replay;
- **backends** all of them;
- **permissions** none;
- **dependsOn** nothing.

The pubspec marks all three with `flutter3d_plugins:`, so an application
that depends on this package gets them from `plugins.g.dart`.

### Example

```dart
import 'package:flutter3d_post/reflections.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

final loop = EngineLoop(
  input: input,
  registries: <PluginRegistry>[renderer.renderSteps],
  plugins: reflectionsAddons,
);

scene
  ..add(ReflectionProbeNode(faceSize: 64))
  ..add(PlanarReflectorNode(surfaces: <MeshNode>[pond]));

// The probes keep the picture they last took, and stop recapturing.
loop.plugins.disable(const ReflectionProbesAddon().id);
```

### What installing it does to the frame

Nothing. While a plugin is on, its step is drawn as `RenderSettings` says,
exactly as with no plugin installed. Switched off, the step is withdrawn:
every frame of that renderer is drawn `RenderSettings.without` it, and
`FrameResult.skipped` reports its passes as switched off. A probe that
stops recapturing keeps its last picture, as with the setting.

A renderer with no addon installed draws every step as its settings say.
That is the 1.0 promise, and the reason the `standard` preset
([`flutter3d_post/standard.dart`](https://pub.dev/packages/flutter3d_post))
changes no golden.

### Where the code is

The passes are still drawn by the renderer in `flutter3d_core`: the probes
and the planar pictures among the captures (`beforeCaptures`), and the
screen-space reflections after the scene (`beforeReflections`). The
captures draw the scene again through the renderer's own scene encoder,
and the scene pass samples what they took through its bindings, so they
move here once both are public. The settings types and scene nodes are defined in the kernel and imported from `flutter3d_core`, or through `flutter3d`.

## `atmosphere.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_atmosphere`.*

The atmosphere family of flutter3d's post-processing: distance and height
fog, volumetric fog, light shafts and the sky. Each effect is a plugin on
[`flutter3d_plugin_api`](https://pub.dev/packages/flutter3d_plugin_api) and
the switch of its own render step.

| Plugin | Id | Step | Configured by |
|---|---|---|---|
| `SkyAddon` | `flutter3d_addon_atmosphere.sky` | `sky` (this package's own, `skyStep`) | `RenderSettings.sky` |
| `FogAddon` | `flutter3d_addon_atmosphere.fog` | `fog` | `RenderSettings.fog` |
| `VolumetricFogAddon` | `flutter3d_addon_atmosphere.volumetric_fog` | `volumetric fog` | `RenderSettings.volumetricFog` |
| `LightShaftsAddon` | `flutter3d_addon_atmosphere.light_shafts` | `light shafts` | `RenderSettings.lightShafts` |

Height fog is part of the fog step: `FogSettings.heightFalloff` thins the
fog upwards from `baseHeight`. The sky is physical, `PhysicalSky`, unless it
was given gradient colours or a cubemap.

### Manifest

All four plugins have the same shape:

- **apiVersion** 1.0;
- **touches** `view`, so switching one is not written into a replay;
- **backends** all of them;
- **permissions** none;
- **dependsOn** nothing.

`SkyAddon` adds a step before it provides it. The kernel's thirty steps
have none for the sky, which is drawn inside the scene pass. `skyStep` is
switched by `SkySettings.enabled`.

The pubspec marks all four with `flutter3d_plugins:`, so an application
that depends on this package gets them from `plugins.g.dart`.

### Example

```dart
import 'package:flutter3d_post/atmosphere.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

final loop = EngineLoop(
  input: input,
  registries: <PluginRegistry>[renderer.renderSteps],
  plugins: atmosphereAddons,
);

const settings = RenderSettings(
  sky: SkySettings(enabled: true),
  fog: FogSettings(density: 0.02, heightFalloff: 0.1),
  volumetricFog: VolumetricFogSettings(enabled: true),
);

// Indoors: no sky, and no shafts of it.
loop.plugins
  ..disable(const SkyAddon().id)
  ..disable(const LightShaftsAddon().id);
```

### What installing it does to the frame

Nothing. While a plugin is on, its step is drawn as `RenderSettings` says,
exactly as with no plugin installed. Switched off, the step is withdrawn:
every frame of that renderer is drawn `RenderSettings.without` it, and
`FrameResult.skipped` reports it as switched off. That covers the fog and
the sky, which own no pass and are reported under their step's name.

A renderer with no addon installed draws every step as its settings say.
That is the 1.0 promise, and the reason the `standard` preset
([`flutter3d_post/standard.dart`](https://pub.dev/packages/flutter3d_post))
changes no golden.

### Where the code is

The fog and the sky are arithmetic inside the renderer's scene pass in
`flutter3d_core`, compiled into the lit stages and the sky triangle, so they
cannot move apart from it. The volumetric fog and the light shafts are
passes between `beforeVolumetricFog` and `afterLightShafts`. They read the
shadow cascades, the light buffer and the surface buffer through the
renderer's own bindings, so they move here once those are public. The
settings types are defined in the kernel and imported from `flutter3d_core`, or through `flutter3d`.

## `motion.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_motion`.*

The motion family of flutter3d's post-processing: depth of field, motion
blur and temporal anti-aliasing. Each effect is a plugin on
[`flutter3d_plugin_api`](https://pub.dev/packages/flutter3d_plugin_api) and
the switch of its own render step.

| Plugin | Id | Step | Configured by |
|---|---|---|---|
| `DepthOfFieldAddon` | `flutter3d_addon_motion.depth_of_field` | `depth of field` | `RenderSettings.depthOfField` |
| `MotionBlurAddon` | `flutter3d_addon_motion.motion_blur` | `motion blur` | `RenderSettings.motionBlur` |
| `TemporalAntiAliasingAddon` | `flutter3d_addon_motion.temporal_anti_aliasing` | `temporal anti-aliasing` | `AntiAliasSettings.temporal` |

### Manifest

All three plugins have the same shape:

- **apiVersion** 1.0;
- **touches** `view`, so switching one is not written into a replay;
- **backends** all of them;
- **permissions** none;
- **dependsOn** nothing.

The pubspec marks all three with `flutter3d_plugins:`, so an application
that depends on this package gets them from `plugins.g.dart`.

### Example

```dart
import 'package:flutter3d_post/motion.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

final loop = EngineLoop(
  input: input,
  registries: <PluginRegistry>[renderer.renderSteps],
  plugins: motionAddons,
);

const settings = RenderSettings(
  depthOfField: DepthOfFieldSettings(enabled: true),
  motionBlur: MotionBlurSettings(enabled: true),
  antiAlias: AntiAliasSettings(temporal: TemporalSettings(enabled: true)),
);

// A player who gets sick from smearing turns it off.
loop.plugins.disable(const MotionBlurAddon().id);
```

### What installing it does to the frame

Nothing. While a plugin is on, its step is drawn as `RenderSettings` says,
exactly as with no plugin installed. Switched off, the step is withdrawn:
every frame of that renderer is drawn `RenderSettings.without` it, and
`FrameResult.skipped` reports its passes as switched off. Without the
temporal resolve, a spatial upscale that was asked for runs in its place,
as it does when the setting is off.

A renderer with no addon installed draws every step as its settings say.
That is the 1.0 promise, and the reason the `standard` preset
([`flutter3d_post/standard.dart`](https://pub.dev/packages/flutter3d_post))
changes no golden.

### Where the code is

The passes are still drawn by the renderer in `flutter3d_core`, between
`beforeVelocity` and `afterTemporalResolve`. The velocity passes belong to
no step. They run while the blur or the resolve reads them, and the
resolve keeps the renderer's history ring and the jitter the scene pass
draws with. These move here once the history and the jitter are public. The
settings types are defined in the kernel and imported from `flutter3d_core`, or through `flutter3d`.

## `style.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_style`.*

The style family of flutter3d's post-processing: the high-contrast look,
its outlines, and the editor's viewport shading. Each effect is a plugin on
[`flutter3d_plugin_api`](https://pub.dev/packages/flutter3d_plugin_api) and
the switch of its own render step.

| Plugin | Id | Step | Configured by |
|---|---|---|---|
| `HighContrastAddon` | `flutter3d_addon_style.high_contrast` | `high contrast` | `RenderSettings.highContrast` |
| `OutlinesAddon` | `flutter3d_addon_style.outlines` | `outlines` (this package's own, `outlinesStep`) | `HighContrastSettings.outlineWidth`, `MeshNode.outlineColor` |
| `ViewportShadingAddon` | `flutter3d_addon_style.viewport_shading` | `viewport shading` | `RenderSettings.viewportShading` |

The toon look is not here yet. It is a lighting model a material picks,
`LightingModel.toon`, and it is compiled into the scene's own stages rather
than drawn as a step of the frame.

### Manifest

All three plugins have the same shape:

- **apiVersion** 1.0;
- **touches** `view`, so switching one is not written into a replay;
- **backends** all of them;
- **permissions** none;
- **dependsOn**: the outlines name the high-contrast look, which draws
  them; the others name nothing.

`OutlinesAddon` adds a step before it provides it. The kernel's thirty steps
have none for the rings, which are drawn inside the high-contrast pass.
`outlinesStep` is switched by `HighContrastSettings.outlineWidth` and needs
`RenderStep.highContrast`.

The pubspec marks all three with `flutter3d_plugins:`, so an application
that depends on this package gets them from `plugins.g.dart`.

### Example

```dart
import 'package:flutter3d_post/style.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

final loop = EngineLoop(
  input: input,
  registries: <PluginRegistry>[renderer.renderSteps],
  plugins: styleAddons,
);

monster.outlineColor = Vector3(1.0, 0.2, 0.2);
const settings = RenderSettings(
  highContrast: HighContrastSettings(enabled: true),
);

// The flat look without the rings.
loop.plugins.disable(const OutlinesAddon().id);
```

### What installing it does to the frame

Nothing. While a plugin is on, its step is drawn as `RenderSettings` says,
exactly as with no plugin installed. Switched off, the step is withdrawn:
every frame of that renderer is drawn `RenderSettings.without` it, and
`FrameResult.skipped` reports it as switched off. The look cannot be
switched off while the outlines are on. The plugin host refuses it and
names the outlines.

A renderer with no addon installed draws every step as its settings say.
That is the 1.0 promise, and the reason the `standard` preset
([`flutter3d_post/standard.dart`](https://pub.dev/packages/flutter3d_post))
changes no golden.

### Where the code is

The passes (`outline mask`, `high contrast`, `viewport shading`) are still
drawn by the renderer in `flutter3d_core`, between `beforeHighContrast` and
`afterViewportShading`. The mask draws the marked nodes through the
renderer's velocity stages, and the looks read its surface buffer and
pooled targets, so they move here once those are public. The settings types
are defined in the kernel and imported from `flutter3d_core`, or through `flutter3d`.

## `standard.dart`

*Until 1.0.0-rc.1, `flutter3d_addons_standard`.*

The `standard` preset of flutter3d's post-processing: the six addon
families in one list, `standardAddons`.

| Family | Effects |
|---|---|
| [`flutter3d_post/light.dart`](https://pub.dev/packages/flutter3d_post) | bloom, lens flare, auto and local exposure, colour grade, lens distortion, vignette and grain |
| [`flutter3d_post/shading.dart`](https://pub.dev/packages/flutter3d_post) | ambient occlusion, contact shadows |
| [`flutter3d_post/reflections.dart`](https://pub.dev/packages/flutter3d_post) | screen-space reflections, planar reflections, reflection probes |
| [`flutter3d_post/atmosphere.dart`](https://pub.dev/packages/flutter3d_post) | fog with height fog, volumetric fog, light shafts, the sky |
| [`flutter3d_post/motion.dart`](https://pub.dev/packages/flutter3d_post) | depth of field, motion blur, temporal anti-aliasing |
| [`flutter3d_post/style.dart`](https://pub.dev/packages/flutter3d_post) | high contrast, outlines, viewport shading |

Twenty-two plugins in all. The kernel keeps the scene, the composite, tone
mapping, the shadows, the edge smoothing and sharpening, the upscale and
the anchors around all of them. Those steps have no addon.

### Example

```dart
import 'package:flutter3d_post/standard.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

final loop = EngineLoop(
  input: input,
  registries: <PluginRegistry>[renderer.renderSteps],
  plugins: standardAddons,
);

// A settings screen's "bloom" toggle.
void setBloom(bool on) => on
    ? loop.plugins.enable(const BloomAddon().id)
    : loop.plugins.disable(const BloomAddon().id);
```

The families' own pubspecs mark their plugins for discovery, so an
application that depends on this package and uses `plugins.g.dart` gets
them without the list. Pass the list in code to override discovery. This
package has no marker of its own, which would name every plugin twice.

### What installing it does to the frame

**Nothing, and that is what it promises.** An addon provides a step the
kernel already draws. While every provider is on, the renderer plans and
draws exactly what it draws with no addon installed, pass for pass. The
frame order fixture in `flutter3d_cpu/test/goldens/frame_order.jsonl`
(244 frames: the default settings and every step on, each step switched off
alone and kept alone, with and without application nodes) comes out byte
for byte the same with the preset installed.

**A renderer without the preset keeps today's defaults too.** In 1.0 a step
nobody provides is drawn as its settings say, so an application that never
heard of addons sees no change.

What the preset adds is the switches. Disabling a plugin withdraws its step
from every frame of that renderer, and whatever needs it with it, and
`FrameResult.skipped` names it as switched off. Enabling it puts it back.
See `RendererSteps.provide` in `flutter3d_core`.
