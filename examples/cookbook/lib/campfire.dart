/// A campfire: particles born at a point, rising, shrinking and fading.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: Campfire()));

/// One flame: drawn additively, so the alpha reads as brightness.
const ParticleEffect flame = ParticleEffect(
  count: 1,
  emitter: ConeEmitter(speed: Range(0.4, 1.0), halfAngle: 0.3),
  lifetime: Range(0.6, 1.2),
  size: Range(0.15, 0.3),
  color: LinearColor(1.0, 0.42, 0.08, 0.8),
  affectors: <ParticleAffector>[
    ParticleGravity(acceleration: 1.2), // Hot air rises.
    ParticleSizeOverLife(),
    ParticleFade(startsAt: 0.3),
  ],
);

/// A dark scene with a camera on the fire and [flame] emitted a hundred and
/// twenty times a second at the origin.
class Campfire extends StatelessWidget {
  /// Takes nothing: the effect is the constant [flame], and the rate is fixed
  /// in [build].
  const Campfire({super.key});

  @override
  Widget build(BuildContext context) => Scene3D(
    clearColor: const LinearColor(0.01, 0.01, 0.03),
    children: <Widget>[
      Camera3D(position: Vector3(0.0, 1.0, 3.0), target: Vector3(0, 0.6, 0)),
      const Particles3D(effect: flame, perSecond: 120),
    ],
  );
}
