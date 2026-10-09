## 1.0.0-rc.1

- **Breaking: a family's library does not re-export its settings.**
  `FogSettings`, `BloomSettings`, `MotionBlurSettings`, `ReflectionSettings`,
  `PlanarReflectorNode`, `ReflectionProbeNode`, `AmbientOcclusionSettings`,
  `HighContrastSettings`, `SettingsSlot` and the rest are `flutter3d_core`'s,
  imported from there or through `flutter3d`.

- **Its plugins are marked with `flutter3d_plugins:`** (decision D), the key
  pub does not warn about.

- **New: one package for what was seven.** `flutter3d_addon_light`,
  `flutter3d_addon_shading`, `flutter3d_addon_reflections`,
  `flutter3d_addon_atmosphere`, `flutter3d_addon_motion`,
  `flutter3d_addon_style`, `flutter3d_addons_standard` are libraries of this
  package now: `light.dart`, `shading.dart`, `reflections.dart`,
  `atmosphere.dart`, `motion.dart`, `style.dart`, `standard.dart`, each with the
  API its package had, and `flutter3d_post.dart` exports them all. `dart run
  flutter3d_build:migrate` moves a project's dependencies and imports; the
  packages' own histories are in `doc/changelogs/`.
- **One plugin marker per library.** The families' plugins are listed under
  their libraries in `flutter3d: plugin:`, which discovery now reads as a map of
  library to classes, so one dependency installs every effect as a switch, as
  the standard preset did.

### `light.dart`, from `flutter3d_addon_light` 1.0.0-rc.1

- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `ColourGradeAddon` is `ColorGradeAddon`. Only the Dart names
  changed: a file keeps the keys it was written with, and `dart fix`
  carries the renames.
- **The light family as plugins.** `BloomAddon`, `LensFlareAddon`,
  `AutoExposureAddon`, `LocalExposureAddon`, `ColorGradeAddon`,
  `LensDistortionAddon` and `VignetteAndGrainAddon`, all in `lightAddons`.
  Each is a view plugin on plugin API 1.0 and the switch of one render
  step. The lens flare depends on the bloom.

- **Each plugin names the settings it reads.** The family's addons add
  `SettingsSlot.bloom`, `look`, `autoExposure` and `localExposure` to the
  renderer while on, so `RendererSteps.settings` lists them, and this
  library exports `SettingsSlot`. The types stay defined in
  `flutter3d_core`, which reads them as fields of `RenderSettings`.

- **Installing them changes nothing.** The kernel still draws the passes,
  with the settings it always had. Switching a plugin off withdraws its step
  from every frame, and `FrameResult.skipped` reports it as switched off.
  A renderer with no addon installed draws what it always drew.

- **The family's settings in one import.** `BloomSettings`,
  `LensFlareSettings`, `AutoExposureSettings`, `ExposureMeter`,
  `ExposureAdapter`, `LocalExposureSettings` and `LookSettings` are exported
  here. They are still defined in `flutter3d_core`, so existing imports keep
  compiling.

### `shading.dart`, from `flutter3d_addon_shading` 1.0.0-rc.1

- **The shading family as plugins.** `AmbientOcclusionAddon` and
  `ContactShadowsAddon`, both in `shadingAddons`. Each is a view plugin on
  plugin API 1.0 and the switch of one render step.

- **Each plugin names the settings it reads.** The family's addons add
  `SettingsSlot.ambientOcclusion` and `contactShadows` to the renderer while
  on, so `RendererSteps.settings` lists them, and this library exports
  `SettingsSlot`. The types stay defined in `flutter3d_core`, which reads
  them as fields of `RenderSettings`.

- **Installing them changes nothing.** The kernel still draws the passes,
  with the settings it always had. Switching a plugin off withdraws its step
  from every frame, and `FrameResult.skipped` reports it as switched off.
  A renderer with no addon installed draws what it always drew.

- **The family's settings in one import.** `AmbientOcclusionSettings`,
  `AmbientOcclusionMethod` and `ContactShadowSettings` are exported here.
  They are still defined in `flutter3d_core`, so existing imports keep
  compiling.

### `reflections.dart`, from `flutter3d_addon_reflections` 1.0.0-rc.1

- **The reflections family as plugins.** `ReflectionProbesAddon`,
  `PlanarReflectionsAddon` and `ScreenSpaceReflectionsAddon`, all in
  `reflectionsAddons`. Each is a view plugin on plugin API 1.0 and the
  switch of one render step.

- **Each plugin names the settings it reads.** The family's addons add
  `SettingsSlot.reflections` and `planarReflections` to the renderer while
  on, so `RendererSteps.settings` lists them, and this library exports
  `SettingsSlot`. The types stay defined in `flutter3d_core`, which reads
  them as fields of `RenderSettings`.

- **Installing them changes nothing.** The kernel still draws the passes,
  with the settings it always had. Switching a plugin off withdraws its step
  from every frame, and `FrameResult.skipped` reports it as switched off.
  A renderer with no addon installed draws what it always drew.

- **The family's settings in one import.** `ReflectionSettings`,
  `PlanarReflectionSettings`, `ReflectionProbeNode` and
  `PlanarReflectorNode` are exported here. They are still defined in
  `flutter3d_core`, so existing imports keep compiling.

### `atmosphere.dart`, from `flutter3d_addon_atmosphere` 1.0.0-rc.1

- **The atmosphere family as plugins.** `SkyAddon`, `FogAddon`,
  `VolumetricFogAddon` and `LightShaftsAddon`, all in `atmosphereAddons`.
  Each is a view plugin on plugin API 1.0 and the switch of one render
  step. The fog includes height fog.

- **Each plugin names the settings it reads.** The family's addons add
  `SettingsSlot.fog`, `volumetricFog`, `lightShafts` and `sky` to the
  renderer while on, so `RendererSteps.settings` lists them, and this
  library exports `SettingsSlot`. The types stay defined in
  `flutter3d_core`, which reads them as fields of `RenderSettings`.

- **The sky is a step.** `skyStep` is this package's own, switched by
  `SkySettings.enabled`. `SkyAddon` adds it to the renderer and provides
  it, and a frame without it reports `sky` as switched off.

- **Installing them changes nothing.** The kernel still draws the passes,
  with the settings it always had. Switching a plugin off withdraws its step
  from every frame, and `FrameResult.skipped` reports it as switched off.
  A renderer with no addon installed draws what it always drew.

- **The family's settings in one import.** `FogSettings`,
  `VolumetricFogSettings`, `LightShaftSettings`, `SkySettings` and
  `PhysicalSky` are exported here. They are still defined in
  `flutter3d_core`, so existing imports keep compiling.

### `motion.dart`, from `flutter3d_addon_motion` 1.0.0-rc.1

- **The motion family as plugins.** `DepthOfFieldAddon`, `MotionBlurAddon`
  and `TemporalAntiAliasingAddon`, all in `motionAddons`. Each is a view
  plugin on plugin API 1.0 and the switch of one render step.

- **Each plugin names the settings it reads.** The family's addons add
  `SettingsSlot.depthOfField`, `motionBlur` and `antiAlias` to the renderer
  while on, so `RendererSteps.settings` lists them, and this library exports
  `SettingsSlot`. The types stay defined in `flutter3d_core`, which reads
  them as fields of `RenderSettings`.

- **Installing them changes nothing.** The kernel still draws the passes,
  with the settings it always had. Switching a plugin off withdraws its step
  from every frame, and `FrameResult.skipped` reports it as switched off.
  A renderer with no addon installed draws what it always drew.

- **The family's settings in one import.** `DepthOfFieldSettings`,
  `MotionBlurSettings`, `TemporalSettings` and `TemporalClip` are exported
  here. They are still defined in `flutter3d_core`, so existing imports keep
  compiling.

### `style.dart`, from `flutter3d_addon_style` 1.0.0-rc.1

- **The style family as plugins.** `HighContrastAddon`, `OutlinesAddon` and
  `ViewportShadingAddon`, all in `styleAddons`. Each is a view plugin on
  plugin API 1.0 and the switch of one render step. The outlines depend on
  the look.

- **Toon lighting is this package's.** `toonLighting` is the model, and
  `ToonLightingAddon` registers it through `LightingModels` the way a
  third-party model is registered. It is the same constant as the kernel's
  `LightingModel.toon`, which stays built in for 1.x because the stages are
  still in every engine bundle: a material naming `Toon` draws with or
  without the addon.

- **Each plugin names the settings it reads.** `HighContrastAddon` and
  `ViewportShadingAddon` add `SettingsSlot.highContrast` and
  `SettingsSlot.viewportShading` to the renderer while on, and this library
  exports `SettingsSlot`.

- **The outlines are a step.** `outlinesStep` is this package's own,
  switched by `HighContrastSettings.outlineWidth` and needing
  `RenderStep.highContrast`. Off, the look stays and the rings go.

- **Installing them changes nothing.** The kernel still draws the passes,
  with the settings it always had. Switching a plugin off withdraws its step
  from every frame, and `FrameResult.skipped` reports it as switched off.
  A renderer with no addon installed draws what it always drew.

- **The family's settings in one import.** `HighContrastSettings`,
  `ViewportShading` and `ViewportShadingSettings` are exported here. They
  are still defined in `flutter3d_core`, so existing imports keep
  compiling.

### `standard.dart`, from `flutter3d_addons_standard` 1.0.0-rc.1

- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `ColourGradeAddon` is `ColorGradeAddon`. Only the Dart names
  changed: a file keeps the keys it was written with, and `dart fix`
  carries the renames.
- **The six post-processing families in one list.** `standardAddons` holds
  all twenty-two plugins of `flutter3d_addon_light`, `_shading`,
  `_reflections`, `_atmosphere`, `_motion` and `_style`, and this library
  exports all six.

- **Installing it changes nothing about the frame.** With the preset
  installed, the frame order fixture's 244 frames come out byte for byte the
  same as with no addon. What it adds is a switch for every effect.
