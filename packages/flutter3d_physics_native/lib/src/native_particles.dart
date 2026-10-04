/// Particles, on the CPU and on the GPU — P9, phase 10.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'core/core.dart' as c;

/// How particles move: gravity, the wind they drift towards at [drag] per
/// second, and a floor at [floorY] they bounce off with [restitution] and
/// lose [friction] of their sliding speed on.
final class ParticleForces {
  ParticleForces({
    Vector3? gravity,
    Vector3? wind,
    this.drag = 0.0,
    this.floorY = double.negativeInfinity,
    this.restitution = 0.0,
    this.friction = 0.0,
  }) : gravity = gravity ?? Vector3(0.0, -9.81, 0.0),
       wind = wind ?? Vector3.zero();

  final Vector3 gravity;
  final Vector3 wind;
  final double drag;
  final double floorY;
  final double restitution;
  final double friction;
}

/// One particle to emit.
typedef Particle = ({Vector3 position, Vector3 velocity, double life});

/// A set of particle slots, filled round and round, that fall, drift,
/// bounce and die: on the CPU ([NativeParticles]) or the GPU
/// ([GpuParticles]), the same steps. Visual, not the game's state.
abstract interface class ParticleSystem {
  /// How many slots there are.
  int get capacity;

  /// Puts [particles] into the next slots, the oldest going first.
  void emit(List<Particle> particles);

  /// Steps every living particle [steps] times by [dt].
  void step(ParticleForces forces, double dt, {int steps = 1});

  /// Every slot: position xyz and the life it has left, four floats apiece;
  /// nought or less is dead.
  Float32List read();

  /// Frees the slots.
  void dispose();
}

c.F32s packParticles(List<Particle> particles) {
  final data = c.F32s.alloc(particles.isEmpty ? 7 : particles.length * 7);
  for (var i = 0; i < particles.length; i++) {
    final p = particles[i];
    data[i * 7] = p.position.x;
    data[i * 7 + 1] = p.position.y;
    data[i * 7 + 2] = p.position.z;
    data[i * 7 + 3] = p.velocity.x;
    data[i * 7 + 4] = p.velocity.y;
    data[i * 7 + 5] = p.velocity.z;
    data[i * 7 + 6] = p.life;
  }
  return data;
}

/// [forces] as the core's `F3dParticleForces` — and the GPU's, laid out
/// the same — in a block of the core's memory the caller frees.
int writeParticleForces(ParticleForces forces) {
  final f = c.coreAlloc(c.F3dParticleForcesLayout.size);
  for (var k = 0; k < 3; k++) {
    c.writeF32(
      f + c.F3dParticleForcesLayout.gravity + k * 4,
      forces.gravity[k],
    );
    c.writeF32(f + c.F3dParticleForcesLayout.wind + k * 4, forces.wind[k]);
  }
  c.writeF32(f + c.F3dParticleForcesLayout.drag, forces.drag);
  c.writeF32(
    f + c.F3dParticleForcesLayout.floorY,
    forces.floorY == double.negativeInfinity ? -3.4e38 : forces.floorY,
  );
  c.writeF32(f + c.F3dParticleForcesLayout.restitution, forces.restitution);
  c.writeF32(f + c.F3dParticleForcesLayout.friction, forces.friction);
  return f;
}

/// Particles stepped by the core on the CPU: the reference for the GPU's,
/// and the fallback where there is none.
final class NativeParticles implements ParticleSystem {
  NativeParticles(int capacity) : _p = c.f3d_particles_create(capacity) {
    if (_p == 0) {
      throw ArgumentError.value(capacity, 'capacity', 'none, or no memory');
    }
    _finalizer.attach(this, _p, detach: this);
  }

  static final Finalizer<int> _finalizer = Finalizer<int>(
    c.f3d_particles_destroy,
  );

  int _p;

  int get _live {
    if (_p == 0) throw StateError('these particles were disposed');
    return _p;
  }

  @override
  int get capacity => c.f3d_particles_capacity(_live);

  @override
  void emit(List<Particle> particles) {
    final data = packParticles(particles);
    try {
      c.f3d_particles_emit(_live, data, particles.length);
    } finally {
      data.free();
    }
  }

  @override
  void step(ParticleForces forces, double dt, {int steps = 1}) {
    final f = writeParticleForces(forces);
    try {
      for (var s = 0; s < steps; s++) {
        c.f3d_particles_step(_live, f, dt);
      }
    } finally {
      c.coreFree(f);
    }
  }

  @override
  Float32List read() {
    final n = capacity;
    final out = c.F32s.alloc(n * c.particleFloats);
    try {
      c.f3d_particles_read(_live, out, n);
      return out.copy(n * c.particleFloats);
    } finally {
      out.free();
    }
  }

  @override
  void dispose() {
    if (_p == 0) return;
    _finalizer.detach(this);
    c.f3d_particles_destroy(_p);
    _p = 0;
  }
}
