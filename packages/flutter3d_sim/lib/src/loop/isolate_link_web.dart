import 'isolate_link.dart';
import 'isolate_simulation.dart';
import 'simulation_handle.dart';

/// A browser has no isolate a package can spawn.
const bool isolatesRun = false;

/// Refuses: in a browser the simulation runs on the page's own thread,
/// built from the same factory with `SimulationSetup.local`.
Future<IsolateLink> openIsolateLink(
  SimulationFactory factory,
  Object? arguments, {
  required bool ownsClock,
  String? debugName,
}) => Future<IsolateLink>.error(
  const SimulationCapabilityException(
    'a browser has no isolate a package can spawn, so the simulation cannot '
    'run in one; build it here from the same factory, '
    'factory(arguments).local(), and check IsolateSimulation.isSupported '
    'first',
  ),
);
