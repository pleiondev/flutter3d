---
name: flutter3d-import-layers
description: Use before adding an import or a dependency in this workspace — the boundaries between the engine, the hardware layer, the backends, the simulation and the genre packages are checked by scans, not by review.
---

# What each layer is allowed to name

These are not style preferences. Every one of them is a claim somebody can act
on — an application picks a backend, a server runs the simulation, a new game
starts from a genre template — and a claim nothing checks is a claim that has
already stopped being true somewhere. `dart run tool/structure.dart` checks
them, in under a second, before anything is built.

## The engine chooses no backend

`packages/flutter3d` must not know `flutter_gpu` exists: not in an import in
`lib/`, and not in its pubspec, where depending on a backend and reaching it
through the umbrella library would name nothing textually and still weld the
engine to one. Whatever the engine needs belongs on `GraphicsDevice` or
`CommandEncoder`.

The rule has a second half that is easy to miss: `flutter3d` must keep depending
on `flutter3d_hardware`. An engine written against nothing makes both checks
above vacuous.

## The hardware layer names no graphics API

`packages/flutter3d_hardware` is the vocabulary a backend answers in, and it is
its own. No `flutter_gpu`, and — for all but a named few files — no `dart:ui`
and no `package:flutter/`. `dart:ui` and `package:flutter/` are held together
deliberately, because widgets re-export half of `dart:ui` and naming one without
the other is a rule with a door in it. If something is genuinely a thing every
backend must answer, it goes in `hardwareMayUseFlutter` with the reason.

Backends depend on the hardware layer. Never the other way.

## The simulation names no Flutter

`packages/flutter3d_sim` is what a server runs in a container with no Flutter
SDK. One `package:flutter/foundation.dart` for one `debugPrint` puts a Flutter
SDK on the critical path of the whole service, and it does so silently:
everything still builds, every test still passes, and the failure arrives months
later as a container that will not start.

`lib/`, `test/` and `bin/` are all scanned. A suite that needs `flutter_test` to
run is a suite CI can only run through Flutter, and then "this package stands
alone" is true of the library and false of the thing anybody executes. Whatever
wants Flutter belongs in `flutter3d_game`.

## A genre is a package, and reaches no other genre

What only a shooter wants lives in `flutter3d_game_shooter`, so a platformer
inherits none of its vocabulary. No `flutter3d*` package may name a genre at
all, and no genre may name a sideways neighbour. A genre camera turns the
shared rig rather than growing its own.

## The rest of the family

No package depends on an application. Nothing shares a mutable value as a
`const`. A step reaches for no clock and no loose dice. An assembly has one home
per application, and no test builds its own world.

## When a rule is wrong for what you are doing

The exemption tables in `tool/structure/repository.dart` take an entry with a
reason. The reason is the point — it is what lets the next reader tell a
considered exception from a rule somebody silenced. Reaching for one should feel
like a decision, because it is.
