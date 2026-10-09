/// A [Brain] that runs a behaviour tree, keeping everything it knows on the
/// actor's [Blackboard].
///
/// ## Nothing on the brain
///
/// [save] is the default empty map, and that is the design rather than an
/// omission. Where the actor is in its tree, what it heard and when, how long
/// it has waited: all of it is a component, so the ECS save writes it and a
/// rewind restores it without this class being asked. A brain that kept even
/// one field would put that field outside every snapshot that forgot to call
/// `save` on it.
///
/// ## What it notices for the tree
///
/// The engine tells a brain about noise and pain, and a tree cannot override
/// a method. So this writes them down, where a leaf or a consideration can
/// read them: [heard] (where), [heardAt] and [hurtAt] (the board's clock when
/// it happened). `since` is the consideration that turns "heard at" into
/// "heard recently".
library;

import 'package:vector_math/vector_math.dart';

import 'actor.dart';
import 'actor_system.dart';
import 'behaviour_tree.dart';
import 'brain.dart';

/// A brain that runs a [BehaviorTree] over the actor's [Blackboard] —
/// [BehaviorBrain], or a game's own that runs one for part of the time —
/// so that [BehaviorBrain.pathOf] and [BehaviorBrain.goalOf] can read it
/// whoever wrote the brain.
///
/// **Mixed in, not implemented**, outside this library: a `base` type, so a
/// member added in a 1.x release arrives with a body and nothing that mixes
/// it in has to change.
abstract base mixin class HasBehaviorTree {
  BehaviorTree get tree;
}

final class BehaviorBrain extends Brain implements HasBehaviorTree {
  BehaviorBrain(this.tree);

  /// Shared by every actor that runs it; see [BehaviorTree].
  @override
  final BehaviorTree tree;

  /// Where the last noise this actor heard came from, as a point.
  static const String heard = 'heard';

  /// The board's clock when it was heard.
  static const String heardAt = 'heardAt';

  /// The board's clock when this actor was last hurt and lived.
  static const String hurtAt = 'hurtAt';

  /// [actor]'s board, made on the spot when it has none.
  ///
  /// Made here rather than at spawn so that `ActorSystem.spawn` stays the one
  /// way an actor is built; a game that wants values on the board before the
  /// first decision sets a [Blackboard] on the entity itself.
  static Blackboard boardOf(Actor actor) {
    final present = actor.entities.get<Blackboard>(actor.entity);
    if (present != null) return present;
    final made = Blackboard();
    actor.entities.set(actor.entity, made);
    return made;
  }

  @override
  void think(Mind it) => tree.tick(it, boardOf(it.actor));

  @override
  void act(Mind it) {
    final board = boardOf(it.actor);
    board.clock += it.dt;
    tree.act(it, board);
  }

  @override
  void onNoise(Mind it, Vector3 at) {
    final board = boardOf(it.actor)..setPoint(heard, at);
    board.set(heardAt, board.clock);
  }

  @override
  void onHurt(Mind it, double amount) {
    final board = boardOf(it.actor);
    board.set(hurtAt, board.clock);
  }

  /// The path [actor] took last time it decided, root first, or empty when it
  /// does not run a tree or has not decided yet.
  ///
  /// **Reads the board and never makes one**, unlike [boardOf]: this is what
  /// an overlay calls between frames, and an overlay that put a component on
  /// an entity would change the next snapshot by being switched on.
  static List<BehaviorPathStep> pathOf(Actor actor) =>
      switch ((actor.brain, actor.entities.get<Blackboard>(actor.entity))) {
        (final HasBehaviorTree brain, final Blackboard board) =>
          brain.tree.pathOf(board),
        _ => const <BehaviorPathStep>[],
      };

  /// Where [actor]'s running leaf is taking it, or null. Reads, like
  /// [pathOf].
  static Vector3? goalOf(Actor actor, ActorSystem system) =>
      switch ((actor.brain, actor.entities.get<Blackboard>(actor.entity))) {
        (final HasBehaviorTree brain, final Blackboard board) =>
          brain.tree.goalOf((actor: actor, system: system, board: board)),
        _ => null,
      };
}
