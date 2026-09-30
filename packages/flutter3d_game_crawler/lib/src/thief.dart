/// The monster that takes rather than hurts.
///
/// It runs at the hero the flow field gives it — the one it can reach first —
/// takes a potion, or a key if there is no potion, and runs the other way.
/// If it stays alive for [Thief.escapeAfter] seconds it is gone with what it
/// took; killed before that, it gives the thing back to whoever killed it.
///
/// **Straight away from the hero, not to an exit.** The field routes towards
/// the heroes and nowhere else, and a thief that knew the way out would need
/// a field of its own. Running straight off and sliding along the walls reads
/// as fleeing, and the clock is what makes it a race.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'hero.dart';
import 'horde.dart';
import 'monster_kind.dart';

/// What a thief can take, in the order it looks for them.
final class Stolen {
  const Stolen._(this.name);

  final String name;

  static const Stolen potion = Stolen._('potion');
  static const Stolen key = Stolen._('key');

  static Stolen? named(Object? name) => switch (name) {
    'potion' => potion,
    'key' => key,
    _ => null,
  };

  /// Takes one of these from [hero]; false when they have none.
  bool takeFrom(Hero hero) {
    if (identical(this, potion) && hero.potions > 0) {
      hero.potions -= 1;
      return true;
    }
    if (identical(this, key) && hero.keys > 0) {
      hero.keys -= 1;
      return true;
    }
    return false;
  }

  /// Gives one back to [hero].
  void giveTo(Hero hero) {
    if (identical(this, potion)) hero.potions += 1;
    if (identical(this, key)) hero.keys += 1;
  }
}

/// A thief took something.
final class ThiefStole extends GameEvent {
  const ThiefStole(this.hero, this.what);

  final Hero hero;
  final Stolen what;

  @override
  String get name => 'a thief took ${hero.kind.name}\'s ${what.name}';
}

/// A thief got away, and what it took is gone.
final class ThiefEscaped extends GameEvent {
  const ThiefEscaped(this.what);

  final Stolen? what;

  @override
  String get name => 'a thief got away';
}

final class Thief extends Brain {
  Thief(this.kind);

  final MonsterKind kind;

  /// Seconds of running before it is gone.
  static const double escapeAfter = 4.0;

  /// What it is carrying, or null while it has taken nothing.
  Stolen? carrying;

  /// Whether it has done its taking and is running. A thief that found its
  /// hero with empty pockets runs too: there was nothing to take.
  bool fleeing = false;

  double _running = 0.0;
  final Vector3 _away = Vector3.zero();

  @override
  void act(Mind it) {
    if (!fleeing) {
      it.steerTowardsFocus();
      final heading = it.heading;
      it.turnTowards(heading.x, heading.z);
      if (it.distance > kind.radius + Chaser.quarry + Chaser.reach) return;
      final hero = it.focusBody?.userData;
      if (hero is! Hero || !hero.isAlive) return;
      for (final what in const <Stolen>[Stolen.potion, Stolen.key]) {
        if (!what.takeFrom(hero)) continue;
        carrying = what;
        it.system.events?.add(ThiefStole(hero, what));
        break;
      }
      fleeing = true;
      return;
    }
    _running += it.dt;
    if (_running >= escapeAfter) {
      it.system.events?.add(ThiefEscaped(carrying));
      carrying = null;
      it.system.hurt(it.actor, double.infinity);
      return;
    }
    final from = it.toFocus;
    _away.setValues(-from.x, 0.0, -from.z);
    if (_away.length2 < 1e-8) return;
    _away.normalize();
    it
      ..steer(_away)
      ..turnTowards(_away.x, _away.z);
  }

  @override
  Map<String, Object?> save() => <String, Object?>{
    if (carrying case final Stolen what) 'carrying': what.name,
    'fleeing': fleeing,
    'running': _running,
  };

  @override
  void restore(Map<String, Object?> from) {
    carrying = Stolen.named(from['carrying']);
    fleeing = from['fleeing'] == true;
    _running = (from['running'] as num?)?.toDouble() ?? 0.0;
  }
}
