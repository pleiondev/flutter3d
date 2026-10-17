import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor;

import 'particle.dart';
import 'particle_affector.dart';
import 'particle_emitter.dart';

/// A recipe for a burst: what is emitted, and what happens to it.
///
/// Data, and const-constructible, so effects live next to the game code that
/// triggers them and cost nothing to hold. Nothing here names a specific
/// effect — an explosion and a footstep puff are the same three fields with
/// different numbers.
final class ParticleEffect {
  const ParticleEffect({
    required this.count,
    required this.emitter,
    required this.lifetime,
    required this.size,
    required this.color,
    this.affectors = const <ParticleAffector>[],
  });

  /// How many particles one burst emits.
  final int count;

  final ParticleEmitter emitter;

  /// What happens to each of them, in order, every step.
  final List<ParticleAffector> affectors;

  final Range lifetime;
  final Range size;

  /// Colour at birth, in linear light. Alpha reads as brightness, since
  /// these draw additively.
  final LinearColor color;
}
