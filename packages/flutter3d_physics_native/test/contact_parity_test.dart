// The step's contacts from the two cores: the same scenes built once,
// through RigidDynamics, stepped by the reference and by the core, and their
// contact lists held to one another — the same pairs on the same faces,
// beginning and ending in the same order, each at the same step or the one
// beside it, meeting at the same speed and passing the same momentum.
//
// **A step either way, and no more.** The core's speculative contact
// reaches as far as a body moves in a step, so it catches a falling ball
// the step before it would touch; the reference's reaches its two
// centimetres of margin, so it catches it the step it does. Both say the
// impact happened, at the speed it fell at; neither moves the simulation
// to agree with the other, since the reference's bits are the ones every
// recorded run holds.
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';

import 'scenes/contact_scenes.dart';

void main() {
  for (final scene in contactScenes) {
    test('${scene.name}: the cores report the same contacts', () {
      final reference = ContactHistory(
        scene.run(
          (world) =>
              Dynamics(world: world)
                ..sleepAfter = scene.sleeps ? 0.5 : double.infinity,
        ),
      );
      final core = ContactHistory(
        scene.run((world) {
          world.properties = world.properties.copyWith(airDensity: 1e-30);
          final dynamics = NativeDynamics(world: world);
          if (!scene.sleeps) dynamics.native.setSleep(speed: 0.0, time: 0.0);
          addTearDown(dynamics.dispose);
          return dynamics;
        }),
      );
      expect(reference.pairs, isNotEmpty, reason: 'a scene with no contact');
      // Mutation: report a contact the core keeps while both sides sleep as
      // ended, or a body's removal as nothing, and the pairs or their
      // phases part.
      expect(core.pairs, reference.pairs);
      for (final pair in reference.pairs) {
        final r = reference.changes[pair]!, n = core.changes[pair]!;
        expect(
          n.map((c) => c.contact.phase).toList(),
          r.map((c) => c.contact.phase).toList(),
          reason: '$pair: what became of it, in order',
        );
        for (var i = 0; i < r.length; i++) {
          final why = '$pair: ${r[i].order} against ${n[i].order}';
          expect(
            (n[i].step - r[i].step).abs(),
            lessThanOrEqualTo(1),
            reason: why,
          );
          expect(
            n[i].normal.distanceTo(r[i].normal),
            lessThan(1e-3),
            reason: why,
          );
          // Where a contact begins, the core says by the points its manifold
          // had then: a crate the speculative contact caught short of
          // another holds the corner that reached it first. Where it rests,
          // below, the two agree.
          if (r[i].contact.phase != ContactPhase.begin) {
            expect(
              n[i].point.distanceTo(r[i].point),
              lessThan(0.05),
              reason: why,
            );
          }
          if (r[i].contact.phase == ContactPhase.begin) {
            expect(
              (n[i].relativeVelocity - r[i].relativeVelocity).length,
              lessThan(0.3),
              reason: why,
            );
          }
        }
        if (reference.resting[pair] case final r?) {
          final n = core.resting[pair]!;
          expect(
            n.point.distanceTo(r.point),
            lessThan(0.05),
            reason: '$pair: where it rests',
          );
          expect(n.normal.distanceTo(r.normal), lessThan(1e-3));
        }
        // The momentum the pair passed over the scene: the impact's and the
        // weight held, give or take a step of weight either way.
        if (scene.sleeps) continue;
        expect(
          core.impulse[pair]!,
          closeTo(reference.impulse[pair]!, scene.impulseTolerance),
          reason: '$pair: impulse over the scene',
        );
      }
    });
  }
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
