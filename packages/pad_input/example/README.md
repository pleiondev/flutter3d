# pad_input_example

Every axis, every trigger and every button of a connected controller, live on one
screen, with the dead-zone sliders beside them.

```sh
mise exec -- flutter run -d <android device>   # where the native backend is
mise exec -- flutter run -d chrome             # the web backend
mise exec -- flutter run -d macos              # says there is no backend yet
```

## Why this exists, and why it is here rather than in a game

The tests of `packages/pad_input` cover everything above the platform channel:
the dead zone, the trigger's travel, the browser's mapping table, and Android's
choice of trigger axis. The specification says the rest can only be checked by
a person holding a controller: whether half a deflection gives half the input,
whether letting go stops dead, whether the dead zone should be bigger, and
whether going to the background releases everything. This screen is for going
through that list, which takes about a minute.

It lives in the package and not in one of the three games because the games
have no Android runner and no on-screen controls, and because the thing being
checked here is the device, not the game.

## Building for Android

The repository pins a JDK in `.mise.toml` because of this project. The Android
Gradle Plugin's `core-for-system-modules` transform runs
`jlink --disable-plugin system-modules`, which a JDK 26 refuses, and the
resulting error names neither Java nor the transform. `mise exec --` applies
the pin.
