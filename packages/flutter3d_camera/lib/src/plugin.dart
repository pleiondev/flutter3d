import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'director.dart';
import 'shake.dart';

/// What one rule of an [ImpulseTable] makes of an event of type [T]: the
/// impulse it shakes the view with, or null for none.
typedef ImpulseRule<T extends BusEvent> = CameraImpulse? Function(T event);

/// Impulses keyed by event type: which events shake the view, and how.
///
/// A rule is registered for an event class and handed every event of that
/// class and its subclasses; every rule that answers adds its impulse, in
/// registration order.
///
/// ```dart
/// final impulses = ImpulseTable()
///   ..on<Exploded>((e) => CameraImpulse(amplitude: 0.4, at: e.at))
///   ..on<Landed>((e) => e.hard ? const CameraImpulse(amplitude: 0.1) : null);
/// ```
final class ImpulseTable {
  final List<(Type, ImpulseRule<BusEvent>)> _rows =
      <(Type, ImpulseRule<BusEvent>)>[];

  /// Adds [rule] for every event that is a [T].
  void on<T extends BusEvent>(ImpulseRule<T> rule) {
    _rows.add((T, (BusEvent event) => event is T ? rule(event) : null));
  }

  /// The event types this table has a rule for, in registration order.
  List<Type> get types => <Type>[for (final row in _rows) row.$1];

  /// Every impulse [event] shakes the view with.
  List<CameraImpulse> impulsesFor(BusEvent event) => <CameraImpulse>[
    for (final row in _rows) ?row.$2(event),
  ];
}

/// A [CameraDirector] run by the engine's loop: placed in the frame phase
/// `camera`, and shaken by the bus.
///
/// **A view plugin.** It adds one system to `LoopPhase.camera`, which runs
/// once a displayed frame after the frame's steps, the animation and the
/// sound, and before the frame is drawn — the order a camera needs: the
/// things it follows have moved, and the renderer has not yet asked where
/// to look. It hears every event on the frame channel and shakes the view
/// with what [impulses] makes of them. Nothing it does reaches the
/// simulation, so switching it off is not written into a replay.
///
/// **A rollback shakes nothing twice.** An event the frame channel hands out
/// again, marked resimulated, already shook the view the first time; it is
/// skipped unless [shakeCorrections] is set.
///
/// **The shake is seeded by the step that published the event**, through
/// `ImpulseShake`, so a replay shakes the way the run did.
///
/// ```dart
/// final director = CameraDirector()..add(VirtualCamera('chase', chase));
/// final loop = EngineLoop(
///   input: input,
///   plugins: [genre, CameraPlugin(director, impulses: table)],
/// );
/// // every frame, after the loop's frame phases:
/// node..setPositionFrom(director.shot.eye)..lookAt(director.shot.target);
/// ```
final class CameraPlugin extends Flutter3dPlugin {
  /// Runs [director] in the loop, shaken by [impulses].
  CameraPlugin(
    this.director, {
    ImpulseTable? impulses,
    this.id = 'flutter3d_addon_camera',
    this.realTime = false,
    this.shakeCorrections = false,
  }) : impulses = impulses ?? ImpulseTable();

  /// The cameras.
  final CameraDirector director;

  /// Which events shake the view.
  final ImpulseTable impulses;

  /// The plugin's id. Two directors in one engine — a split screen — need
  /// two.
  final String id;

  /// Whether the cameras move by the wall clock rather than by simulated
  /// time.
  ///
  /// Off by default, so a paused game's view holds still and a slowed one
  /// eases slowly. On for a camera that must keep moving while the world is
  /// paused — a menu flying over the level.
  final bool realTime;

  /// Whether an event a rollback changed shakes the view when it arrives
  /// again.
  final bool shakeCorrections;

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: const PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description:
        'Virtual cameras with priorities and blends, placed in the camera '
        'phase and shaken by events.',
  );

  @override
  void install(PluginHost host) {
    host.loop.addSystem(
      '$id.place',
      LoopPhase.camera,
      (LoopContext context) =>
          director.update(realTime ? context.realDt : context.dt),
    );
    host.events.onFrame<BusEvent>('$id.impulses', (Delivered<BusEvent> d) {
      if (d.resimulated && !shakeCorrections) return;
      for (final impulse in impulses.impulsesFor(d.event)) {
        director.impulse(impulse, step: d.step, sequence: d.sequence);
      }
    });
  }

  @override
  void uninstall(PluginHost host) => director.shake.clear();
}
