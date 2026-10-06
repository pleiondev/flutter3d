/// A bonfire on the pond's bank: six logs of the physics core's wood, laid
/// crosswise. They catch, burn down and spread fire to each other by the
/// core's heat; `flutter3d_effects`' `FireView` draws the fire and chars
/// them.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativeBody, NativeMaterial, NativeShape, NativeWorld;
import 'package:vector_math/vector_math.dart';

/// Where the bonfire stands: on the sand past the pond's east shore.
const double fireX = 23.5, fireZ = 24.0;

/// The ground under it, m.
const double fireGround = 0.5;

/// A log's radius and half its length, m: 1.4 m long, 30 cm thick.
const double _logRadius = 0.15, _logHalf = 0.7;

/// One log of the pile, and where it is drawn.
final class _Log {
  _Log(this.body, this.node);

  final NativeBody body;
  final SceneNode node;
}

/// The bonfire: its logs, lit and doused.
final class Bonfire {
  Bonfire(this._world, GraphicsDevice device, Scene scene, FireView fire) {
    final mesh = DeviceMesh.upload(
      device,
      const CylinderShape(
        radiusTop: _logRadius,
        radiusBottom: _logRadius,
        height: 2 * _logHalf,
        segments: 20,
      ).build(),
    );
    // Three layers, crosswise, as a fire is laid: two logs along x, two
    // along z on them, two along x on top.
    for (var layer = 0; layer < 3; layer++) {
      final alongX = layer.isEven;
      for (final side in <double>[-0.4, 0.4]) {
        final y = fireGround + _logRadius * (1 + 2 * layer) + 0.01;
        final body = _world.addBody(
          position: alongX
              ? Vector3(fireX, y, fireZ + side)
              : Vector3(fireX + side, y, fireZ),
          // Seasoned wood, 450 kg/m³.
          mass: 450.0 * math.pi * _logRadius * _logRadius * 2 * _logHalf,
        );
        // As it meets others, a bar along x rounded by two thirds of its
        // radius: round enough to look it, flat enough to lie on another
        // across it, where two round ones meet at a point and roll apart.
        const round = 2 * _logRadius / 3;
        _world
          ..setShape(
            body,
            NativeShape.box(
              Vector3(_logHalf - round, _logRadius - round, _logRadius - round),
            ),
          )
          ..setRounding(body, round)
          ..setMaterial(body, NativeMaterial.wood());
        if (!alongX) {
          _world.setOrientation(
            body,
            Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), math.pi / 2),
          );
        }
        // The cylinder stands along y; laid along the body's x.
        final look =
            MeshNode(
              mesh,
              Material(
                name: 'log',
                baseColor: Vector4(0.42, 0.28, 0.16, 1.0),
                roughness: 0.9,
              ),
              name: 'log',
            )..setRotation(
              Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), math.pi / 2),
            );
        final node = SceneNode(name: 'log')..add(look);
        scene.add(node);
        fire.watch(body, look);
        _logs.add(_Log(body, node));
      }
    }
  }

  final NativeWorld _world;
  final List<_Log> _logs = <_Log>[];

  /// Lights the fire: a match held to the bottom log until it catches —
  /// the log's surface brought past wood's ignition temperature.
  void light() => _world.setTemperature(_logs.first.body, 650.0);

  /// A bucket of water over every log that burns.
  void douse() {
    for (final log in _logs) {
      if (_world.isBurning(log.body)) _world.addWater(log.body, 8.0);
    }
  }

  /// The logs drawn where the world has them.
  void step() {
    for (final log in _logs) {
      final p = _world.positionOf(log.body);
      log.node
        ..setPosition(p.x, p.y, p.z)
        ..setRotation(_world.orientationOf(log.body));
    }
  }
}
