# The cookbook

Twenty tasks an application on flutter3d writes, one file each, forty lines
of code or fewer. Each file is a whole program: its `main` runs it, and the
widget it runs is what you copy.

```bash
cd examples/cookbook
flutter run -d macos -t lib/load_and_orbit.dart
```

| Task | File |
|---|---|
| Load a glTF and orbit it | [`load_and_orbit.dart`](lib/load_and_orbit.dart) |
| A GLB on a product page, with a buy button | [`buy_button.dart`](lib/buy_button.dart) |
| Play a model's clip, and switch to another | [`play_a_clip.dart`](lib/play_a_clip.dart) |
| Something in its place while a model loads | [`placeholder_while_loading.dart`](lib/placeholder_while_loading.dart) |
| Decode models off the page in a browser | [`decode_in_a_worker.dart`](lib/decode_in_a_worker.dart) |
| Turn a shape every frame | [`spin_a_shape.dart`](lib/spin_a_shape.dart) |
| The same scene built by hand, without widgets | [`scene_without_widgets.dart`](lib/scene_without_widgets.dart) |
| Tap a shape to pick it | [`tap_to_pick.dart`](lib/tap_to_pick.dart) |
| What roughness and metal do | [`material_ladder.dart`](lib/material_ladder.dart) |
| The sun and the shadows it casts | [`sun_and_shadow.dart`](lib/sun_and_shadow.dart) |
| A glowing sign | [`glowing_sign.dart`](lib/glowing_sign.dart) |
| A campfire of particles | [`campfire.dart`](lib/campfire.dart) |
| An orbit camera that follows a ball | [`follow_a_ball.dart`](lib/follow_a_ball.dart) |
| A runner at 60 fps on a phone | [`runner_at_60.dart`](lib/runner_at_60.dart) |
| Scenes in a scrolling list | [`scenes_in_a_list.dart`](lib/scenes_in_a_list.dart) |
| A level with physics | [`falling_crates.dart`](lib/falling_crates.dart) |
| A pendulum with a length slider | [`pendulum_slider.dart`](lib/pendulum_slider.dart) |
| Read a probe | [`read_a_probe.dart`](lib/read_a_probe.dart) |
| A twin fed by REST | [`twin_over_rest.dart`](lib/twin_over_rest.dart) |
| Run the whole scene ten times faster | [`ten_times_faster.dart`](lib/ten_times_faster.dart) |

## How it is held

`test/cookbook_test.dart` builds every recipe in a widget test and checks
that a frame of it reached the screen. A test has no Impeller, so the view
opens the software rasteriser, which is the same fallback an application
takes when Impeller will not start. The same test counts each file's lines
of code (blank lines and comments left out) and fails at 41, and fails when
a file is added to `lib/` without a line in its table. `tool/ci.sh` runs it
with the other examples, and the root `analyze` step reads every recipe.

A test answers every HTTP request with status 400, so the twin's test sees
its source fail and keep the colour it started with, which is the case the
recipe is written for.

## The models

The recipes load `assets_src/models/RobotExpressive.glb` (CC0, see
[`ATTRIBUTION.md`](assets_src/models/ATTRIBUTION.md)) by its path, as a
project of yours names a model. In your project, `dart run
flutter3d_build:init` wires the build hook that converts everything under
`assets_src/` into `flutter3d_generated/` on every build. This directory has
no hook, so a debug run and the test decode the source directly and print a
line saying so; a release build of a recipe would need the hook first.

## Arriving with 1.0.0-rc.2

These need API that rc.2 adds, so they are not here yet. Each lands with
the release that brings what it uses, held by the same test:

- A model viewer in one widget, with its own camera, lights and loading
  state (the viewer widget).
- A model named by its reference on models.pleion.dev rather than bundled.
  The recipes above move to hub references then.
- A label that faces the camera over a model (text and billboards).
- A video on a screen in the scene (external textures).
