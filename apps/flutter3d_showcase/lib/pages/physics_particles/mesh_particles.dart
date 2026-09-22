/// Every live particle drawn as a copy of a real mesh instead of a
/// camera-facing quad, in one instanced call.
///
/// Quoted by `mesh_particles.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class MeshParticlesDemo extends ShowcaseDemo {
  late final ParticleSystem _particles;
  late final ParticleEffect _debrisEffect;
  late final MeshParticleContributor _contributor;

  static const int _count = 40;

  // Debris that fell once and lay still would leave nothing moving to look
  // at once gravity settled it below the frame.
  static const double _pause = 1.0;
  double _cooldown = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.5
      ..pitch = 0.25
      ..yaw = 0.4;
  }

  @override
  Scene build(DemoContext context) {
    // #region mesh
    // One shape, uploaded once. Every particle is a placement of it rather
    // than a separate draw, which is what keeps this a single instanced call
    // however many shards are on screen.
    final DeviceMesh shard = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.12, 0.12, 0.12)).build(),
    );
    // #endregion mesh

    _particles = ParticleSystem(capacity: _count, seed: 808);
    _debrisEffect = ParticleEffect(
      count: _count,
      emitter: const SphereEmitter(speed: Range(1.0, 2.5)),
      lifetime: const Range(1.0, 1.8),
      size: const Range(0.6, 1.2),
      color: Vector4(0.8, 0.75, 0.7, 1.0),
      affectors: <ParticleAffector>[const ParticleGravity(-3.0)],
    );
    _particles.burst(_debrisEffect, Vector3.zero());

    // #region contributor
    _contributor = context.renderer.addContributor(
      MeshParticleContributor(_particles, mesh: shard),
    );
    // #endregion contributor

    return Scene()..add(
      LightNode(name: 'sun', intensity: 2.0)
        ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
    );
  }

  @override
  void update(DemoContext context, double dt) {
    _particles.advance(dt);

    if (_particles.aliveCount == 0) {
      _cooldown -= dt;
      if (_cooldown <= 0.0) {
        _particles.burst(_debrisEffect, Vector3.zero());
        _cooldown = _pause;
      }
    }
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (!_contributor.isActive) {
      throw StateError('the mesh particles should be alive and drawing');
    }
    if (_particles.aliveCount != _count || frame.drawCalls < 1) {
      throw StateError('the shards did not reach the frame');
    }
    // #endregion check
  }
}
