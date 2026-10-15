---
description: What the 1.0 line promises, what it is made of, and why a project on 0.8 should move to it, with the one command that does most of the moving.
---

# What 1.0 is, and why migrate

1.0 is the release I mean to keep. Everything before it was allowed to change shape between minors, and did; from 1.0.0 a break waits for a major, and the release candidates already keep that promise. If you have a project on 0.8, this page is the case for moving it, and the [migration guide](/reference/migrating-to-1.0/) is how.

## Two candidates, then 1.0.0

- **`1.0.0-rc.1`** is reliability and the shape of the API. Everything you can write against it is the 1.0 contract.
- **`1.0.0-rc.2`** is breadth on top of that contract: the viewer widget, text and sprites, video on a surface, the model hub's client, more lighting models, terrain, WebXR. Each of these adds to rc.1 and changes nothing in it.
- **1.0.0** follows rc.2, never rc.1. Between the two candidates a break is still allowed, with its migration; at 1.0.0 the contract freezes.

Until 1.0.0 is out, pub.dev's default version is 0.8.x, so ask for `^1.0.0-rc.1` by name. That constraint admits 1.0.0 when it follows.

## Strict semver, checked rather than promised

Every public name of every published package is in a committed snapshot under the package's `api/`, and CI compares the tree with it on every push. A name that changes without a major version fails the build. There is no "experimental" corner of the API that the promise leaves out: what is public is covered.

The command line is held the same way. `flutter3d help --surface` prints every subcommand, flag and `--json` key, `api/flutter3d_build.cli` commits that list, and the structure check fails when the two differ, because a CI script calling `flutter3d convert` compiles against nothing and would otherwise find out last.

The published packages, all but `pad_input` and `flutter3d_pointer_lock`, are at one version, `1.0.0-rc.1`, and move together at a minor or a major. A patch goes only to the package that needs it: `flutter3d_impeller` is already at `1.0.0-rc.1+1`, the same code with the shader bundle its sources compile to, and `flutter3d_webgpu` at `1.0.0-rc.1+1` asks the adapter for the binding limits a lit, instanced draw needs, and `flutter3d_physics` at `1.0.0-rc.1+1` lets a liquid retire particles that have come to rest, and `flutter3d_effects` at `1.0.0-rc.1+1` lets a game leave water out of the picture undrawn, and `flame_flutter3d` at `1.0.0-rc.1+1` lets a billboard stay out of the shadow maps. `^1.0.0-rc.1` picks each over its first upload. After 1.0.0 you may likewise see `flutter3d_impeller` at 1.0.1 beside the rest at 1.0.0, and every `^1.0.0` reaches it. [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md) has the version policy in full, and which platforms each backend is supported on.

## Four backends behind one HAL

The renderer is written against `flutter3d_hardware`, a hardware abstraction layer that names no graphics API, and four packages implement it: Impeller through Flutter GPU on a device, WebGPU and WebGL2 in a browser, and a software rasteriser in plain Dart. `flutter3d_app` picks one at run time and falls back down the list, with a banner when it does, so an application names none of them.

`flutter3d_conformance` is the suite each backend passes, and the golden scenes are drawn on all four and held to reference images. The software rasteriser is the one I trust most for that, because it shares no driver, shading language or command buffer with the others, and it is also why a widget test of your scene can draw a frame with no GPU at all. The [cookbook](https://github.com/pleiondev/flutter3d/tree/main/examples/cookbook) builds every recipe that way in CI.

## A run that happens the same way twice

The simulation steps at a fixed rate, in ordered phases, on arithmetic chosen to round the same way on every machine. A run is its inputs on a tape, and the tape replays it: the same steps, the same world digest at every checkpoint. That is what a bug report can be (send the tape, and a test reproduces it), what rollback netcode is built on, and what lets a server check a student's laboratory run by replaying it.

The C physics core is held to the same standard across compilers and targets; the parity table for it is one of the proofs on hardware the rc.1 tag waits for, with the number written down, and until it is in I am not claiming more than the Dart reference shows. A laboratory that wants accuracy over replay picks the `accurate` profile, which says so in its capabilities; a game and anything a server verifies stay on the deterministic one.

## An agent works on the same documents you do

The level editor and the model editor are MCP servers as well as applications, plain Dart over stdio: an agent's edits go through the same commands as a person's, land in the same undo history, and the model editor's `render` tool hands the agent a picture of what it did. Every package also ships agent skills (what its API is for, and the mistakes it has already paid for), which `dart run skills@ get` installs into your project. The [home page](/#an-agent-in-two-minutes) has the configuration.

## Moving takes one command

```bash
dart pub global activate flutter3d_build 1.0.0-rc.1
dart pub global activate flutter3d_lints 0.9.0
dart pub global run flutter3d_build:migrate --dry-run .
```

`migrate` moves your constraints to `^1.0.0-rc.1`, runs `dart fix` with the fix data every package ships, and applies the rewrites that need the resolved code. 1.0 changed the 0.8 API in many places, and the [migration guide](/reference/migrating-to-1.0/) counts them from the same table the tools read; what needs a decision from you gets a TODO with a link to its entry. Your levels, effects and recordings keep working without a step of their own, because 1.0 reads every older version of each format.

## Why now rather than at 1.0.0

Because rc.1 is the contract. What you migrate to today is what 1.0.0 will be, apart from additions, and a problem you hit on rc.1 is one I can still fix before it freezes. After 1.0.0, a fix that needs a break waits for 2.0.

- [Migrating from 0.8](/reference/migrating-to-1.0/): every change, and how each is carried out
- [Quickstart](/quickstart/): a new project on the candidate
- [What changed, by release](/changelog/)
