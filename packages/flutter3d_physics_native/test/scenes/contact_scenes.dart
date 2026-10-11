// Scenes whose contacts the two cores are held to, built once through
// RigidDynamics: bodies that cannot turn, since the reference's contacts do
// not turn them, on the shapes both cores know exactly.
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

/// One step's contact, with the step it was in.
final class SeenContact {
  SeenContact(this.step, this.contact);

  final int step;
  final StepContact contact;

  /// What two cores must agree on exactly: when, which pair, which face,
  /// and what became of it.
  String get order =>
      '$step ${contact.idA}-${contact.idB}#${contact.feature} '
      '${contact.phase.name}';

  Vector3 get normal => contact.normal;
  Vector3 get point => contact.point;
  Vector3 get relativeVelocity => contact.relativeVelocity;
  double get impulse => contact.impulse;
}

/// A scene: what is in it, how many steps it runs, how far the two cores'
/// impulses over it may differ, N·s, and whether its bodies sleep. Asleep,
/// a contact is held and pushes with nothing, and the two cores fall
/// asleep at steps of their own: a scene that sleeps is held to its phases,
/// and its impulse is not compared.
final class ContactScene {
  const ContactScene(
    this.name,
    this.build, {
    this.steps = 120,
    this.impulseTolerance = 0.4,
    this.during,
    this.sleeps = false,
  });

  final String name;
  final void Function(RigidDynamics dynamics) build;
  final int steps;
  final double impulseTolerance;
  final bool sleeps;

  /// Called before each step with its number, for what a scene does along
  /// the way.
  final void Function(RigidDynamics dynamics, int step)? during;

  /// Every step's contacts, in order, on the dynamics [make] builds.
  List<SeenContact> run(RigidDynamics Function(CollisionWorld world) make) {
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    final dynamics = make(world);
    build(dynamics);
    final seen = <SeenContact>[];
    for (var step = 0; step < steps; step++) {
      during?.call(dynamics, step);
      dynamics.step(1.0 / 60.0);
      for (final contact in dynamics.contacts) {
        seen.add(SeenContact(step, contact));
      }
    }
    return seen;
  }
}

RigidBody _ball(RigidDynamics d, Vector3 at, {double radius = 0.25}) => d.add(
  RigidBody(world: d.world, shape: CollisionSphere(radius), position: at),
);

RigidBody _crate(RigidDynamics d, Vector3 at, {double half = 0.5}) => d.add(
  RigidBody(
    world: d.world,
    shape: CollisionBox(Vector3.all(half)),
    position: at,
  ),
);

/// The scenes.
final List<ContactScene> contactScenes = <ContactScene>[
  ContactScene('a ball dropped on the floor', (d) {
    _ball(d, Vector3(0.0, 1.0, 0.0));
  }),
  ContactScene('balls dropped side by side from three heights', (d) {
    for (var i = 0; i < 3; i++) {
      _ball(d, Vector3(i * 1.0, 0.6 + i * 0.5, 0.0));
    }
  }),
  ContactScene('a crate dropped on a crate', (d) {
    _crate(d, Vector3(0.0, 0.5, 0.0));
    _crate(d, Vector3(0.0, 2.0, 0.0));
  }),
  ContactScene('two balls meeting in the air, and parting', (d) {
    d.world.properties = d.world.properties.copyWith(gravity: Vector3.zero());
    _ball(d, Vector3(-1.0, 2.0, 0.0)).velocity.setValues(2.0, 0.0, 0.0);
    _ball(d, Vector3(1.0, 2.0, 0.0)).velocity.setValues(-2.0, 0.0, 0.0);
  }, steps: 60),
  ContactScene(
    'a pile of three falls asleep, and is held',
    (d) {
      for (var i = 0; i < 3; i++) {
        _crate(d, Vector3(0.0, 0.5 + i * 1.0, 0.0));
      }
    },
    steps: 240,
    sleeps: true,
  ),
  ContactScene(
    'a ball taken out while it rests',
    (d) {
      _ball(d, Vector3(0.0, 0.26, 0.0));
    },
    steps: 40,
    during: (d, step) {
      if (step == 30) d.remove(d.bodies.single);
    },
  ),
];
