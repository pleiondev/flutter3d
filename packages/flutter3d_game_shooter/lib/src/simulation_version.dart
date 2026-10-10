import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The shooter's simulation, by number: what a `.f3drun` and a network hello
/// carry so that a run or a peer on other rules is refused rather than
/// played wrong (ARCHITECTURE §9.4).
///
/// **A patch never changes it; a minor that changes the shooter's rules bumps
/// [SimulationVersion.genreVersion] here** — anything in [GameSimulation] that moves
/// a body differently: the monsters, combat, projectiles and the step order. The engine's own number is
/// [SimulationVersion.engineVersion], bumped in `flutter3d_sim`, and both are
/// compared.
const SimulationVersion shooterSimulationVersion = SimulationVersion(
  genre: 'shooter',
);
