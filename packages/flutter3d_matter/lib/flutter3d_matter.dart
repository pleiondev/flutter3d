/// What a world and the things in it are made of, with nothing that moves
/// them.
///
/// * [WorldProperties]: a world's gravity, its air, its wind and the medium
///   things move through, with the defaults a world nobody configured starts
///   with ([standardGravity], [standardAtmosphere], [standardAirTemperature]
///   and the rest, in `standard_world.dart`) and the laws that derive the air
///   from them ([airDensityAt], [speedOfSoundAt]);
/// * [PhysicalMaterial]: one substance's mechanical, fluid, thermal,
///   acoustic, optical and electrical properties, each group citing its
///   source, and the [MaterialPair]s measured between two of them;
/// * [MaterialCatalog]: the materials an engine knows by id, the engine's
///   own ([Materials], `f3d.*`) and its plugins'; and
/// * the constants of nature the engine uses ([stefanBoltzmann],
///   [molarGasConstant] and the rest).
///
/// **Its own package, below the physics, because more than the physics reads
/// it.** The audio reckons a Doppler shift against the world's speed of
/// sound, the particles fall by its gravity and drift on its wind, and the
/// native core's C header is generated from the catalogue. None of them
/// steps a body, and none of them should need the collision world to know
/// what the air is. `flutter3d_physics` re-exports this library while the
/// packages that read it through the physics move to it.
///
/// `docs/CONTRACTS.md` ("World properties", "Physical materials") gives the
/// unit of every number here.
library;

export 'src/materials/material_catalog.dart';
export 'src/materials/material_json.dart' show MaterialFormatException;
export 'src/materials/material_sections.dart';
export 'src/materials/materials.dart';
export 'src/materials/physical_material.dart';
export 'src/materials/property_groups.dart';
export 'src/physical_constants.dart';
export 'src/standard_world.dart';
export 'src/world_properties.dart';
