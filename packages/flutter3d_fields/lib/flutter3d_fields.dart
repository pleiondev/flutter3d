/// Fields and subsystems: the contract for a 3D grid of quantities that the
/// simulation, the renderer and audio share, and for a solver that says what
/// it reads and writes.
///
/// **A field** is a [FieldDeclaration] first: the quantity every cell holds
/// and its unit, the grid and where it stands in the world, where its values
/// are held ([FieldResidence]: host memory, a device's buffer, a 3D
/// texture), the one step that writes it and the steps that read it. A
/// host field's values are a [HostField]; a field on a device is the
/// renderer's core's to make, through the compute placement of the step that
/// writes it, and a device without what the residence needs refuses it with
/// a [FieldResidenceException].
///
/// **A subsystem** is a solver registered with its [SubsystemDeclaration]:
/// its id and version, the quantities and fields it reads and writes, its
/// place in the step and the profiles that switch it on. The simulation's
/// version is composed from the running ones, so a solver a minor adds and
/// switches on through a profile leaves the default simulation, its tapes
/// and its matches alone.
///
/// The engine implements [FieldRegistry] and [SubsystemRegistry]
/// (`flutter3d_sim`'s loop); a plugin reaches them through its host.
library;

export 'src/field.dart'
    show
        FieldAccess,
        FieldCoordinate,
        FieldDeclaration,
        FieldGrid,
        FieldResidence,
        FieldSide,
        FieldTransform;
export 'src/field_refusal.dart' show FieldRefusal, FieldResidenceException;
export 'src/field_registry.dart' show FieldRegistry;
export 'src/host_field.dart' show FieldStorage, HostField;
export 'src/subsystem.dart'
    show Subsystem, SubsystemContext, SubsystemDeclaration, SubsystemRegistry;
