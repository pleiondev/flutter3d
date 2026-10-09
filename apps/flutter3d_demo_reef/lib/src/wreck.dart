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
    bodies.add(body);
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
    bodies.add(mast);
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

  /// Her timbers and her mast, as the world has them.
  final List<NativeBody> bodies = <NativeBody>[];

  /// How deep her hull is sunk in the sand, m: down to where her sides
  /// begin to turn under, so what stands of her stands as high as her
  /// timbers do.
  static const double _sunk = 0.6;
}

/// Where the hull that is drawn stands, read off its own vertices: for
/// each half metre of her length and each quarter metre of height, how far
/// out her planking is on either side. What grows on the reef asks it
/// whether a branch would be inside her, and where her side is to grow on.
///
/// Her boxes are what the diver meets of her, and are narrower than the
/// planking at her turn of bilge and lower at her ends, where her stern
/// stands near six metres over the sand: asked of them, a sea fan could
/// stand through her planking into the hold.
final class HullRoom {
  /// The hull from the [pieces] of the model `wreck.dart` draws her with,
  /// each its vertices and where it sits in the model.
  HullRoom(Iterable<(MeshData, Matrix4)> pieces) {
    for (final (data, place) in pieces) {
      final v = data.vertices;
      final stride = data.layout.floatsPerVertex;
      for (var o = 0; o < v.length; o += stride) {
        final p = place.transformed3(Vector3(v[o], v[o + 1], v[o + 2]));
        // Her frame as drawn: along her keel, up from the sand at her
        // middle, across to starboard.
        final key = (_slice(p.x), _band(p.y - Wreck._sunk), p.z >= 0.0);
        final out = p.z.abs();
        if (out > (_out[key] ?? -1.0)) _out[key] = out;
      }
    }
  }

  /// How far out her planking stands, by slice of her length, band of
  /// height and side, starboard true.
  final Map<(int, int, bool), double> _out = <(int, int, bool), double>{};

  static const double _length = 0.5, _height = 0.25;
  static int _slice(double along) => (along / _length).floor();
  static int _band(double up) => (up / _height).floor();

  /// [at] in her frame: along her keel from her middle, up from the sand
  /// there, and across to starboard.
  static Vector3 frame(Vector3 at) {
    final dx = at.x - wreckX, dz = at.z - wreckZ;
    return Vector3(
      dx * wreckTurn.cos + dz * wreckTurn.sin,
      at.y - wreckFloor,
      -dx * wreckTurn.sin + dz * wreckTurn.cos,
    );
  }

  /// [frame] undone: the point [along], [up] and [across] in her frame.
  static Vector3 world(double along, double up, double across) => Vector3(
    wreckX + along * wreckTurn.cos - across * wreckTurn.sin,
    wreckFloor + up,
    wreckZ + along * wreckTurn.sin + across * wreckTurn.cos,
  );

  /// Whether [at] is inside her, or within [margin] of her planking: within
  /// her widest planking, either side, over the slices and bands [reach]
  /// round it — one by default, as her vertices may stand that far apart
  /// along a long plank; nought for what grows on her side, which stands
  /// past her planking in its own slice and band. The hold counts as inside
  /// up to her standing side where the other has broken away, and above her
  /// highest timbers nothing is.
  bool holds(Vector3 at, {double margin = 0.0, int reach = 1}) {
    final p = frame(at);
    final i = _slice(p.x), j = _band(p.y);
    var widest = -1.0;
    for (var di = -reach; di <= reach; di++) {
      for (var dj = -reach; dj <= reach; dj++) {
        for (final starboard in const <bool>[false, true]) {
          final out = _out[(i + di, j + dj, starboard)];
          if (out != null && out > widest) widest = out;
        }
      }
    }
    return widest >= 0.0 && p.z.abs() < widest + margin;
  }

  /// How far out her planking stands on the [starboard] side or the other,
  /// [along] her keel and [up] over the sand, or null where she has no side
  /// there.
  double? side(double along, double up, {required bool starboard}) =>
      _out[(_slice(along), _band(up), starboard)];
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
    _drop();
    // Bow to the west, into the current, with the anchor's rope off her
    // stem: the way a boat lies at anchor in a stream.
    look = launchLook(device)
      ..setRotation(Quaternion.axisAngle(Vector3(0, 1, 0), math.pi));
    scene.add(look);
  }

  final NativeWorld _world;
  late final NativeBody body;
  late final SceneNode look;

  /// What the launch's engine pulls with at a standstill, N: a small
  /// inboard's; the water's drag on the hull sets how fast that drives her.
  static const double _pull = 1500.0;

  /// Her anchor on the bottom and its rope, while she lies to it.
  NativeBody? _anchor;
  NativeJoint? _rope;

  /// Anchor down six metres up-current of her, on a rope a metre longer
  /// than the way to it: she lies to it bow to the current.
  void _drop() {
    final p = _world.localPositionOf(body);
    final anchor = _world.addBody(
      position: Vector3(p.x - 6.0, floorAt(p.x - 6.0, p.z) + 0.2, p.z),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    _world.setShape(anchor, const NativeShape.sphere(0.2));
    final from = _world.localPositionOf(body) + Vector3(-2.2, 0, 0);
    final rope = _world.createDistanceJoint(
      anchor,
      body,
      anchorA: _world.localPositionOf(anchor),
      anchorB: from,
    );
    final length =
        (_world.localPositionOf(anchor) - _world.localPositionOf(body)).length +
        1.0;
    _world
      ..setJointSpring(rope, (hertz: 0.0, damping: 0.0))
      ..setJointLength(rope, length: length, least: 0.0, most: length);
    _anchor = anchor;
    _rope = rope;
  }

  /// Anchor up, and her engine pulling her towards [at].
  void motorTo(Vector3 at) {
    if (_rope != null) {
      _world
        ..removeJoint(_rope!)
        ..removeBody(_anchor!);
      _rope = null;
      _anchor = null;
    }
    final p = position;
    final way = Vector3(at.x - p.x, 0.0, at.z - p.z);
    if (way.length2 == 0.0) return;
    _world
      ..wake(body)
      ..addForce(body, way.normalized() * _pull);
  }

  /// Engine off, and her anchor down where she is, if it is up.
  void stop() {
    if (_rope == null) _drop();
  }

  Vector3 get position => _world.localPositionOf(body);

  /// Her anchor and its rope, by their handles, or nulls while she motors.
  Map<String, Object?> save() => <String, Object?>{
    'anchor': _anchor?.raw,
    'rope': _rope?.raw,
  };

  /// Back to what [save] wrote, the world already restored under it.
  void restore(Object? saved) {
    final anchor = saved is Map ? saved['anchor'] : null;
    final rope = saved is Map ? saved['rope'] : null;
    _anchor = anchor is num ? NativeBody(anchor.toInt()) : null;
    _rope = rope is num ? NativeJoint(rope.toInt()) : null;
  }

  /// Whether [at] is alongside, near enough to be hauled aboard.
  bool alongside(Vector3 at) =>
      Vector2(at.x - position.x, at.z - position.z).length < 4.0 &&
      at.y > position.y - 1.5;

  void update() {
    final p = position;
    look.setPosition(p.x, p.y, p.z);
  }
}
