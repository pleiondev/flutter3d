# flutter3d_fields

Fields and subsystems for flutter3d: one contract for a 3D grid of
quantities that the simulation, the renderer and audio share, and for a
solver that says what it reads and writes before it runs.

```dart
import 'package:flutter3d_fields/flutter3d_fields.dart';

const heat = FieldDeclaration(
  id: 'acme.heat',
  quantity: 'f3d.temperature',
  unit: Unit.kelvin,
  grid: FieldGrid(32, 8, 32),
  transform: FieldTransform(origin: WorldPosition(-8, 0, -8), cellSize: 0.5),
  writer: FieldAccess.simulation('acme.diffuse'),
  readers: <FieldAccess>[FieldAccess.frame('acme.shimmer')],
);

final class Diffuse extends Subsystem {
  @override
  SubsystemDeclaration get declaration => const SubsystemDeclaration(
    id: 'acme.diffuse',
    version: 1,
    writesFields: <String>['acme.heat'],
    readsQuantities: <String>['f3d.temperature'],
  );

  @override
  void step(SubsystemContext context) {
    final heat = context.field('acme.heat');
    // … one fixed step of diffusion over heat.values
  }
}

// In a plugin's install:
host.registry<FieldRegistry>().declare(heat);
host.registry<SubsystemRegistry>().register(Diffuse());
```

## A field

A `FieldDeclaration` says, before anything writes a value:

- **what every cell holds**: a quantity by its namespaced id, as a body's
  material state names one (`f3d.temperature`, `<pluginId>.charring`), in a
  `Unit` from `flutter3d_foundation`;
- **where it stands**: a `FieldGrid` (cells along each axis, values per
  cell) and a `FieldTransform` (the middle of the first cell as a world
  position, and the cell size), so a field kilometres from the origin keeps
  its cells where they are when the floating origin moves;
- **where its values are held**: `FieldResidence.host` (a `HostField`, a
  `Float32List` every machine has), `buffer` (a storage buffer on a device
  that runs compute) or `texture3D` (a 3D texture a stage samples). The
  set is open;
- **who writes it and who reads it**: one writer and any number of readers,
  each a step on a `FieldSide` (`simulation`, `frame`, `audio`) by name.

A host field is the simulation's: the loop makes its values, puts it in
its snapshots once a running subsystem writes it, and publishes a copy at
the end of every step for the frame and for audio. A field on a device is
the frame's: the renderer's core holds it under its id as a frame-graph
resource, placed where the compute step that writes it runs, and a device
without what the residence needs (`DeviceFeature.texture3D` for a 3D
texture) refuses it with a `FieldResidenceException` naming the feature.

## A subsystem

A solver is a `Subsystem` with a `SubsystemDeclaration`: its id and
version, the quantities and fields it reads and writes, its phase (the
world's `fields` phase unless it says otherwise) and its place among the
phase's systems, and the profiles that switch it on.

- **It is handed only what it declared.** `SubsystemContext.field` answers
  a field it writes, and a read-only view of one it reads; anything else is
  a `StateError`. A later simulation-graph checker reads the same
  declarations.
- **The simulation's version is composed from the running ones.**
  `SimulationVersion.subsystems` names each by id at its version, so a run
  recorded with a solver on is refused where it is off.
- **A solver a minor adds is switched on by a profile.** Declared with
  `switchedOnBy`, it is registered under every profile and runs under the
  ones it names. The default simulation, its tapes and its matches stay as
  they were, and `examples/outside_plugin` holds the racing tape's digest
  to that.

## Its own version

This package has a version of its own, as `flutter3d_plugin_api` and
`flutter3d_hardware` have: the seam grows by additions faster than the
engine does. It is plain Dart over the plugin contract and the foundation,
and names nothing that draws, so the simulation can implement it.
