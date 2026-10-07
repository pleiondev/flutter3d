/// What a hit leaves burning on the river: a tanker's oil spread on the
/// water and alight, a depot's timbers in a heap on the bank. Fires of the
/// physics core's own heat, which burn as long as their fuel lasts and
/// light what stands close enough, drawn as flames and smoke over the
/// stretch they burn on and let go once the jet has left it behind.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

/// The fires a run leaves behind it on the river.
final class BurningWrecks {
  BurningWrecks({
    required GraphicsDevice device,
    required Scene scene,
    required Renderer renderer,
  }) {
    _fire = FireView(
      world: world,
      device: device,
      scene: scene,
      renderer: renderer,
      baseWidth: 0.8,
    );
  }

  /// The world the fires burn in: nothing in it but what burns.
  final NativeWorld world = NativeWorld();
  late final FireView _fire;
  final List<NativeBody> _burning = <NativeBody>[];

  /// How far behind the jet a fire is let go, m.
  static const double behind = 40.0;

  /// A tanker's cargo spread over the water at [at] and burning: crude oil,
  /// which burns as long and as sooty as rubber does.
  void oil(Vector3 at) => _light(
    Vector3(at.x, 0.05, at.z),
    NativeShape.box(Vector3(1.4, 0.05, 0.8)),
    NativeMaterial.rubber(),
    mass: 60.0,
  );

  /// A depot's timbers at [at], burning where they fell.
  void timbers(Vector3 at) => _light(
    Vector3(at.x, at.y, at.z),
    NativeShape.box(Vector3(0.9, 0.5, 0.9)),
    NativeMaterial.wood(),
    mass: 160.0,
  );

  void _light(
    Vector3 at,
    NativeShape shape,
    NativeMaterial material, {
    required double mass,
  }) {
    final body = world.addBody(
      position: at,
      type: NativeBodyType.fixed,
      mass: mass,
    );
    world
      ..setShape(body, shape)
      ..setMaterial(body, material)
      // Set alight by the blast: past what lights either.
      ..setTemperature(body, 900.0);
    _burning.add(body);
  }

  /// The fires on by [dt], the jet [distance] metres down the river: the
  /// river runs along −z, so a fire past [behind] metres behind it is gone.
  void step(double dt, double distance) {
    world.step(dt);
    _burning.removeWhere((body) {
      if (world.positionOf(body).z < -(distance - behind)) return false;
      world.removeBody(body);
      return true;
    });
    _fire.update(dt);
  }

  /// Every fire put out, for a new jet starting the stretch again.
  void clear() {
    for (final body in _burning) {
      world.removeBody(body);
    }
    _burning.clear();
  }

  void dispose() => world.dispose();
}
