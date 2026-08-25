/// The words a platformer's levels use beyond the format's own.
///
/// `EntityTypes` already covers the spawn point, doors, lifts, platforms,
/// buttons, triggers, exits and lights — every one of which a platformer wants
/// unchanged, which is the first evidence that the level format really was
/// written for levels rather than for one game.
abstract final class PlatformerEntities {
  static const String collectible = 'collectible';
  static const String hazard = 'hazard';
  static const String checkpoint = 'checkpoint';
  static const String crate = 'crate';
  static const String spring = 'spring';

  /// A platform you jump up through and land on top of.
  static const String oneWay = 'oneway';

  /// A floor that carries whoever stands on it.
  static const String conveyor = 'conveyor';

  /// A platform that gives way under you.
  static const String crumbling = 'crumbling';

  /// A block a ground pound breaks.
  static const String breakable = 'breakable';

  /// A ladder, or — with a swing on it — a rope.
  static const String climbable = 'climbable';

  /// A lamp on a post: something to see by, and something to see.
  static const String lamp = 'lamp';

  /// Something that walks a route and hurts on contact.
  static const String enemy = 'enemy';
}
