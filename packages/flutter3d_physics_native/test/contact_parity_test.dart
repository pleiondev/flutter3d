// The step's contacts from the two cores: the same scenes built once,
// through RigidDynamics, stepped by the reference and by the core, and their
// contact lists held to one another — the same pairs on the same faces,
// beginning and ending in the same order, meeting at the same speed and
// passing the same momentum; and each core, restored from a save mid-scene,
// telling exactly the contacts it told the first time.
//
// **On the same step.** Both solvers look for a contact as far as a body
// moves in the step and let the gap close and no more, so both catch a
// falling ball on the step it would reach the floor and say so then.
//
// Every tolerance below is the least the two cores' arithmetic
// allows, with its reason beside it: the core steps in floats with
// substeps, the reference in doubles with one step, and each solver leaves
// a resting body at an overlap of its own inside [contactSlop].
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';

import 'scenes/contact_scenes.dart';

/// A normal along an axis is exact in floats, and one made from float
/// positions is a float's rounding of a unit vector: six parts in a hundred
/// million a component.
const double _normalTolerance = 1e-6;

/// Across the normal, a contact's middle is the middle of a face both cores
/// place where the scene put it: a float's rounding of a few metres, a
/// micrometre at most.
const double _acrossTolerance = 1e-6;

/// Along the normal, each solver leaves a resting body at an overlap of its
/// own between nought and [contactSlop], and the middle is halfway into it,
/// so the two middles are at most half the slop apart — and a whole slop
/// more for each resting body under it ([ContactScene.stacked]), whose
/// overlap it stands on.
double _alongTolerance(ContactScene scene) =>
    contactSlop * (scene.stacked + 0.5);

/// The speed a contact begins at: the same fall on both, the core's in
/// floats, a float's rounding of a few metres a second.
const double _speedTolerance = 1e-5;

void main() {
  for (final scene in contactScenes) {
    RigidDynamics reference(CollisionWorld world) =>
        Dynamics(world: world)
          ..sleepAfter = scene.sleeps ? 0.5 : double.infinity;
    RigidDynamics core(CollisionWorld world) {
      world.properties = world.properties.copyWith(airDensity: 1e-30);
      final dynamics = NativeDynamics(world: world);
      if (!scene.sleeps) dynamics.native.setSleep(speed: 0.0, time: 0.0);
      addTearDown(dynamics.dispose);
      return dynamics;
    }

    group(scene.name, () {
      test('the cores report the same contacts', () {
        _holdTo(
          ContactHistory(scene.run(core)),
          ContactHistory(scene.run(reference)),
          scene,
        );
      });

      for (final (name, make)
          in <(String, RigidDynamics Function(CollisionWorld))>[
            ('the reference', reference),
            ('the core', core),
          ]) {
        test('$name restored mid-scene tells the same contacts again', () {
          final straight = scene.run(make);
          final restored = scene.run(make, restoreAt: scene.steps ~/ 2);
          // Mutation: forget the step before on a restore, on either core,
          // and a contact resting through it begins again.
          expect(
            restored.map((c) => c.order).toList(),
            straight.map((c) => c.order).toList(),
            reason: 'every contact, in order, on its step, in its phase',
          );
          for (var i = 0; i < straight.length; i++) {
            expect(restored[i].point, straight[i].point);
            expect(restored[i].impulse, straight[i].impulse);
          }
        });
      }
    });
  }
}

/// [n], the core's, held to [r], the reference's.
void _holdTo(ContactHistory n, ContactHistory r, ContactScene scene) {
  expect(r.pairs, isNotEmpty, reason: 'a scene with no contact');
  // Mutation: report a contact the core keeps while both sides sleep as
  // ended, or a body's removal as nothing, and the pairs or their phases
  // part.
  expect(n.pairs, r.pairs);
  for (final pair in r.pairs) {
    final rs = r.changes[pair]!, ns = n.changes[pair]!;
    expect(
      ns.map((c) => c.contact.phase).toList(),
      rs.map((c) => c.contact.phase).toList(),
      reason: '$pair: what became of it, in order',
    );
    for (var i = 0; i < rs.length; i++) {
      final a = rs[i], b = ns[i];
      final why = '$pair: ${a.order} against ${b.order}';
      // Mutation: look for a contact no further than the margin in the
      // reference, and a fall is caught a step after the core catches it.
      expect(b.step, a.step, reason: why);
      expect(
        b.normal.distanceTo(a.normal),
        lessThan(_normalTolerance),
        reason: why,
      );
      if (a.contact.phase == ContactPhase.begin) {
        expect(
          (b.relativeVelocity - a.relativeVelocity).length,
          lessThanOrEqualTo(_speedTolerance),
          reason: why,
        );
      }
      if (a.contact.phase == ContactPhase.end) _samePlace(b, a, scene, why);
    }
    if (r.resting[pair] case final a?) {
      _samePlace(n.resting[pair]!, a, scene, '$pair: where it rests');
    }
    // The momentum the pair passed over the scene: its impact and the
    // weight it held, every step of it the same weight times the step on
    // both, give or take the step the impact is told on.
    if (scene.sleeps) continue;
    expect(
      n.impulse[pair]!,
      closeTo(r.impulse[pair]!, scene.impulseTolerance),
      reason: '$pair: impulse over the scene',
    );
  }
}

/// [b]'s middle against [a]'s: across the normal to the floats' rounding,
/// along it within the two solvers' resting overlaps.
void _samePlace(SeenContact b, SeenContact a, ContactScene scene, String why) {
  final n = a.normal;
  final d = b.point - a.point;
  final along = d.dot(n);
  final across = (d - n * along).length;
  expect(
    across,
    lessThan(_acrossTolerance * (1 + a.point.length)),
    reason: why,
  );
  expect(along.abs(), lessThanOrEqualTo(_alongTolerance(scene)), reason: why);
}

/// A scene's contacts, by pair and face: where each began and ended, and
/// the impulse it passed in all.
final class ContactHistory {
  ContactHistory(List<SeenContact> seen) {
    for (final c in seen) {
      final pair = '${c.contact.idA}-${c.contact.idB}#${c.contact.feature}';
      if (!changes.containsKey(pair)) pairs.add(pair);
      final list = changes.putIfAbsent(pair, () => <SeenContact>[]);
      if (c.contact.phase != ContactPhase.persist) list.add(c);
      impulse[pair] = (impulse[pair] ?? 0.0) + c.impulse;
    }
    pairs.sort();
    final lastStep = seen.isEmpty ? -1 : seen.last.step;
    for (final c in seen) {
      if (c.step != lastStep || c.contact.phase != ContactPhase.persist) {
        continue;
      }
      resting['${c.contact.idA}-${c.contact.idB}#${c.contact.feature}'] = c;
    }
  }

  /// The pairs still in contact at the scene's last step, as they rest.
  final Map<String, SeenContact> resting = <String, SeenContact>{};

  final List<String> pairs = <String>[];
  final Map<String, List<SeenContact>> changes = <String, List<SeenContact>>{};
  final Map<String, double> impulse = <String, double>{};
}
