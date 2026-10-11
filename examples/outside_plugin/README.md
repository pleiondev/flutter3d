# A plugin from outside

A plugin written as somebody outside this repository would write one:
`package:flutter3d_plugin_api`, `package:flutter3d_fields`,
`package:flutter3d_sim` and `package:flutter3d_core`, every engine package
by path, and no `src/` import. The structure rule `an outside example
reaches only the published API` reads every file here and holds it to
that. Its namespace is `outside`, and every name it registers is in it.

`lib/outside_plugin.dart` is the whole plugin. Where two bodies press on
each other, the contact warms the air around it:

- **a field**, `outside.heat`: kelvin above the surroundings in a grid of
  8 by 4 by 8 cells half a metre across, held in host memory, written by
  the plugin's solver and read by the frame and by a sound;
- **a subsystem**, `outside.warming`, version 1: it lays down the heat the
  last step's contacts left, cools every cell towards the air and hands
  each body in the field its warmth. It declares what it reads and writes,
  and is switched on by a profile of the plugin's own, `outside.warming`;
- **the contact event**: under that profile the plugin hears every
  `ContactEvent` on the step channel and keeps its heat, in the loop's
  snapshots, for the next step;
- **a quantity on a body's material state**, `outside.warmth`, which a save,
  a snapshot and the wire carry with the body like the engine's own.

Under the default profile the solver is registered and runs nowhere, the
plugin hears nothing, and the simulation is the one without it, digest for
digest.

## Tests

```bash
flutter test
```

- `test/outside_plugin_test.dart` drops an oak ball on a granite floor
  and watches the warmth arrive in the field and in the ball's material
  state; rolls a run back and forward again; and draws the published field
  into a frame on the software rasteriser, as a 3D texture and as a
  storage buffer on the CPU executor.
- `test/conformance_test.dart` holds the plugin to the plugin suite of
  `flutter3d_conformance` under both profiles. Its backends check installs
  and steps the plugin on no backend and on each of the four by name, and
  the plugin earns the badge under both.
- `test/default_simulation_test.dart` plays a racing tape with the
  registries on and the plugin's solver registered and off, against the
  digests recorded on the tree before fields and subsystems existed.

## The four backends

The plugin suite is about the simulation and needs no device: it runs here,
on every backend by name. Where a field meets a device, the backends'
conformance suites hold each of them to the same two checks
(`fieldResidenceChecks` in `flutter3d_conformance`): a 3D texture of a
field's shape is made and written or refused with `DeviceFeature.texture3D`
named, and a field in a storage buffer reads back bit for bit.

- **CPU**: runs in this checkout, `packages/flutter3d_cpu/test/conformance_test.dart`,
  and the frame tests above draw the plugin's own field on it.
- **WebGL2** and **WebGPU**: their suites list the checks and run in Chrome
  (`flutter test --platform chrome test/conformance_test.dart` in each
  package), on the Mac with a browser that has the API.
- **Impeller**: its suite runs on the Mac through a Flutter GPU context only
  an application has, `packages/flutter3d/example/lib/conformance_main.dart`
  (`flutter run -d macos -t lib/conformance_main.dart`). flutter_gpu has no 3D textures, so the first check
  passes there by refusing one with `texture3D` named, and `FieldUpload`
  refuses the plugin's field the same way, as unsupported in the frame. A
  buffer field needs compute, which flutter_gpu does not have yet
  (flutter/flutter#188474), so the second is declined there and a buffer
  field goes to the wgpu sidecar or the CPU executor instead.
