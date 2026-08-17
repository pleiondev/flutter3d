# gamepad_example

Every axis, every trigger and every button of a connected controller, live on one
screen, with the dead-zone sliders beside them.

```sh
mise exec -- flutter run -d <android device>   # where the native backend is
mise exec -- flutter run -d chrome             # the web backend
mise exec -- flutter run -d macos              # says there is no backend yet
```

## Why this exists, and why it is here rather than in a game

`packages/gamepad`'s own tests cover everything above the platform channel — the
dead zone, the trigger's travel, the browser's mapping table, Android's choice of
trigger axis. The specification is explicit that the rest can only be checked by
a person holding a controller: whether half a deflection is half a wish, whether
letting go stops dead, whether the dead zone wants to be bigger, whether going to
the background lets go of everything. This is the screen for walking that list,
and it takes about a minute.

It lives in the package rather than in one of the three games because the games
have no Android runner and no on-screen controls — and because what is being
checked here is the device, not the game.

## Building for Android

The repository pins a JDK in `.mise.toml`, and this project is the reason: the
Android Gradle Plugin's `core-for-system-modules` transform runs
`jlink --disable-plugin system-modules`, which a JDK 26 refuses, and the error it
produces names neither Java nor the transform. `mise exec --` is what applies the
pin.
