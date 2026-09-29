import 'package:flame/components.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_particles/flutter3d_particles.dart';

import '../transform/plane.dart';

/// A `flutter3d_particles` [ParticleSystem] run on Flame's clock: fire,
/// sparks, debris thrown out where something happened in the game.
///
/// **What each bridged game with explosions wrote by hand.** A component
/// per blast, a scene node per shard, each node moved, spun, shrunk and
/// taken out again: a hundred nodes and a hundred draws for one depot going
/// up. A particle system is one pool and one instanced draw for every blast
/// on screen, and the particles package already has the emitters, gravity,
/// fading and shrinking a shard was given by hand.
///
/// This component advances [system] in its [update], so a paused game
/// pauses its fire. It draws through a [MeshParticleContributor] once
/// [drawWith] is given the renderer, which `Flutter3dFlameWidget`'s
/// `onRendererReady` hands over; without one (a test, a server) the
/// particles still live and die, and nothing is drawn.
///
/// The contributor draws additively, so a particle can only add light: fire,
/// sparks, a muzzle flash, a glow. Dark smoke is not a particle here.
class Particles3dComponent extends Component {
  Particles3dComponent({required this.system, required this.plane});

  /// The pool every burst goes into.
  final ParticleSystem system;

  /// The plane [burstAt] places a Flame point on.
  final BridgePlane plane;

  Renderer? _renderer;
  MeshParticleContributor? _contributor;

  /// Draws every particle as a copy of [mesh] through [renderer]'s scene
  /// pass. Calling it again, with a new renderer after the old one was
  /// replaced, moves the drawing there.
  void drawWith(Renderer renderer, DrawableGeometry mesh) {
    _stopDrawing();
    _renderer = renderer;
    _contributor = renderer.addContributor(
      MeshParticleContributor(system, mesh: mesh),
    );
  }

  /// Throws [effect] out of the Flame point [at] on [plane], lifted
  /// [elevation] off it, along the plane's normal. Returns how many
  /// particles the pool had room for.
  int burstAt(
    ParticleEffect effect,
    Vector2 at, {
    double elevation = 0.0,
    Object? source,
  }) => system.burst(
    effect,
    plane.to3d(at, at: plane.constant + elevation),
    direction: plane.normal,
    source: source,
  );

  @override
  void update(double dt) {
    super.update(dt);
    system.advance(dt);
  }

  @override
  void onRemove() {
    _stopDrawing();
    system.clear();
    super.onRemove();
  }

  void _stopDrawing() {
    final contributor = _contributor;
    if (contributor != null) _renderer?.removeContributor(contributor);
    _contributor = null;
    _renderer = null;
  }
}
