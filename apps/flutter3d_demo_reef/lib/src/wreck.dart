/// The sunken ship and the boat over the reef: the one a fixed body of
/// timbers lying on the sand, the other afloat on the sea, held by its
/// anchor's rope against the current.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'launch.dart';
import 'looks.dart';
import 'terrain.dart';

/// Where the ship's timbers rest: the floor under its middle.
double get wreckFloor => floorAt(wreckX, wreckZ);

/// The ship: a keel and bottom, one side whole and the other broken off,
/// her stem and stern posts, three deck beams across the open hold, and the
/// mast fallen beside her — solid as boxes, drawn as [look], a ship's hull
/// the sea has had for a long time.
final class Wreck {
  Wreck(
    NativeWorld world,
    GraphicsDevice device,
    Scene scene,
    SeabedLook floor,
    ReefModel look,
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
          turn.asRotationMatrix().transformed(world.compoundOffset(shape)),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world
      ..setCompound(body, shape)
      ..setOrientation(body, turn);
    final ship = SceneNode(name: 'wreck')
      ..setPosition(wreckX, wreckFloor, wreckZ)
      ..setRotation(turn);
    // What is drawn is a ship's hull, cut down to what the sand kept, sunk
    // to her turn of bilge in the scour; the boxes above are what the diver
    // meets of her. The deck beams are the one piece of them drawn as they
    // are: the hull lost its decks, and three beams still span the hold.
    // Her planking was painted dark and tarred; a century under water has
    // bleached the wood grey and grown it over green, so the picture's
    // grain is kept and its colour lifted towards that.
    final weathered = Vector4(1.7, 1.85, 1.6, 1.0);
    ship.add(
      look.dress(floor, name: 'hull', recolour: (_) => weathered, lined: device)
        ..setPosition(0.0, -_sunk, 0.0),
    );
    final timber = underWith(
      floor,
      'timber',
      weathered,
      picture: look.pieces.first.picture,
    );
    // Where her port side has fallen away, each beam's end still stands on
    // the hold's stanchion under it: a post from her floor up, drawn
    // only, too slight for a diver to be stopped by.
    for (final (half, at, lean) in pieces.skip(5)) {
      final stanchion = at.z - half.z + 0.3;
      ship
        ..add(
          MeshNode(
              DeviceMesh.upload(device, CuboidShape(size: half * 2.0).build()),
              timber,
              name: 'beam',
            )
            ..setPosition(at.x, at.y, at.z)
            ..setRotation(Quaternion.axisAngle(Vector3(1, 0, 0), lean)),
        )
        ..add(
          MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3(0.16, at.y - half.y, 0.16)).build(),
            ),
            timber,
            name: 'stanchion',
          )..setPosition(at.x, (at.y - half.y) / 2, stanchion),
        );
    }
    // The mast, fallen across the sand off her broken side.
    final mastAt = Vector3(1.5, 0.25, -wreckHalfBeam - 2.0);
    final mast = world.addBody(
      position:
          Vector3(wreckX, wreckFloor, wreckZ) +
          turn.asRotationMatrix().transformed(mastAt),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    final lying = turn * Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2);
    world
      ..setShape(mast, const NativeShape.cylinder(0.2, 6.0))
      ..setOrientation(mast, lying);
    // Snapped a third of the way up: the stump end ragged, the top with its
    // cap still on, half in the sand.
    ship.add(
      MeshNode(
          DeviceMesh.upload(
            device,
            MeshData.merge(<MeshData>[
              const CylinderShape(
                radiusTop: 0.15,
                radiusBottom: 0.21,
                height: 11.0,
                segments: 12,
              ).build().transformed(Matrix4.translationValues(0, -0.5, 0)),
              const ConeShape(
                radius: 0.21,
                height: 0.5,
                segments: 12,
              ).build().transformed(
                Matrix4.compose(
                  Vector3(0.05, -6.1, 0),
                  Quaternion.axisAngle(Vector3(1, 0, 0), math.pi),
                  Vector3(1.0, 1.0, 1.0),
                ),
              ),
              CuboidShape(
                size: Vector3(0.7, 0.25, 0.5),
              ).build().transformed(Matrix4.translationValues(0, 5.1, 0)),
            ]),
          ),
          timber,
          name: 'mast',
        )
        ..setPosition(mastAt.x, mastAt.y - 0.08, mastAt.z)
        ..setRotation(Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2)),
    );
    scene.add(ship);
  }

  /// How deep her hull is sunk in the sand, m: down to where her sides
  /// begin to turn under, so what stands of her stands as high as her
  /// timbers do.
  static const double _sunk = 0.6;
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
    // Bow to the west, into the current, with the anchor's rope off her
    // stem: the way a boat lies at anchor in a stream.
    look = launchLook(device)
      ..setRotation(Quaternion.axisAngle(Vector3(0, 1, 0), math.pi));
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
