/// A bonfire on the pond's bank: six logs of the physics core's wood, laid
/// crosswise. A burning brand held to the bottom one lights it in the time
/// the wood takes to reach its ignition temperature; they burn down and
/// spread fire to each other by the core's heat, and the effects package's
/// elements draw the fire and char them.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativeMaterial;

/// Where the bonfire stands: on the sand past the pond's east shore.
const double fireX = 23.5, fireZ = 24.0;

/// The ground under it, m.
const double fireGround = 0.5;

/// A log's radius and half its length, m: 1.4 m long, 30 cm thick.
const double _logRadius = 0.15, _logHalf = 0.7;

/// The bonfire: its logs, lit and doused.
final class Bonfire {
  Bonfire(this._elements, GraphicsDevice device) {
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
        // The cylinder stands along y; laid along the body's x.
        final look =
            MeshNode(
              mesh,
              RenderMaterial(
                name: 'log',
                baseColor: LinearColor.fromSrgb(0.42, 0.28, 0.16, 1.0),
                roughness: 0.9,
              ),
              name: 'log',
            )..setRotation(
              Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), math.pi / 2),
            );
        final node = SceneNode(name: 'log')..add(look);
        _elements.fireView.scene.add(node);
        // As it meets others, a bar along x rounded by two thirds of its
        // radius: round enough to look it, flat enough to lie on another
        // across it, where two round ones meet at a point and roll apart.
        // Seasoned wood, 450 kg/m³.
        const round = 2 * _logRadius / 3;
        final bar = Vector3(
          _logHalf - round,
          _logRadius - round,
          _logRadius - round,
        );
        final log = _elements.addBody(
          Solid.box(
            bar,
            material: NativeMaterial.wood(),
            density: 450.0,
          ).rounded(round),
          at: alongX
              ? Vector3(fireX, y, fireZ + side)
              : Vector3(fireX + side, y, fireZ),
          turn: alongX
              ? null
              : Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), math.pi / 2),
          look: node,
          chars: look,
        );
        _logs.add(log);
      }
    }
  }

  final Elements _elements;
  final List<TrackedBody> _logs = <TrackedBody>[];

  /// The logs, as they were laid: the bottom layer first.
  List<TrackedBody> get logs => List<TrackedBody>.unmodifiable(_logs);

  /// A burning brand held to a log: about fifty kilowatts a square metre
  /// over a hand's width from a flame at 1300 K, held for half a minute.
  static const Igniter _brand = Igniter(
    flux: 5e4,
    area: 0.01,
    temperature: 1300.0,
    seconds: 30.0,
  );

  /// Lights the fire: the brand held under the bottom log.
  void light() {
    final log = _logs.first;
    final at = _elements.world.localPositionOf(log.native)..y -= _logRadius;
    _elements.fires.ignite(log, by: _brand, at: at);
  }

  /// A bucket of water over every log that burns.
  void douse() {
    for (final log in _logs) {
      if (_elements.world.isBurning(log.native)) {
        _elements.fires.douse(log, 8.0);
      }
    }
  }
}
