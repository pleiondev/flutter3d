/// What grows on Wreck Reef and what lies about on it: coral heads of
/// branching staghorn and rounded brain coral, plates of table coral, sea
/// fans standing across the current, tube sponges, whips, and boulders down
/// the wall and on the sand.
///
/// None of it is solid. The coral heads the diver bumps into are the
/// floor's own mounds; what grows on them is drawn over them, a thing to
/// swim among. Every growth is built here from the engine's shapes, bent and
/// painted vertex by vertex, and all of it merged into one mesh, so a reef of
/// a few hundred colonies is one draw. Nobody publishes coral as free models
/// fit to put in a repository; it is easier to grow it.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:vector_math/vector_math.dart';

import 'looks.dart';
import 'terrain.dart';
import 'wreck.dart' show HullRoom;

/// Colours a colony may be, linear: what they are under white light, before
/// the water takes the red out of them.
final List<Vector4> _staghorn = <Vector4>[
  Vector4(0.62, 0.48, 0.26, 1.0),
  Vector4(0.50, 0.42, 0.30, 1.0),
  Vector4(0.42, 0.30, 0.55, 1.0),
];
final List<Vector4> _fans = <Vector4>[
  Vector4(0.50, 0.10, 0.45, 1.0),
  Vector4(0.80, 0.22, 0.10, 1.0),
  Vector4(0.85, 0.65, 0.15, 1.0),
];
final List<Vector4> _sponges = <Vector4>[
  Vector4(0.90, 0.42, 0.10, 1.0),
  Vector4(0.40, 0.12, 0.45, 1.0),
  Vector4(0.85, 0.75, 0.20, 1.0),
];

/// Where growth must leave room: the finds, so a bag can be tied without
/// a coral standing through the diver's hands, and the boat's mooring.
const List<(double, double, double)> _clear = <(double, double, double)>[
  (23.5, 21.0, 1.8),
  (37.0, 30.5, 1.8),
  (50.0, 24.0, 1.8),
  (6.0, 32.0, 1.5),
];

/// The reef's growth and its boulders, added to [scene]; nothing of either
/// inside the [hull].
final class ReefLife {
  ReefLife(
    GraphicsDevice device,
    Scene scene,
    SeabedLook floor,
    List<ReefModel> rocks,
    HullRoom hull, {
    bool light = false,
  }) {
    final random = math.Random(7);
    double rand(double a, double b) => a + (b - a) * random.nextDouble();
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          MeshData.merge(growReef(hull, random, light: light)),
        ),
        floor.under('coral', Vector4(1.0, 1.0, 1.0, 1.0), roughness: 0.8),
        name: 'coral',
      ),
    );

    // Boulders: fallen from the wall and lying at its foot, a few out on
    // the flat. Each kind is merged into one mesh of its own picture.
    final placed = <List<MeshData>>[for (final _ in rocks) <MeshData>[]];
    for (var k = 0; k < (light ? 30 : 70); k++) {
      final z = rand(1.0, reefSize - 1.0);
      final edge = wallTop + 2.0 * math.sin(z * 0.21);
      final x = k % 4 == 0
          ? rand(2.0, edge)
          : edge +
                (wallFoot - wallTop) * math.pow(rand(0.0, 1.0), 0.6) +
                rand(-1.0, 2.5);
      if (!_free(x, z) || x > reefSize - 1.0) continue;
      final which = random.nextInt(rocks.length);
      final size = k % 4 == 0 ? rand(0.3, 0.8) : rand(0.5, 2.2);
      final place = Matrix4.compose(
        Vector3(x, drawnFloorAt(x, z) - size * 0.25, z),
        Quaternion.axisAngle(Vector3(0, 1, 0), rand(0, math.pi * 2)) *
            Quaternion.axisAngle(Vector3(1, 0, 0), rand(-0.3, 0.3)),
        Vector3(size * rand(0.8, 1.3), size, size * rand(0.8, 1.3)),
      );
      if (_inShip(x, z)) continue;
      final boulder = <MeshData>[
        for (final piece in rocks[which].pieces)
          piece.data.transformed(place * piece.place),
      ];
      if (!_clearOf(hull, boulder)) continue;
      placed[which].addAll(boulder);
    }
    for (var i = 0; i < rocks.length; i++) {
      if (placed[i].isEmpty) continue;
      final piece = rocks[i].pieces.first;
      scene.add(
        MeshNode(
          DeviceMesh.upload(device, MeshData.merge(placed[i])),
          // Lightened from the scan's dark brown and turned a little green:
          // the pale crust and the weed on anything that lies long in the
          // sea, which is what the water has to show from any distance.
          underWith(
            floor,
            'rock',
            Vector4(1.5, 1.65, 1.4, 1.0),
            picture: piece.picture,
            roughness: 0.95,
          ),
          name: 'boulders',
        ),
      );
    }
  }
}

/// Whether (x, z) is clear of the places growth must leave room at.
bool _free(double x, double z) => !_clear.any(
  (c) => (x - c.$1) * (x - c.$1) + (z - c.$2) * (z - c.$2) < c.$3 * c.$3,
);

/// Whether no vertex of [parts] is inside the [hull] or within a hand's
/// breadth of her planking, over [reach] of her slices round it.
bool _clearOf(HullRoom hull, List<MeshData> parts, {int reach = 1}) {
  for (final part in parts) {
    final v = part.vertices;
    final stride = part.layout.floatsPerVertex;
    for (var o = 0; o < v.length; o += stride) {
      if (hull.holds(
        Vector3(v[o], v[o + 1], v[o + 2]),
        margin: 0.1,
        reach: reach,
      )) {
        return false;
      }
    }
  }
  return true;
}

/// What grows on the reef, colony by colony, drawn from [random]: on the
/// coral heads, down the wall, out on the plain and on the [hull]'s sides.
///
/// Nothing grows in the ship. A colony is made whole and then kept only
/// if none of it is inside her: rooted outside her footprint, a fan or a
/// clump of sponges a metre across may still lean in through her planking,
/// and from the hold it would be seen standing there. What is dropped was
/// made all the same, so the reef round her is what it was.
List<MeshData> growReef(
  HullRoom hull,
  math.Random random, {
  bool light = false,
}) {
  final parts = <MeshData>[];
  double rand(double a, double b) => a + (b - a) * random.nextDouble();
  Vector4 pick(List<Vector4> from) =>
      from[random.nextInt(from.length)] * rand(0.85, 1.1)
        ..w = 1.0;
  Vector3 ground(double x, double z) =>
      Vector3(x, drawnFloorAt(x, z) - 0.05, z);
  // One colony grown at (x, z) by [grow], and kept if it is clear of her.
  void colony(double x, double z, void Function(List<MeshData> grown) grow) {
    final grown = <MeshData>[];
    grow(grown);
    if (!_inShip(x, z) && _clearOf(hull, grown)) parts.addAll(grown);
  }

  // On each coral head, a crowd: a brain coral or two, branching
  // staghorn, a table, and fans along its flanks.
  for (final (cx, cz, r, _) in coralHeads) {
    for (var k = 0; k < (light ? 6 : 14); k++) {
      final a = rand(0, math.pi * 2), d = r * math.sqrt(rand(0.0, 0.9));
      final x = cx + math.cos(a) * d, z = cz + math.sin(a) * d;
      if (!_free(x, z)) continue;
      final at = ground(x, z);
      colony(x, z, (grown) {
        switch (k % 5) {
          case 0:
            grown.add(_brain(at, rand(0.4, 0.9), pick(_staghorn), random));
          case 1 || 3:
            _staghornColony(grown, at, rand(0.5, 0.9), pick(_staghorn), random);
          case 2:
            grown.add(_table(at, rand(0.4, 0.8), pick(_staghorn), random));
          default:
            _fan(grown, at, rand(0.6, 1.3), pick(_fans), random);
        }
      });
    }
  }
  // Down the wall and along the flat's edge, a scatter of everything.
  for (var k = 0; k < (light ? 60 : 160); k++) {
    final z = rand(1.0, reefSize - 1.0);
    final edge = wallTop + 2.0 * math.sin(z * 0.21);
    final x = edge + rand(-5.0, wallFoot - wallTop + 1.0);
    if (!_free(x, z)) continue;
    final at = ground(x, z);
    colony(x, z, (grown) {
      switch (random.nextInt(6)) {
        case 0:
          grown.add(_brain(at, rand(0.3, 0.7), pick(_staghorn), random));
        case 1:
          _staghornColony(grown, at, rand(0.3, 0.7), pick(_staghorn), random);
        case 2 || 3:
          _fan(grown, at, rand(0.5, 1.2), pick(_fans), random);
        case 4:
          _sponge(grown, at, rand(0.3, 0.8), pick(_sponges), random);
        default:
          _whips(grown, at, rand(0.6, 1.4), pick(_fans), random);
      }
    });
  }
  // On the plain, far apart: sponges, whips, the odd fan.
  for (var k = 0; k < (light ? 20 : 50); k++) {
    final x = rand(wallFoot + 1.0, reefSize - 1.0),
        z = rand(1.0, reefSize - 1.0);
    if (!_free(x, z)) continue;
    final at = ground(x, z);
    colony(x, z, (grown) {
      switch (random.nextInt(3)) {
        case 0:
          _sponge(grown, at, rand(0.3, 0.7), pick(_sponges), random);
        case 1:
          _whips(grown, at, rand(0.5, 1.0), pick(_fans), random);
        default:
          _fan(grown, at, rand(0.4, 0.9), pick(_fans), random);
      }
    });
  }
  // And on her sides, where hard ground stands off the sand: rooted on her
  // planking where it stands, outside it, fans spread along it rather than
  // across it, as a fan on a wall grows flat to the wall. Where she has no
  // side at that height — her broken port side, her narrowing ends below
  // where they were asked — nothing.
  final keel = Vector3(math.cos(wreckHeading), 0.0, math.sin(wreckHeading));
  for (var k = 0; k < (light ? 4 : 10); k++) {
    final along = rand(-7.0, 7.0), up = rand(1.2, 2.0);
    final starboard = random.nextBool();
    final fan = k.isEven;
    final size = fan ? rand(0.4, 0.8) : rand(0.2, 0.4);
    final color = pick(fan ? _fans : _sponges);
    final out = hull.side(along, up, starboard: starboard);
    if (out == null) continue;
    final at = HullRoom.world(
      along,
      up,
      (starboard ? 1.0 : -1.0) * (out + 0.05),
    );
    final grown = <MeshData>[];
    if (fan) {
      _fan(grown, at, size, color, random, plane: keel);
    } else {
      _sponge(grown, at, size, color, random);
    }
    if (_clearOf(hull, grown, reach: 0)) parts.addAll(grown);
  }
  return parts;
}

/// A tapered rod from [from] to [to], radius [r0] at its foot and [r1] at
/// its end, in [color].
MeshData _rod(
  Vector3 from,
  Vector3 to,
  double r0,
  double r1,
  Vector4 color, {
  int sides = 6,
}) {
  final along = to - from;
  final length = along.length;
  final turn = Quaternion.fromTwoVectors(
    Vector3(0, 1, 0),
    along / math.max(length, 1e-6),
  );
  return CylinderShape(
        radiusTop: r1,
        radiusBottom: r0,
        height: length,
        segments: sides,
        capped: false,
      )
      .build()
      .transformed(
        Matrix4.compose(from + along * 0.5, turn, Vector3(1.0, 1.0, 1.0)),
      )
      .withColor(color.toLinearColor());
}

/// Staghorn: a clump of branches forking upwards and outwards, each fork
/// thinner and paler towards a growing tip.
void _staghornColony(
  List<MeshData> parts,
  Vector3 at,
  double size,
  Vector4 color,
  math.Random random,
) {
  void grow(
    Vector3 from,
    Vector3 heading,
    double length,
    double radius,
    int depth,
  ) {
    final to = from + heading * length;
    final tip =
        color + (Vector4(0.95, 0.92, 0.85, 1.0) - color) * (0.5 / depth);
    parts.add(_rod(from, to, radius, radius * 0.75, tip..w = 1.0, sides: 5));
    if (depth >= 4) return;
    for (var k = 0; k < 2; k++) {
      final bend = Vector3(
        random.nextDouble() - 0.5,
        0.6 + random.nextDouble() * 0.4,
        random.nextDouble() - 0.5,
      );
      final next = (heading + bend * 0.7)..normalize();
      grow(to, next, length * 0.78, radius * 0.75, depth + 1);
    }
  }

  for (var k = 0; k < 5; k++) {
    final a = random.nextDouble() * math.pi * 2;
    final heading = Vector3(math.cos(a) * 0.5, 1.0, math.sin(a) * 0.5)
      ..normalize();
    grow(at, heading, size * 0.35, size * 0.05, 1);
  }
}

/// A rounded boulder of brain coral: a squashed ball, its meandering
/// ridges and valleys painted lighter and darker across it.
MeshData _brain(Vector3 at, double size, Vector4 color, math.Random random) {
  final ball = const SphereShape(radius: 1.0, segments: 44, rings: 26).build();
  final v = ball.vertices;
  final stride = ball.layout.floatsPerVertex;
  final colorAt = ball.layout.floatOffsetOf(VertexLayout.color.name);
  final phase = random.nextDouble() * 10.0;
  for (var o = 0; o < v.length; o += stride) {
    final x = v[o], y = v[o + 1], z = v[o + 2];
    final meander = math.sin(
      14.0 * (x + 0.3 * math.sin(5.0 * z + phase)) + 4.0 * y,
    );
    final ridge = 1.0 + 0.05 * meander;
    v[o] = x * ridge;
    v[o + 1] = math.max(y, -0.15) * 0.65 * ridge;
    v[o + 2] = z * ridge;
    final shade = 0.55 + 0.3 * meander;
    v[colorAt] = color.x * shade;
    v[colorAt + 1] = color.y * shade;
    v[colorAt + 2] = color.z * shade;
    v[colorAt + 3] = 1.0;
  }
  return ball.transformed(
    Matrix4.compose(
      at + Vector3(0, size * 0.05, 0),
      Quaternion.axisAngle(Vector3(0, 1, 0), random.nextDouble() * 6.0),
      Vector3(size, size, size),
    ),
  );
}

/// Table coral: a broad thin plate held up on a short stalk.
MeshData _table(Vector3 at, double size, Vector4 color, math.Random random) {
  final top = at + Vector3(0, size * 0.45, 0);
  return MeshData.merge(<MeshData>[
    _rod(
      at,
      top,
      size * 0.12,
      size * 0.08,
      color * 0.8
        ..w = 1.0,
    ),
    CylinderShape(
          radiusTop: size,
          radiusBottom: size * 0.85,
          height: size * 0.06,
          segments: 14,
        )
        .build()
        .transformed(
          Matrix4.compose(
            top,
            Quaternion.axisAngle(
              Vector3(1, 0, 0),
              (random.nextDouble() - 0.5) * 0.3,
            ),
            Vector3(1.0, 1.0, 0.8 + random.nextDouble() * 0.3),
          ),
        )
        .withColor(color.toLinearColor()),
  ]);
}

/// A sea fan: a flat lattice of fine branches in one plane, set across
/// the current, which runs from west to east, as fans grow to sieve it —
/// or, on a wall, along the level line [plane] of the wall.
void _fan(
  List<MeshData> parts,
  Vector3 at,
  double size,
  Vector4 color,
  math.Random random, {
  Vector3? plane,
}) {
  // The fan's plane holds up and north–south, give or take.
  final a = (random.nextDouble() - 0.5) * 0.6;
  final side = plane ?? Vector3(math.sin(a), 0, math.cos(a));
  void grow(
    Vector3 from,
    double angle,
    double length,
    double radius,
    int depth,
  ) {
    final heading = Vector3(0, math.cos(angle), 0) + side * math.sin(angle);
    final to = from + heading * length;
    parts.add(_rod(from, to, radius, radius * 0.8, color, sides: 4));
    if (depth >= 6) return;
    final spread = 0.35 + random.nextDouble() * 0.25;
    grow(to, angle - spread, length * 0.8, radius * 0.8, depth + 1);
    grow(to, angle + spread, length * 0.8, radius * 0.8, depth + 1);
  }

  final trunk = at + Vector3(0, size * 0.15, 0);
  parts.add(
    _rod(
      at,
      trunk,
      size * 0.035,
      size * 0.03,
      color * 0.7
        ..w = 1.0,
      sides: 5,
    ),
  );
  grow(trunk, 0.0, size * 0.2, size * 0.02, 1);
}

/// Tube sponges: a few hollow upright tubes, each its colour outside and
/// a dark mouth.
void _sponge(
  List<MeshData> parts,
  Vector3 at,
  double size,
  Vector4 color,
  math.Random random,
) {
  final count = 2 + random.nextInt(4);
  for (var k = 0; k < count; k++) {
    final a = random.nextDouble() * math.pi * 2;
    final foot = at + Vector3(math.cos(a), 0, math.sin(a)) * (size * 0.18 * k);
    final height = size * (0.6 + random.nextDouble() * 0.6);
    final lean = Vector3(
      random.nextDouble() - 0.5,
      4.0,
      random.nextDouble() - 0.5,
    )..normalize();
    final r = size * (0.10 + random.nextDouble() * 0.05);
    // Turned: narrow at its foot, swelling and pinching on the way up and
    // flaring to a rolled lip; inside, the dark hollow going down.
    final h = height;
    final place = Matrix4.compose(
      foot,
      Quaternion.fromTwoVectors(Vector3(0, 1, 0), lean),
      Vector3(1.0, 1.0, 1.0),
    );
    MeshData turned(List<(double, double)> profile, Vector4 shade) =>
        LatheShape(
              profile: <Vector2>[
                for (final (across, up) in profile) Vector2(r * across, h * up),
              ],
              segments: 10,
            )
            .build()
            .transformed(place)
            .withColor((shade..w = 1.0).toLinearColor());
    parts
      ..add(
        turned(<(double, double)>[
          (0.0, -0.05),
          (0.7, -0.05),
          (0.95, 0.25),
          (0.88, 0.55),
          (1.0, 0.85),
          (1.18, 0.98),
          (1.1, 1.0),
        ], color),
      )
      ..add(
        turned(<(double, double)>[
          (1.1, 1.0),
          (0.92, 0.97),
          (0.78, 0.8),
          (0.0, 0.7),
        ], color * 0.15),
      );
  }
}

/// Sea whips: long single stems bending over in the current.
void _whips(
  List<MeshData> parts,
  Vector3 at,
  double size,
  Vector4 color,
  math.Random random,
) {
  final count = 3 + random.nextInt(4);
  for (var k = 0; k < count; k++) {
    var from =
        at +
        Vector3(random.nextDouble() - 0.5, 0, random.nextDouble() - 0.5) * 0.3;
    var heading = Vector3(
      random.nextDouble() - 0.5,
      3.0,
      random.nextDouble() - 0.5,
    )..normalize();
    final bend = 0.15 + random.nextDouble() * 0.15;
    const steps = 6;
    for (var s = 0; s < steps; s++) {
      final to = from + heading * (size / steps);
      final r = size * 0.018 * (1.0 - s / (steps + 1));
      parts.add(_rod(from, to, r, r * 0.85, color, sides: 4));
      from = to;
      // The current, from the west, bends each joint a little east.
      heading = (heading + Vector3(bend, 0, 0))..normalize();
    }
  }
}

/// Whether (x, z) is in the ship's footprint, her length and beam and the
/// mast lying two metres off her port side, grown by half a metre.
bool _inShip(double x, double z) {
  final dx = x - wreckX, dz = z - wreckZ;
  final along = dx * math.cos(wreckHeading) + dz * math.sin(wreckHeading);
  final across = -dx * math.sin(wreckHeading) + dz * math.cos(wreckHeading);
  return along.abs() < wreckHalfLength + 0.5 &&
      across > -(wreckHalfBeam + 2.5) &&
      across < wreckHalfBeam + 0.5;
}
