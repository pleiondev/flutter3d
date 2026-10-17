import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The platformer's simulation, by number: what a `.f3drun` and a network hello
/// carry so that a run or a peer on other rules is refused rather than
/// played wrong (ARCHITECTURE §9.4).
///
/// **A patch never changes it; a minor that changes the platformer's rules bumps
/// [SimulationVersion.genreVersion] here** — anything in [PlatformerSimulation] that moves
/// a body differently: the runner's jump, springs, water, crates. The engine's own number is
/// [SimulationVersion.engineVersion], bumped in `flutter3d_sim`, and both are
/// compared.
const SimulationVersion platformerSimulationVersion = SimulationVersion(
  genre: 'platformer',
);
