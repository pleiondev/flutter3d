import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:vector_math/vector_math.dart';

import 'game_event.dart';

/// Two bodies met, are still meeting, or parted, in a step: a
/// [StepContact] of the step's dynamics (`RigidDynamics.contacts`), on the
/// bus.
///
/// What physics-driven sound, impact decals, damage and breaking are
/// written on, and why it carries **ids, not objects**: the bodies as the
/// collision world numbers them (`CollisionWorld.idOf`) and their
/// materials by catalogue id. So it is the same value on a tape, across
/// the isolate and over the wire as in the step that raised it, and a
/// view reads a material's properties from its own catalogue
/// (`MaterialCatalog`) rather than from an object the simulation holds.
/// Where the world is at hand, the ids read back: `CollisionWorld.colliderOf`
/// gives the collider and its `userData`, `RigidDynamics.bodyOfId` the
/// body, on either core.
///
/// **In one order on both cores.** A step publishes its contacts in the
/// order the dynamics list them — by [bodyA], then [bodyB], then
/// [feature] — so a tape replays them as the run made them, whichever core
/// stepped it ([publishAll]).
final class ContactEvent extends GameEvent {
  /// A contact between bodies [bodyA] and [bodyB]; [feature] tells apart
  /// several contacts of one pair and defaults to nought.
  ContactEvent({
    required this.bodyA,
    required this.bodyB,
    this.feature = 0,
    this.materialA,
    this.materialB,
    required this.phase,
    required this.point,
    required this.normal,
    required this.impulse,
    required this.relativeVelocity,
  });

  /// The event a step's [contact] is: its vectors the ones the contact
  /// hands out, each made for this event alone.
  factory ContactEvent.of(StepContact contact) => ContactEvent(
    bodyA: contact.idA,
    bodyB: contact.idB,
    feature: contact.feature,
    materialA: contact.materialA,
    materialB: contact.materialB,
    phase: contact.phase,
    point: contact.point,
    normal: contact.normal,
    impulse: contact.impulse,
    relativeVelocity: contact.relativeVelocity,
  );

  /// The name it is declared and published under.
  static const String eventName = 'physics.contact';

  /// Publishes [contacts] through [publish], one event each, in their
  /// order: what a step calls once its dynamics have stepped, with
  /// `RigidDynamics.contacts` and its context's `publish` (or a bus's).
  static void publishAll(
    Iterable<StepContact> contacts,
    void Function(ContactEvent event) publish,
  ) {
    for (final contact in contacts) {
      publish(ContactEvent.of(contact));
    }
  }

  /// Its codec: every field, flat, the phase by its wire name. Reads back
  /// to an equal event; a phase this build does not name reads as null,
  /// since an event with a phase it cannot say is not one it can hand on.
  static final EventCodec<ContactEvent> codec = EventCodec<ContactEvent>.of(
    encode: (ContactEvent e) => <Object?>[
      e.bodyA,
      e.bodyB,
      e.feature,
      e.materialA,
      e.materialB,
      e.phase.name,
      e.point.x,
      e.point.y,
      e.point.z,
      e.normal.x,
      e.normal.y,
      e.normal.z,
      e.impulse,
      e.relativeVelocity.x,
      e.relativeVelocity.y,
      e.relativeVelocity.z,
    ],
    decode: (context) {
      final data = context.data;
      return switch (data) {
        [
          final int bodyA,
          final int bodyB,
          final int feature,
          final String? materialA,
          final String? materialB,
          final String phase,
          final num px,
          final num py,
          final num pz,
          final num nx,
          final num ny,
          final num nz,
          final num impulse,
          final num vx,
          final num vy,
          final num vz,
          ...,
        ] =>
          switch (ContactPhase.byName(phase)) {
            final ContactPhase phase => ContactEvent(
              bodyA: bodyA,
              bodyB: bodyB,
              feature: feature,
              materialA: materialA,
              materialB: materialB,
              phase: phase,
              point: Vector3(px.toDouble(), py.toDouble(), pz.toDouble()),
              normal: Vector3(nx.toDouble(), ny.toDouble(), nz.toDouble()),
              impulse: impulse.toDouble(),
              relativeVelocity: Vector3(
                vx.toDouble(),
                vy.toDouble(),
                vz.toDouble(),
              ),
            ),
            null => null,
          },
        _ => null,
      };
    },
  );

  /// The body the collision world numbered first (`CollisionWorld.idOf`).
  final int bodyA;

  /// The other, numbered above [bodyA]: a body, or the level it met.
  final int bodyB;

  /// Which face of the pair, for two that meet on two at once: nought, or
  /// one for the second.
  final int feature;

  /// [bodyA]'s material's catalogue id, or null for none.
  final String? materialA;

  /// [bodyB]'s material's catalogue id, or null for none.
  final String? materialB;

  /// Whether it began, persists or ended this step. An open set: a
  /// `switch` over it ends with a wildcard.
  final ContactPhase phase;

  /// Halfway between the two surfaces, relative to the world's origin, in
  /// metres; for an ended contact, where it last was.
  final Vector3 point;

  /// Unit length, out of [bodyB] into [bodyA].
  final Vector3 normal;

  /// What the solver pushed the two apart with over the step, along
  /// [normal], in newton-seconds: nought for an ended contact and for one
  /// held while both sides sleep.
  final double impulse;

  /// [bodyA]'s point's velocity against [bodyB]'s as the step found them,
  /// before gravity or a contact acted, in metres per second: what a
  /// [ContactPhase.begin] was struck at.
  final Vector3 relativeVelocity;

  @override
  String get name => eventName;

  @override
  String toString() =>
      'ContactEvent($bodyA–$bodyB#$feature ${phase.name}, '
      'impulse $impulse)';
}
