/// The twin's simulation: a site's air, measured, and a tank of water on it,
/// modelled.
library;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// A site whose air temperature comes from a real source and a tank of water
/// standing in it, whose temperature the model works out: what a twin is,
/// at its smallest.
///
/// **Two entities, each a body with a material state** (`f3d.temperature`)
/// and a [Probe] on it, so what the view shows is what the probes publish
/// (`PublishedState.probes`) and nothing reads the world from outside.
///
/// * **The air is measured.** Readings from [airSource] enter as input
///   (`ExternalStateInput`), and an assimilation in the input phase sets the
///   air to the latest one a source trusts; a reading its source calls
///   [ReadingQuality.bad] is passed over, and the air keeps what it was.
/// * **The tank is modelled.** Between readings, and through them, the water
///   relaxes towards the air with a [timeConstant] (Newton's law of cooling:
///   dT/dt = (T_air − T_water) / τ), stepped in the fields phase.
///
/// **The readings are input, so the history is a tape.** [install] takes
/// them from [readings] at the start of every live step and feeds them
/// into the step's input; the loop records them with the step, and
/// [keepHistory] keeps the tape and the keyframes a `RunTimeline` scrubs.
final class SiteTwin {
  SiteTwin._(this.loop, this.air, this.tank, this._registrations);

  /// The name readings of the air's temperature arrive under.
  static const String airSource = 'site.air.temperature';

  /// The probe on the air, in °C.
  static const String airProbe = 'site.air';

  /// The probe on the tank's water, in °C.
  static const String waterProbe = 'tank.water';

  /// Steps a second: ten, since nothing on the site moves faster than air
  /// warms.
  static const double stepRate = 10;

  /// How long the water takes to close all but 1/e of a gap to the air, in
  /// seconds of simulated time: ten minutes, for a small tank in the open.
  static const double timeConstant = 600;

  /// What both stand at before the first reading, in °C.
  static const double startCelsius = 15;

  /// Puts the site into [loop]: the air and the tank with their probes, the
  /// assimilation that hears [airSource], the model, and [readings] asked
  /// at the start of every live step.
  factory SiteTwin.install(
    EngineLoop loop, {
    required List<ExternalStateInput> Function() readings,
  }) {
    final world = loop.world;
    Entity body(String probe) {
      final entity = world.spawn();
      world
        ..set<MaterialStateComponent>(
          entity,
          MaterialStateComponent(
            MaterialState.at(
              temperature: const Quantity(
                startCelsius,
                Unit.celsius,
              ).valueIn(Unit.kelvin),
            ),
          ),
        )
        ..set<Probe>(
          entity,
          Probe(
            id: probe,
            quantity: MaterialState.temperatureId,
            unit: Unit.celsius,
          ),
        );
      return entity;
    }

    final air = body(airProbe);
    final tank = body(waterProbe);
    double kelvin(Entity entity) =>
        world.get<MaterialStateComponent>(entity)!.state.temperature;
    void warm(Entity entity, double kelvin) =>
        world.set<MaterialStateComponent>(
          entity,
          MaterialStateComponent(
            world
                .get<MaterialStateComponent>(entity)!
                .state
                .withQuantity(
                  MaterialState.temperatureId,
                  Quantity(kelvin, Unit.kelvin),
                ),
          ),
        );

    return SiteTwin._(loop, air, tank, <Registration>[
      loop.onStepInput((InputState input) {
        for (final reading in readings()) {
          input.feedExternal(reading);
        }
      }),
      loop.addAssimilation(
        'twin.air',
        Assimilation.of((AssimilationContext context) {
          for (final reading in context.from(airSource)) {
            if (reading.quality == ReadingQuality.bad) continue;
            warm(air, reading.quantity.valueIn(Unit.kelvin));
          }
        }),
      ),
      loop.addSystem('twin.tank', LoopPhase.fields, (LoopContext context) {
        final water = kelvin(tank);
        warm(tank, water + (kelvin(air) - water) * context.dt / timeConstant);
      }),
    ]);
  }

  /// The loop the site is in.
  final EngineLoop loop;

  /// The air above the site.
  final Entity air;

  /// The tank of water standing in it.
  final Entity tank;

  final List<Registration> _registrations;

  /// A buffer of the last [seconds] of the site, attached to [loop]: the
  /// tape of every step's readings and a keyframe every [keyframeEvery]
  /// steps, which a `RunTimeline` scrubs.
  RewindBuffer keepHistory({double seconds = 600, int keyframeEvery = 100}) {
    final buffer = RewindBuffer(
      stepsPerSecond: stepRate.round(),
      history: seconds,
      keyframeEvery: keyframeEvery,
    );
    _registrations.add(buffer.attach(loop));
    return buffer;
  }

  /// Takes the site's hooks out of [loop]; the entities stay.
  void dispose() {
    for (final registration in _registrations.reversed) {
      registration.cancel();
    }
    _registrations.clear();
  }
}
