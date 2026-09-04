/// A monster that walks a beat until something interrupts it.
///
/// **What the roster was missing.** [ChaseBrain] has two resting states — idle
/// and alert — and both of them stand still. A crypt whose monsters are all
/// asleep until seen reads as a museum: the player learns that nothing moves
/// until they are noticed, and after that every room is the same room. A
/// guard walking between two points is the cheapest thing that stops that, and
/// it costs the level one list of positions.
///
/// **A subclass rather than a mode on [ChaseBrain]**, which is the extension
/// point `Brain` was opened for. Everything a chase does — seeing, hearing,
/// being hurt, fighting back, dying — is inherited unchanged; what this adds is
/// what to do with the state that used to mean *stand there*.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'chase_brain.dart';
import 'monster_def.dart';

/// The state a patrolling monster rests in.
///
/// Its own rather than reusing [MonsterState.idle], so an animation table can
/// tell a guard on its beat from one standing still, and so [ChaseBrain] —
/// which does not know this state — leaves it alone rather than driving it.
/// That is exactly what its `default` was written for.
const MonsterState patrolling = MonsterState('patrolling');

/// A [ChaseBrain] that walks a route while it has nothing better to do.
///
/// Interruption is not handled here and does not need to be: everything that
/// wakes a monster — sight, noise, damage — already calls `_enter` on the
/// inherited machine, and this brain only drives the state nothing else claims.
/// When the fight is over the monster is left in whatever state the chase left
/// it in, which is deliberate: a guard that goes calmly back to its beat after
/// being shot at is a guard nobody believes.
final class PatrolBrain extends ChaseBrain {
  PatrolBrain({
    required super.def,
    required super.shot,
    required this.route,
    super.difficulty,
    this.reachedWithin = 0.6,
    this.pauseSeconds = 0.0,
  }) : assert(
         route.length >= 2,
         'a beat between fewer than two points is a '
         'monster standing still, which ChaseBrain already does',
       ) {
    state = patrolling;
  }

  /// Where the beat goes, in world space, walked in order and then round again.
  ///
  /// **A loop rather than a there-and-back**, because a there-and-back is a
  /// loop a level can author by listing the points twice, and a loop is not
  /// something a there-and-back can express at all.
  final List<Vector3> route;

  /// How close counts as having reached a point, in metres.
  ///
  /// Generous on purpose: a monster steering towards a point through a doorway
  /// arrives beside it rather than on it, and a tight radius is a guard that
  /// circles its own waypoint for ever.
  final double reachedWithin;

  /// How long to stand at each point before moving on.
  ///
  /// Zero walks the beat without stopping. A second or two is what makes a
  /// patrol readable from across a room: a player needs to see the guard
  /// stop, look, and go on before they can time anything against it.
  final double pauseSeconds;

  /// Which point is being walked to.
  int leg = 0;

  /// How long this monster has been standing at the point it reached.
  double waited = 0.0;

  final Vector3 _target = Vector3.zero();

  @override
  void act(Mind it) {
    super.act(it);
    if (state != patrolling) return;

    final here = it.actor.position;
    if (here == null) return;

    _target.setFrom(route[leg % route.length]);
    final gap = _target.distanceTo(here);
    if (gap <= reachedWithin) {
      waited += it.dt;
      if (waited >= pauseSeconds) {
        waited = 0.0;
        leg = (leg + 1) % route.length;
      }
      return;
    }

    waited = 0.0;
    it.steerTowards(_target);
    final heading = it.system.heading;
    it.turnTowards(heading.x, heading.z);
  }

  @override
  Map<String, Object?> save() => <String, Object?>{
    ...super.save(),
    'leg': leg,
    'waited': waited,
  };

  @override
  void restore(Map<String, Object?> from) {
    super.restore(from);
    leg = (from['leg'] as num?)?.toInt() ?? 0;
    waited = (from['waited'] as num?)?.toDouble() ?? 0.0;
  }
}
