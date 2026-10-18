## 1.0.0-rc.1

- **New: fields, as a contract of their own.** A `FieldDeclaration` names a
  3D grid of one quantity (a namespaced id, as a body's material state names
  one, in a `Unit`), its `FieldGrid` and `FieldTransform` in world
  positions, where its values are held (`FieldResidence`: `host`, `buffer`,
  `texture3D`, an open set), the one step that writes it and the steps that
  read it (`FieldAccess` on a `FieldSide`: `simulation`, `frame`, `audio`).
  `HostField` holds a host field's values in a `Float32List`, samples it
  between cells and is a snapshot part of its own. A field a device cannot
  hold is refused with `FieldResidenceException` and an open `FieldRefusal`.
- **New: subsystems.** A solver registers as a `Subsystem` with its
  `SubsystemDeclaration`: id and version, the quantities and fields it reads
  and writes, its phase and place in the step, and the profiles that switch
  it on (`switchedOnBy`). `SubsystemContext` hands it the fields it
  declared, read-only where it only reads. `FieldRegistry` and
  `SubsystemRegistry` are what the engine implements and a plugin reaches
  through its host; the simulation's version is composed from the running
  subsystems (`SimulationVersion.subsystems`).
