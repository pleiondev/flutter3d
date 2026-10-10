import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'chase_brain.dart';
import 'patrol.dart';

/// A monster whose rest is a behaviour tree: what it does before it has
/// noticed anybody — a beat, a wander, a post kept, a door checked — written
/// as a document a level carries rather than as a brain a game compiles.
///
/// **Everything after the noticing is [ChaseBrain]'s**, unchanged: seeing,
/// hearing, being hurt, the fight and the dying, and the save that keeps
/// them. The tree has the monster only while it is [isResting]; the moment
/// sight, a noise or pain wakes it, the chase takes over and the tree is not
/// asked again. That split is [PatrolBrain]'s, which is a tree of one fixed
/// shape; this is the same with the shape authored.
///
/// The tree keeps nothing here: its path, its memory and its clock are a
/// `Blackboard` component on the actor, in the run's save with everything
/// else, which is what `BehaviorBrain` is built on.
final class TreeBrain extends ChaseBrain with HasBehaviorTree {
  TreeBrain({
    required super.def,
    required super.shot,
    required BehaviorTree tree,
    super.difficulty,
  }) : _tree = BehaviorBrain(tree) {
    state = patrolling;
  }

  final BehaviorBrain _tree;

  /// The tree it rests by.
  @override
  BehaviorTree get tree => _tree.tree;

  @override
  bool get isResting => state == patrolling || super.isResting;

  @override
  void think(Mind it) {
    super.think(it);
    if (state == patrolling) _tree.think(it);
  }

  @override
  void act(Mind it) {
    super.act(it);
    if (state == patrolling) _tree.act(it);
  }
}
