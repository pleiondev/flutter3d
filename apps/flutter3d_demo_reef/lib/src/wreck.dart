/// The sunken ship and the boat over the reef: the one a fixed body of
/// timbers lying on the sand, the other afloat on the sea, held by its
/// anchor's rope against the current.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'terrain.dart';

/// Where the ship's timbers rest: the floor under its middle.
double get wreckFloor => floorAt(wreckX, wreckZ);

/// The ship: a keel and bottom, one side whole and the other broken off,
/// her stem and stern posts, three deck beams across the open hold, and the
/// mast fallen beside her.
final class Wreck {
  Wreck(
    NativeWorld world,
    GraphicsDevice device,
    Scene scene,
    Material timber,
  ) {
    // Each piece: its half size, where it is in the ship's frame (x along
    // her length, bow forward), and a lean about her length.
    final pieces = <(Vector3, Vector3, double)>[
      (
        Vector3(wreckHalfLength, 0.15, wreckHalfBeam - 0.3),
        Vector3(0, 0.15, 0),
        0.0,
      ),
      (
        Vector3(wreckHalfLength - 0.5, 1.2, 0.12),
        Vector3(0, 1.3, wreckHalfBeam),
        0.12,
      ),
      (Vector3(5.5, 0.8, 0.12), Vector3(-2.5, 0.9, -wreckHalfBeam), -0.25),
      (
        Vector3(0.15, 1.5, wreckHalfBeam - 0.2),
        Vector3(-wreckHalfLength, 1.5, 0),
        0.0,
      ),
      (Vector3(0.15, 1.3, 1.4), Vector3(wreckHalfLength, 1.3, 0), 0.0),
      for (final x in <double>[-5.0, -1.0, 3.0])
        (Vector3(0.12, 0.12, wreckHalfBeam), Vector3(x, 2.3, 0.15), 0.0),
    ];
    final turn = Quaternion.axisAngle(Vector3(0, 1, 0), -wreckHeading);
    final shape = world.createCompound(<NativeCompoundPart>[
      for (final (half, at, lean) in pieces)
        NativeCompoundPart(
          NativeShape.box(half),
          at: at,
          turn: Quaternion.axisAngle(Vector3(1, 0, 0), lean),
        ),
    ]);
    final body = world.addBody(
      position:
          Vector3(wreckX, wreckFloor, wreckZ) +
          turn.rotated(world.compoundOffset(shape)),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world
      ..setCompound(body, shape)
      ..setOrientation(body, turn);
    final ship = SceneNode(name: 'wreck')
      ..setPosition(wreckX, wreckFloor, wreckZ)
      ..setRotation(turn);
    for (final (half, at, lean) in pieces) {
      ship.add(
        MeshNode(
            DeviceMesh.upload(device, CuboidShape(size: half * 2.0).build()),
            timber,
            name: 'timber',
          )
          ..setPosition(at.x, at.y, at.z)
          ..setRotation(Quaternion.axisAngle(Vector3(1, 0, 0), lean)),
      );
    }
    // The mast, fallen across the sand off her broken side.
    final mastAt = Vector3(1.5, 0.25, -wreckHalfBeam - 2.0);
    final mast = world.addBody(
      position: Vector3(wreckX, wreckFloor, wreckZ) + turn.rotated(mastAt),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    final lying = turn * Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2);
    world
      ..setShape(mast, const NativeShape.cylinder(0.2, 6.0))
      ..setOrientation(mast, lying);
    ship.add(
      MeshNode(
          DeviceMesh.upload(
            device,
            const CylinderShape(
              radiusTop: 0.16,
              radiusBottom: 0.2,
              height: 12.0,
            ).build(),
          ),
          timber,
          name: 'mast',
        )
        ..setPosition(mastAt.x, mastAt.y, mastAt.z)
        ..setRotation(Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2)),
    );
    scene.add(ship);
  }
}

/// The dive boat: afloat, anchored over the reef flat.
final class Boat {
  Boat(this._world, GraphicsDevice device, Scene scene, double level) {
    body = _world.addBody(
      position: Vector3(boatX, level + 0.2, boatZ),
      // Its hull, half again as heavy as it is big would float it a third
      // under: a wooden launch.
      mass: 900.0,
    );
    _world
      ..setShape(body, NativeShape.box(Vector3(2.4, 0.4, 1.0)))
      ..lockRotation(body);
    final anchor = _world.addBody(
      position: Vector3(boatX - 6.0, floorAt(boatX - 6.0, boatZ) + 0.2, boatZ),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    _world.setShape(anchor, const NativeShape.sphere(0.2));
    final rope = _world.createDistanceJoint(
      anchor,
      body,
      anchorA: _world.positionOf(anchor),
      anchorB: _world.positionOf(body) + Vector3(-2.2, 0, 0),
    );
    _world
      ..setJointSpring(rope, (hertz: 0.0, damping: 0.0))
      ..setJointLength(
        rope,
        length:
            (_world.positionOf(anchor) - _world.positionOf(body)).length + 1.0,
        least: 0.0,
        most:
            (_world.positionOf(anchor) - _world.positionOf(body)).length + 1.0,
      );
    Material paint(Vector4 colour) =>
        Material(name: 'boat', baseColor: colour, roughness: 0.6);
    look = SceneNode(name: 'boat')
      ..add(
        MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3(4.8, 0.8, 2.0)).build(),
          ),
          paint(Vector4(0.85, 0.82, 0.76, 1.0)),
          name: 'hull',
        ),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3(1.4, 0.9, 1.4)).build(),
          ),
          paint(Vector4(0.16, 0.30, 0.48, 1.0)),
          name: 'cabin',
        )..setPosition(0.6, 0.85, 0),
      );
    scene.add(look);
  }

  final NativeWorld _world;
  late final NativeBody body;
  late final SceneNode look;

  Vector3 get position => _world.positionOf(body);

  /// Whether [at] is alongside, near enough to be hauled aboard.
  bool alongside(Vector3 at) =>
      Vector2(at.x - position.x, at.z - position.z).length < 4.0 &&
      at.y > position.y - 1.5;

  void update() {
    final p = position;
    look.setPosition(p.x, p.y, p.z);
  }
}
