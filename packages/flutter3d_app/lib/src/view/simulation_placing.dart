/// How a `Flutter3dView` puts its simulation where [SimulationPlacement]
/// says. Not exported: the view's own, with the platform's answer to "can
/// an isolate be spawned here" a parameter, so both answers are tested on
/// one machine.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        EngineLoop,
        IsolateSimulation,
        LocalSimulation,
        SimulationHandle,
        SimulationSetup;

import 'view_settings.dart';

/// A simulation where it was placed: the handle the view and the game read,
/// how the view steps it by a frame's seconds, and how it is let go.
final class PlacedSimulation {
  PlacedSimulation._(this.handle, this._advance, this._dispose);

  /// What the game submits to and the view reads published state from.
  final SimulationHandle handle;

  final void Function(double seconds)? _advance;
  final Future<void> Function() _dispose;

  /// Steps the simulation by [seconds] of a frame, when it runs apart from
  /// the view's loop; the view's own loop is stepped by the view itself.
  void advance(double seconds) => _advance?.call(seconds);

  /// Lets the simulation go: the isolate is stopped, the handle's
  /// registrations on a loop cancelled.
  Future<void> dispose() => _dispose();
}

/// The simulation [placement] asks for, beside [loop], the view's own.
///
/// [isolates] says whether this platform can spawn one: false in a browser,
/// where an isolate placement builds its setup here and the view steps it.
Future<PlacedSimulation> placeSimulation(
  SimulationPlacement placement,
  EngineLoop loop, {
  required bool isolates,
}) async {
  final factory = placement.factory;
  if (factory == null) {
    final apply = placement.applyInput;
    final local = LocalSimulation(
      loop,
      applyInput: (int seat, Object? input) =>
          apply?.call(SeatInput(seat: seat, input: input)),
    );
    return PlacedSimulation._(local, null, local.dispose);
  }
  if (isolates) {
    final apart = await IsolateSimulation.open(
      factory,
      arguments: placement.arguments,
      ownsClock: false,
      debugName: placement.debugName,
    );
    return PlacedSimulation._(apart, apart.advance, apart.dispose);
  }
  final SimulationSetup setup = factory(placement.arguments);
  final here = setup.local();
  return PlacedSimulation._(
    here,
    (double seconds) => setup.loop.frame(seconds),
    here.dispose,
  );
}
