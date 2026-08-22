# flutter3d_ui

The screens a game has that are not the game: settings, volumes, rebinding,
credits, and where a save goes on each platform.

```dart
SettingsOverlay(
  settings: settingsCubit,
  mixer: audio.mixer,
  bindings: devices.bindings,
  config: config,
  padConnected: pad.isConnected,
  actions: myRebindableActions,
  defaultBindings: myKeys,
  opening: letGoOfTheGame,
)
```

**Extracted when the second game wanted it**, and what triggered it was
accessibility: rebinding a control is the accommodation that matters most, one
game had grown a panel for it, and the alternative was four hundred lines copied
into the next one.

What is deliberately not here is anything a particular game says. The credits are
a widget the caller hands in, the list of rebindable actions is the caller's, and
the panel has never known what a coin or a monster is.

## Storage

A save and a settings document are two small JSON files, kept where each
platform keeps such things — and on two of the four platforms the first version
was silently losing them, which looks exactly like a player who changed no
settings. `Storage` is where that is now decided once, per platform, in the
open.
