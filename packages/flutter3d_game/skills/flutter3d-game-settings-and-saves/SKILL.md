---
name: flutter3d-game-settings-and-saves
description: Use when a flutter3d game needs settings, volumes, control rebinding or credits, or when deciding where a save and a settings document live per platform.
---

# The screens that are not the game

```dart
SettingsOverlay(
  settings: gameSettings,           // a GameSettingsController, a ValueListenable
  sections: SettingsSection.standard(
    padConnected: pad.isConnected,
    defaultActions: myActionMap,    // the game's ActionSet decides what rebinds
    credits: MyCredits(),           // optional, and the game's widget
  ),
  opening: letGoOfTheGame,          // release pointer lock, pause, …
)
```

The panel is a list of `SettingsSection`s: `standard` is what every game had,
and a game drops, reorders or adds one of its own by extending the class.
Everything a particular game says is passed in: the credits are a widget, the
rebindable actions are the ones its `ActionSet` declares rebindable, and the panel has never known what a coin
or a monster is. Keep it that way — a name from one game here is a name every
other game carries.

**Rebinding is the accommodation that matters most**, so treat it as a
requirement rather than a setting. `Rebinding` and the controller's `actions`
are the model behind it — one `ActionMap`, read by `DesktopInput` and
`PadInput` and saved by the controller on every change — `PadPresses` drives a menu from a gamepad, and `DragLook` and
`lockLandscapeForTouch` make the same screens usable on a phone. The words
on these screens come from `Flutter3dGameLocalizations` (English and Russian;
add its `delegate` to the app) and the colours from `GameUiTheme`. `AutomapView`,
`clockText` and `TapToRestart` are the small pieces games kept rewriting. The
status screens (`LoadingScreen`, `RendererFailure`, `LevelLoadFailed`) are
`flutter3d_app`'s, because an application that is not a game loads and fails
the same way.

## Storage

A save and a settings document are two small JSON files kept through
`flutter3d_app`'s `Storage`: `FileStorage` on native, `WebStorage` in a browser.
`Storage` is asynchronous and a refused write throws `StorageException`; read
the settings in `main()` before `runApp` so the first key press uses them.
`SaveSlots` holds several runs, each a `SaveFile`; the default slot is
`save.json`, as it always was.

**On two of the four platforms the first version was silently losing them**,
which looks exactly like a player who changed no settings and reported nothing.
So the directory per platform is decided in `flutter3d_app`, once. When adding a
platform, add it there rather than at a call site, and write the test that reads
back what was written.

`SaveFile`, `SettingsFile` and `DemoFile` are the three documents.
`GameSettings` is a value — a volume per `AudioBus`, typed `SettingKey`s under
namespaced ids (`GameSettingKeys` for the engine's, `mygame.<name>` for a
game's), the player's action map — and every change is a copy the controller
hands to the game's `apply` and writes in the format envelope (`f3d.settings`).
The action map is the one live object: the devices read the controller's
`actions`, so a rebind takes effect without a round trip through a file.
