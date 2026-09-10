---
name: flutter3d-screens-settings-and-saves
description: Use when a flutter3d game needs settings, volumes, control rebinding or credits, or when deciding where a save and a settings document live per platform.
---

# The screens that are not the game

```dart
SettingsOverlay(
  settings: settingsCubit,
  mixer: audio.mixer,
  bindings: devices.bindings,
  config: config,
  padConnected: pad.isConnected,
  actions: myRebindableActions,     // the game's own list
  defaultBindings: myKeys,
  opening: letGoOfTheGame,          // release pointer lock, pause, …
  credits: MyCredits(),             // optional, and the game's widget
)
```

Everything a particular game says is passed in: the credits are a widget, the
rebindable actions are the caller's, and the panel has never known what a coin
or a monster is. Keep it that way — a name from one game here is a name every
other game carries.

**Rebinding is the accommodation that matters most**, so treat it as a
requirement rather than a setting. `Rebinding` and `ownedBindings` are the model
behind it, `PadPresses` drives a menu from a gamepad, and `DragLook` and
`configureForTouch` make the same screens usable on a phone. `AutomapView`,
`clockText`, `TapToRestart` and the status screens (`LoadingScreen`,
`RendererFailure`, `LevelLoadFailed`) are the small pieces games kept rewriting.

## Storage

A save and a settings document are two small JSON files kept where each platform
keeps such things: `FileStorage` on native, `WebStorage` in a browser, behind
one `Storage` interface.

**On two of the four platforms the first version was silently losing them**,
which looks exactly like a player who changed no settings and reported nothing.
So the directory per platform is decided here, once. When adding a platform, add
it here rather than at a call site, and write the test that reads back what was
written.

`SaveFile`, `SettingsFile` and `DemoFile` are the three documents. The settings
document is shared live with the input layer on purpose — `SettingsCubit` holds
the same `config` the bindings read — so a rebind takes effect without a round
trip through a file.
