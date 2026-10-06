import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'core/load.dart';
import 'native_dynamics.dart';
import 'native_world.dart';

/// The backend a build asks for: `--dart-define=FLUTTER3D_PHYSICS=dart`
/// runs on the Dart reference, anything else on the core. What a game
/// passes to [startPhysics] unless it has its own reason.
const String askedPhysics = String.fromEnvironment(
  'FLUTTER3D_PHYSICS',
  defaultValue: 'native',
);

/// The physics core as a [PhysicsBackend]: every world's bodies, character
/// moves and rays on it, through a [NativeDynamics] per world.
final class NativePhysics implements PhysicsBackend {
  NativePhysics();

  @override
  String get name => 'native';

  /// What [attach] made for each world, so [release] can let it go.
  final Expando<NativeDynamics> _attached = Expando<NativeDynamics>(
    'the core attached to a world',
  );

  /// Takes over from what [attach] gave [world], if anything did: one
  /// core world per collision world.
  @override
  RigidDynamics dynamics(CollisionWorld world, {Vector3? gravity}) {
    _attached[world]?.dispose();
    _attached[world] = null;
    return NativeDynamics(
      world: world,
      gravity: gravity,
      movesCharacters: true,
      castsRays: true,
    );
  }

  /// A [NativeDynamics] with no bodies, for its mover and rays: mirrored at
  /// the end of every `CollisionWorld.update`, never stepped.
  @override
  void attach(CollisionWorld world) {
    if (_attached[world] != null || world.characterMover != null) return;
    _attached[world] = NativeDynamics(
      world: world,
      movesCharacters: true,
      castsRays: true,
    );
  }

  @override
  void release(CollisionWorld world) {
    _attached[world]?.dispose();
    _attached[world] = null;
    for (final mirror in world.mirrors.toList()) {
      if (mirror is NativeDynamics) mirror.dispose();
    }
  }
}

/// Why the run is on the backend it is on — what [startPhysics] answered.
typedef PhysicsStart = ({PhysicsBackend backend, String? fallbackBecause});

/// What [usePhysics] chose, once it could; null until then.
PhysicsStart? _chosen;

/// Why the run fell back to the Dart reference, or null when it did not —
/// for a game to say so somewhere a player reporting a bug will see.
String? get physicsFallbackReason => _chosen?.fallbackBecause;

/// The run's backend, chosen the first time anything asks and the same
/// every time after: the core, unless the build asked for the reference
/// or the core will not start. Synchronous, so the code that stages a
/// world can ask it.
///
/// **In the browser the core has to be fetched first** — [startPhysics]
/// does that — and until it is, this answers the reference without
/// choosing it, so a later [startPhysics] still can.
///
/// The core is tried, not assumed: a world is made and freed, which is the
/// first call that would find a missing library or bindings for another
/// ABI — and either is a fallback rather than a crash at the first step.
PhysicsBackend usePhysics({String asked = askedPhysics}) {
  if (_chosen case final PhysicsStart chosen) return chosen.backend;
  if (asked != 'dart' && !physicsCoreLoaded) return const DartPhysics();
  return _choose(asked, () => NativeWorld().dispose()).backend;
}

PhysicsStart _choose(String asked, void Function() probe) {
  PhysicsStart chosen;
  if (asked == 'dart') {
    chosen = (backend: const DartPhysics(), fallbackBecause: null);
  } else {
    try {
      probe();
      chosen = (backend: NativePhysics(), fallbackBecause: null);
    } on Object catch (e) {
      chosen = (backend: const DartPhysics(), fallbackBecause: '$e');
    }
  }
  PhysicsBackend.current = chosen.backend;
  return _chosen = chosen;
}

/// Chooses the run's backend again, now: [asked] — `'native'` or `'dart'`
/// — where it can be had, the reference where not. For code that plays a
/// recording back on what it was recorded on (`Demo.physics`) and cannot
/// wait: a replay in an isolate of its own, whose backend starts as the
/// reference. Natively the core needs nothing loaded; in the browser it has
/// to be, by [startPhysics], or this falls back.
PhysicsBackend choosePhysics(String asked) {
  if (asked != 'dart' && !physicsCoreLoaded) {
    return _choose(asked, () => throw StateError('the core is not loaded'))
        .backend;
  }
  return _choose(asked, () => NativeWorld().dispose()).backend;
}

/// [startPhysics] unless the run's backend is chosen already: what code
/// that opens a level calls, so the first level starts the physics and the
/// rest find it as the first left it.
Future<PhysicsStart> preparePhysics() async =>
    _chosen ?? await startPhysics();

/// Loads the core where it has to be loaded — the browser's module — and
/// chooses the run's backend as [usePhysics] does, choosing again if
/// something chose before: what a game's `main` calls first, and what a
/// test calls to start from a known backend.
///
/// [probe] stands in for the first world, for a test of the fallback.
Future<PhysicsStart> startPhysics({
  String asked = askedPhysics,
  int threads = 1,
  void Function()? probe,
}) async {
  _chosen = null;
  if (asked != 'dart') {
    try {
      await loadPhysicsCore(threads: threads);
    } on Object catch (e) {
      return _choose(asked, () => throw StateError('$e'));
    }
  }
  return _choose(asked, probe ?? () => NativeWorld().dispose());
}
