/// [ActorSystemComponent] steps one shared flutter3d_sim [ActorSystem],
/// once a frame, wherever Flame's own game loop already is.
library;

import 'package:flame/components.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'actor_component.dart';

/// The one place a bridged game's frame steps a shared [ActorSystem].
///
/// **Plain [Component], not [PositionComponent].** It draws nothing and
/// sits nowhere — each actor it steps has its own [ActorComponent] for
/// that — so it carries none of the transform a [PositionComponent] would
/// otherwise make a caller invent an answer for.
///
/// **Why stepping lives here and not on every [ActorComponent].**
/// [ActorSystem.step]'s own doc states the protocol it is half of:
/// [ActorSystem.beginStep] must run once, immediately before it, every
/// frame — call `step` again without a fresh `beginStep` and it throws;
/// call `beginStep`/`step` more than once a frame and every actor's
/// physics runs twice that frame. A game with N actors sharing one
/// [ActorSystem] but stepping it from N different [ActorComponent]s would
/// do exactly that, and stepping the whole system N times to move a
/// world's worth of actors N times too fast is not something any one
/// actor's component can see from where it sits — only whoever owns the
/// system can. So [ActorComponent] itself never calls [ActorSystem.step]
/// or [ActorSystem.beginStep]; this is the only caller, and it calls the
/// pair exactly once per [update].
///
/// **Why [focus] and [focusBody] are closures, not values captured once.**
/// [ActorSystem.step] needs to know where the world's one focus point is
/// *this frame* — a player's own position, typically — and a value taken
/// once at construction would freeze it at wherever that was when this
/// component was built. Reading a fresh `Vector3`/`Collider?` every
/// [update] costs one call each and is the only way this component can
/// hand [ActorSystem.step] a focus that has actually moved since.
final class ActorSystemComponent extends Component {
  ActorSystemComponent({
    required this.system,
    required this.focus,
    this.focusBody,
  });

  /// The actor system every [ActorComponent] in this game shares.
  final ActorSystem system;

  /// Where the system's one focus point is, read fresh every [update].
  final Vector3 Function() focus;

  /// What the focus point belongs to, or null for a focus with no body of
  /// its own — read fresh every [update], for the same reason as [focus].
  final Collider? Function()? focusBody;

  @override
  void update(double dt) {
    super.update(dt);
    system.beginStep();
    system.step(dt, focus: focus(), focusBody: focusBody?.call());
  }
}
