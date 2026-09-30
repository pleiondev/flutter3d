import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'hero_class.dart';

/// One player's hero: a body, a class, and what they are carrying.
///
/// **Health drains by itself.** A second in the maze costs [drainPerSecond]
/// whatever happens in it, so standing still is not safe and food is not a
/// luxury. That is the pressure the whole genre runs on, and it is why
/// [maximumHealth] is far above [startingHealth]: food carries a hero past
/// where they began, and a hero who ate well can afford a detour.
///
/// The body's collider names this object as its `userData`, which is how a
/// piece of loot lying in the maze knows who walked into it.
final class Hero {
  Hero({
    required CollisionWorld world,
    required this.kind,
    required this.slot,
    required Vector3 at,
  }) : body = CharacterController(
         world: world,
         position: at,
         tuning: MovementTuning(walkSpeed: kind.speed),
         layer: CollisionLayers.player,
       ) {
    body.collider.userData = this;
  }

  /// What a hero starts a run with.
  static const double startingHealth = 700.0;

  /// How far food can carry a hero past that.
  static const double maximumHealth = 9999.0;

  /// What a second costs.
  static const double drainPerSecond = 1.0;

  /// Below this, the hero is told they need food — once each time they fall
  /// under it, not every step they stay there.
  static const double hungryBelow = 200.0;

  final HeroClass kind;

  /// Which controller this hero answers to, nought to three.
  final int slot;

  final CharacterController body;

  final Health health = Health(maximumHealth, current: startingHealth);

  /// Keys carried. Each opens one door and is gone.
  int keys = 0;

  /// Potions carried, for clearing the screen.
  int potions = 0;

  int score = 0;

  /// Where the player is pushing the stick, on the ground, written by the game
  /// before each step. A length under one is a request to walk slower.
  final Vector3 wish = Vector3.zero();

  /// Whether fire is held, written by the game before each step. Held fire
  /// shoots every [HeroClass.shotInterval].
  bool fire = false;

  /// Set by the game on the step the magic button goes down; the step drinks
  /// a potion, if there is one, and puts this back to false. A press, not a
  /// hold: one potion per press.
  bool drink = false;

  /// Which way the hero faces, on the ground: the last way they walked, and
  /// the way they shoot.
  final Vector3 facing = Vector3(0.0, 0.0, -1.0);

  /// Seconds until the next shot may leave.
  double reload = 0.0;

  /// Whether [hungryBelow] has been announced since the hero was last above it.
  bool _warned = false;

  Vector3 get position => body.position;
  bool get isAlive => health.isAlive;

  /// Takes a blow through the class's armour, and says whether it killed.
  bool hurt(double amount) => health.damage(amount * kind.damageTaken);

  /// What a second of the maze costs, past armour. Says whether it killed.
  bool starve(double dt) => health.damage(drainPerSecond * dt);

  /// Whether the hero has just fallen below [hungryBelow], true once per fall.
  bool get becameHungry {
    final hungry = isAlive && health.current < hungryBelow;
    if (!hungry) {
      _warned = false;
      return false;
    }
    if (_warned) return false;
    _warned = true;
    return true;
  }

  /// Health from food, never past [maximumHealth].
  void feed(double amount) => health.heal(amount);

  Map<String, Object?> save() => <String, Object?>{
    'body': body.save(),
    'health': health.save(),
    'keys': keys,
    'potions': potions,
    'score': score,
    'warned': _warned,
    'facing': <double>[facing.x, facing.y, facing.z],
    'reload': reload,
  };

  void restore(Map<String, Object?> from) {
    final saved = from.object('body');
    if (saved != null) body.restore(saved);
    final vitals = from.object('health');
    if (vitals != null) health.restore(vitals);
    keys = (from['keys'] as num?)?.toInt() ?? 0;
    potions = (from['potions'] as num?)?.toInt() ?? 0;
    score = (from['score'] as num?)?.toInt() ?? 0;
    _warned = from['warned'] == true;
    from.vectorInto('facing', facing);
    reload = (from['reload'] as num?)?.toDouble() ?? 0.0;
  }
}
