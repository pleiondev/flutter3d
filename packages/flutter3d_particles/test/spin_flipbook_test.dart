/// Rotation and flipbook, both of which live entirely in the vertex data.
///
/// No shader knows either exists. Billboarding already happens on the CPU here,
/// so a rotation turns the quad's axes before the corners are written and a
/// flipbook scales the corner coordinates into one cell of a sheet — which is
/// why neither cost a backend change, and why both are testable without a
/// device.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Sets one angle on every particle, so a test can state it rather than derive
/// it from a seed.
final class _FixedSpin extends ParticleAffector {
  const _FixedSpin(this.angle);
  final double angle;
  @override
  void apply(Particle particle, double dt) => particle.rotation = angle;
}

/// One particle at the origin, at a stated size, with nothing moving it.
///
/// The system has no public way to reach a live particle, and adding one for a
/// test would put a hole in the pool's invariants for the benefit of this file.
/// An affector is the supported way in, and it is also how a real caller would
/// set a rotation.
ParticleSystem _one({double size = 2.0, double? rotation}) {
  final system = ParticleSystem(capacity: 4, seed: 7)
    ..burst(
      ParticleEffect(
        count: 1,
        lifetime: const Range.exact(10.0),
        size: Range.exact(size),
        color: Vector4(1.0, 1.0, 1.0, 1.0),
        emitter: const SphereEmitter(speed: Range.exact(0.0)),
        affectors: rotation == null
            ? const <ParticleAffector>[]
            : <ParticleAffector>[_FixedSpin(rotation)],
      ),
      Vector3.zero(),
    );
  if (rotation != null) system.step(1 / 60);
  return system;
}

/// The quad's four corners and their texture coordinates.
({List<Vector3> corners, List<Vector2> uvs}) _quad(
  ParticleSystem system, {
  Flipbook? flipbook,
}) {
  final vertices = Float32List(4 * ParticleSystem.floatsPerParticle);
  final indices = Uint32List(24);
  final written = system.writeQuads(
    Vector3(1.0, 0.0, 0.0),
    Vector3(0.0, 1.0, 0.0),
    vertices,
    indices,
    flipbook: flipbook,
  );
  expect(written, 1);
  return (
    corners: <Vector3>[
      for (var i = 0; i < 4; i++)
        Vector3(vertices[i * 9], vertices[i * 9 + 1], vertices[i * 9 + 2]),
    ],
    uvs: <Vector2>[
      for (var i = 0; i < 4; i++)
        Vector2(vertices[i * 9 + 7], vertices[i * 9 + 8]),
    ],
  );
}

void main() {
  group('rotation', () {
    test('a particle nothing turns is written exactly as it always was', () {
      // The property every recorded golden depends on. Rotation is a field that
      // defaults to zero, and the path that reads it must not touch a quad that
      // has none.
      final quad = _quad(_one()).corners;
      expect(quad[0].x, closeTo(-1.0, 1e-9));
      expect(quad[0].y, closeTo(-1.0, 1e-9));
      expect(quad[2].x, closeTo(1.0, 1e-9));
      expect(quad[2].y, closeTo(1.0, 1e-9));
      expect(quad[0].z, 0.0);
    });

    test('a quarter turn moves each corner to the next one round', () {
      final quad = _quad(_one(rotation: math.pi / 2)).corners;
      // The corner that was bottom-left is now bottom-right: rotating the axes
      // by a quarter turn sends right to up and up to minus right.
      expect(quad[0].x, closeTo(1.0, 1e-9));
      expect(quad[0].y, closeTo(-1.0, 1e-9));
      expect(quad[2].x, closeTo(-1.0, 1e-9));
      expect(quad[2].y, closeTo(1.0, 1e-9));
    });

    test('the quad keeps its size and stays square', () {
      final quad = _quad(_one(rotation: 0.7)).corners;
      // Opposite corners are still two apart, and adjacent ones still two.
      // A rotation built by scaling instead of turning would shrink one axis
      // and leave a rhombus, which reads as a particle that pulses as it spins.
      //
      // A millionth, not a billionth: these come back out of a `Float32List`,
      // and at an angle with no exact sine the round trip costs about 1e-8.
      expect((quad[0] - quad[2]).length, closeTo(2 * math.sqrt2, 1e-6));
      expect((quad[0] - quad[1]).length, closeTo(2.0, 1e-6));
      expect((quad[1] - quad[2]).length, closeTo(2.0, 1e-6));
    });

    test('the spin affector derives the angle rather than accumulating it', () {
      // Applied twice at the same age it must answer the same angle. An
      // accumulating implementation would double it, and the number of
      // sub-steps a frame takes would then change how fast particles spin.
      const spin = ParticleSpin(turnsPerSecond: 1.0);
      final particle = Particle()
        ..lifetime = 1.0
        ..age = 0.25
        ..seed = 0.8;
      spin.apply(particle, 1 / 60);
      final once = particle.rotation;
      spin.apply(particle, 1 / 60);
      expect(particle.rotation, once);
    });

    test('two particles of one burst do not turn together', () {
      // The tell this exists to avoid: a sheet of aligned squares rotating in
      // step, which draws the eye to the grid.
      const spin = ParticleSpin(turnsPerSecond: 1.0);
      final a = Particle()
        ..lifetime = 1.0
        ..age = 0.3
        ..seed = 0.1;
      final b = Particle()
        ..lifetime = 1.0
        ..age = 0.3
        ..seed = 0.9;
      spin
        ..apply(a, 1 / 60)
        ..apply(b, 1 / 60);
      expect(a.rotation, isNot(closeTo(b.rotation, 0.1)));
      // And in opposite directions, since the seed is signed about a half.
      expect(
        (a.rotation - 0.1 * 2 * math.pi).sign,
        isNot((b.rotation - 0.9 * 2 * math.pi).sign),
      );
    });
  });

  group('the flipbook', () {
    test('no flipbook writes the whole texture', () {
      final uvs = _quad(_one()).uvs;
      expect(uvs.first, Vector2(0.0, 0.0));
      expect(uvs[2], Vector2(1.0, 1.0));
    });

    test('a fresh particle shows the first cell', () {
      final book = Flipbook(columns: 4, rows: 4);
      final uvs = _quad(_one(), flipbook: book).uvs;
      expect(uvs.first.x, closeTo(0.0, 1e-9));
      expect(uvs.first.y, closeTo(0.0, 1e-9));
      expect(uvs[2].x, closeTo(0.25, 1e-9));
      expect(uvs[2].y, closeTo(0.25, 1e-9));
    });

    test('the cell advances across the life and holds the last one', () {
      final book = Flipbook(columns: 4, rows: 1);
      final particle = Particle()..lifetime = 1.0;

      particle.age = 0.0;
      expect(book.cellFor(particle).left, closeTo(0.0, 1e-9));
      particle.age = 0.3;
      expect(book.cellFor(particle).left, closeTo(0.25, 1e-9));
      particle.age = 0.8;
      expect(book.cellFor(particle).left, closeTo(0.75, 1e-9));

      // At and past the end the last frame is held. Wrapping to the first would
      // be a visible blink at the instant the particle disappears.
      particle.age = 1.0;
      expect(book.cellFor(particle).left, closeTo(0.75, 1e-9));
      particle.age = 2.0;
      expect(book.cellFor(particle).left, closeTo(0.75, 1e-9));
    });

    test('a looping sheet wraps instead of holding', () {
      final book = Flipbook(columns: 2, rows: 1, loops: 2);
      final particle = Particle()..lifetime = 1.0;
      particle.age = 0.0;
      expect(book.cellFor(particle).left, closeTo(0.0, 1e-9));
      particle.age = 0.3;
      expect(book.cellFor(particle).left, closeTo(0.5, 1e-9));
      // Second time round.
      particle.age = 0.6;
      expect(book.cellFor(particle).left, closeTo(0.0, 1e-9));
    });

    test('a sheet whose last row is not full stops at the frames it has', () {
      // Seven frames in a 3x3 grid: cells seven and eight are empty, and
      // playing them is a particle that blinks out and comes back.
      final book = Flipbook(columns: 3, rows: 3, frames: 7);
      expect(book.frameCount, 7);
      final particle = Particle()
        ..lifetime = 1.0
        ..age = 0.999;
      final cell = book.cellFor(particle);
      expect(cell.left, closeTo(0.0, 1e-9), reason: 'frame six is column zero');
      expect(cell.top, closeTo(2 / 3, 1e-9), reason: 'of the last row');
    });
  });
}
