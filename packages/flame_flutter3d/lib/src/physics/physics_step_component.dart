/// [PhysicsStepComponent] steps one shared flutter3d_physics world, once a
/// frame, wherever Flame's own game loop already is.
library;

import 'package:flame/components.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';

import 'rigid_body_component.dart';

/// The one place a bridged game's frame steps its [Dynamics] and dispatches
/// its [CollisionWorld]'s contacts.
///
/// **The physics half of what [ActorSystemComponent] is for actors.** A
/// [RigidBodyComponent] never steps anything, for the reason that class
/// gives: a hundred bridged crates each stepping the shared world would
/// step it a hundred times a frame. Something has to step it once, and every
/// game that used the bridge wrote this component for itself: the arcade,
/// the package's own example, a showcase page. It lives here now.
///
/// **Step, then whatever follows a body, then dispatch.** [update] calls
/// [Dynamics.step], then [afterStep], then [CollisionWorld.update], in that
/// order, because the last of them is what sends overlaps to every listener,
/// a [CollisionBridge] among them. Dispatching before the step would report
/// last frame's overlaps against this frame's picture. [afterStep] is the
/// seam for anything that follows a body the solver just moved and has to
/// be in place before the dispatch: a trigger sensor that rides on a solid
/// body, for instance, since two solids never overlap and only the sensor
/// can report them touching.
///
/// **Order it before whatever reads the result.** Flame updates components
/// by ascending priority; give this one a priority below the components that
/// read positions or react to contacts, as [ActorSystemComponent] is given
/// one below the actors' readers.
final class PhysicsStepComponent extends Component {
  PhysicsStepComponent({
    required this.dynamics,
    required this.world,
    this.afterStep,
    super.priority,
  });

  /// The bodies this steps.
  final Dynamics dynamics;

  /// The world whose contacts this dispatches after the step.
  final CollisionWorld world;

  /// Runs between the solver and the dispatch, once a frame. Null for a game
  /// with nothing to move there.
  final void Function()? afterStep;

  @override
  void update(double dt) {
    super.update(dt);
    dynamics.step(dt);
    afterStep?.call();
    world.update();
  }
}
