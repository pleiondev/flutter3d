## 1.0.0-rc.1

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
