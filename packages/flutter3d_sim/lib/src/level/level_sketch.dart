import 'dart:math' as math;
import 'dart:typed_data';

import 'level_format_exception.dart';

/// Level geometry as the rows a document writes, before anything reads them.
///
/// **Rows rather than [Brush]es, because two kinds of caller want them.** A
/// recipe in a level (see `expandRecipes`) turns into brushes when the level is
/// read, and a generator in a tool writes the same rows into a document that is
/// committed and diffed. Both need the arithmetic of a wall with a door cut in
/// it, and both need it to produce the same numbers, so the arithmetic lives
/// once, here, and speaks the document's own vocabulary: an `at`, a `size`, a
/// `material`, and only the keys that say something a default does not.
///
/// What a row looks like is the format's, not this class's — a row is exactly
/// what `Brush.fromJson` reads, which is how an expanded recipe and a hand
/// written brush end up indistinguishable.
final class LevelSketch {
  /// The brush rows, in the order they were drawn.
  final List<Map<String, Object?>> brushes = <Map<String, Object?>>[];

  /// The entity rows. A room adds its reflection probes here.
  final List<Map<String, Object?>> entities = <Map<String, Object?>>[];

  /// The light rows.
  final List<Map<String, Object?>> lights = <Map<String, Object?>>[];

  /// How thick a wall, a floor and a ceiling are.
  ///
  /// One number, because rooms whose walls vary in thickness read as rooms
  /// somebody built twice — and because two rooms whose centres are their
  /// sizes plus this apart share a wall rather than overlapping.
  static const double thickness = 1.0;

  /// Where a ceiling goes when a room does not say: head height, plus enough
  /// that a torch on the wall is not in anybody's eye.
  static const double defaultHeight = 4.0;

  /// How far one reflection probe is trusted to stand for, in metres.
  ///
  /// Past it, the picture a probe took is a view from another part of the room,
  /// which reads as a reflection of the wrong wall rather than as a blur.
  static const double probeReach = 10.0;

  /// One box, as it is.
  ///
  /// [shadows] is one of the four words `ShadowCasting` spells; see
  /// [shadowKeys] for which of them a row writes down. A brush that is drawn
  /// and stops nothing — water — says so with [solid].
  Map<String, Object?> box(
    List<num> at,
    List<num> size,
    String material, {
    String shadows = 'on',
    bool solid = true,
  }) {
    final row = <String, Object?>{
      'at': roundedVector(at),
      'size': roundedVector(size),
      'material': material,
      ...shadowKeys(shadows),
      if (!solid) 'solid': false,
    };
    brushes.add(row);
    return row;
  }

  /// A room: floor, ceiling, and four walls with [doors] cut through them.
  ///
  /// [centre] is the middle of the floor and [size] the inside, read in X and
  /// Z; its Y is ignored and [height] is the height. [base] is where the floor's
  /// top face stands, and [height] is measured from it — so a sunken room's
  /// walls reach the same ceiling as its neighbours' when it is asked to.
  ///
  /// **North is −Z**, the direction a camera faces at yaw zero. The sides are
  /// named by the axis rather than by any compass in a fiction.
  ///
  /// With [probe], `reflection_probe` entities stand half way up on a grid
  /// across the room, as few as leave nothing further than [probeReach] from
  /// one — a probe is a picture taken from a point, and a hall is not a point.
  void room(
    List<num> centre,
    List<num> size, {
    double height = defaultHeight,
    double base = 0.0,
    String floor = 'floor',
    String wall = 'wall',
    String ceiling = 'ceiling',
    List<RoomDoor> doors = const <RoomDoor>[],
    bool ceilinged = true,
    bool probe = true,
  }) {
    final cx = centre[0].toDouble();
    final cz = centre[2].toDouble();
    final w = size[0].toDouble();
    final d = size[2].toDouble();
    final x0 = cx - w / 2.0, x1 = cx + w / 2.0;
    final z0 = cz - d / 2.0, z1 = cz + d / 2.0;

    box(
      <num>[cx, base - thickness / 2.0, cz],
      <num>[w + thickness * 2, thickness, d + thickness * 2],
      floor,
    );
    // Half way up this room's own walls, which is not half way up the level: a
    // sunken room's probe placed from zero would stand in its own ceiling.
    if (probe) {
      for (final (px, pz) in _probeGrid(cx, cz, w, d)) {
        entities.add(<String, Object?>{
          'type': 'reflection_probe',
          'at': roundedVector(<num>[px, base + height / 2.0, pz]),
        });
      }
    }
    if (ceilinged) {
      box(
        <num>[cx, base + height + thickness / 2.0, cz],
        <num>[w + thickness * 2, thickness, d + thickness * 2],
        ceiling,
      );
    }

    final holes = <String, List<_Hole>>{
      'north': <_Hole>[],
      'south': <_Hole>[],
      'east': <_Hole>[],
      'west': <_Hole>[],
    };
    for (final door in doors) {
      final side =
          holes[door.side] ??
          (throw LevelFormatException(
            'a room has a door on its '
            '"${door.side}" side, which is not north, south, east or west',
          ));
      final along =
          (door.side == 'north' || door.side == 'south' ? cx : cz) +
          door.offset;
      final low = door.sill ?? base;
      side.add((
        centre: along,
        width: door.width,
        sill: low,
        top: low + door.height,
      ));
    }

    _wallWithHoles(
      z0 - thickness / 2.0,
      _Axis.x,
      (x0 - thickness, x1 + thickness),
      base,
      height,
      holes['north']!,
      wall,
    );
    _wallWithHoles(
      z1 + thickness / 2.0,
      _Axis.x,
      (x0 - thickness, x1 + thickness),
      base,
      height,
      holes['south']!,
      wall,
    );
    _wallWithHoles(
      x1 + thickness / 2.0,
      _Axis.z,
      (z0, z1),
      base,
      height,
      holes['east']!,
      wall,
    );
    _wallWithHoles(
      x0 - thickness / 2.0,
      _Axis.z,
      (z0, z1),
      base,
      height,
      holes['west']!,
      wall,
    );
  }

  /// A passage between two points along one axis: a room with no probes.
  ///
  /// Refuses a diagonal rather than building a staircase of boxes — a corridor
  /// that is not axis-aligned is either two corridors or a mistake, and both
  /// are better said by the caller. The points' heights are ignored; [base] is
  /// the floor.
  void corridor(
    List<num> from,
    List<num> to, {
    double width = 3.0,
    double height = 3.0,
    double base = 0.0,
    String floor = 'floor',
    String wall = 'wall',
    String ceiling = 'ceiling',
    List<RoomDoor> doors = const <RoomDoor>[],
  }) {
    final x0 = from[0].toDouble(), z0 = from[2].toDouble();
    final x1 = to[0].toDouble(), z1 = to[2].toDouble();
    final alongX = (x0 - x1).abs() > 1e-6;
    if (alongX && (z0 - z1).abs() > 1e-6) {
      throw LevelFormatException(
        'a corridor from $from to $to is not straight',
      );
    }
    final (centre, size) = alongX
        ? (<num>[(x0 + x1) / 2.0, 0.0, z0], <num>[(x1 - x0).abs(), 0.0, width])
        : (<num>[x0, 0.0, (z0 + z1) / 2.0], <num>[width, 0.0, (z1 - z0).abs()]);
    room(
      centre,
      size,
      height: height,
      base: base,
      floor: floor,
      wall: wall,
      ceiling: ceiling,
      doors: doors,
      probe: false,
    );
  }

  /// A flight of steps from [from] up (or down) to [to], standing on [bottom].
  ///
  /// Steps rather than a ramp because the navigation grid reads a ramp as the
  /// box it is cut from, so a walker would refuse a slope a body could climb.
  /// A step whose top would be at or under [bottom] is not built.
  ///
  /// **A step shallower than a navigation cell is a step nothing walks up**:
  /// the grid keeps one surface per column, so a cell straddling two steps has
  /// no floor at all. Give a flight as many steps as it has metres of run.
  void stair(
    List<num> from,
    List<num> to, {
    double width = 3.0,
    int steps = 8,
    double bottom = 0.0,
    String material = 'stone',
  }) {
    final x0 = from[0].toDouble(), y0 = from[1].toDouble();
    final z0 = from[2].toDouble();
    final x1 = to[0].toDouble(), y1 = to[1].toDouble(), z1 = to[2].toDouble();
    for (var i = 0; i < steps; i++) {
      final t = (i + 1) / steps;
      final y = y0 + (y1 - y0) * t;
      final x = x0 + (x1 - x0) * t;
      final z = z0 + (z1 - z0) * t;
      if (y - bottom < 0.05) continue;
      final alongX = (x1 - x0).abs() > (z1 - z0).abs();
      final run = (alongX ? (x1 - x0).abs() : (z1 - z0).abs()) / steps;
      box(
        <num>[x, (bottom + y) / 2.0, z],
        <num>[alongX ? run : width, y - bottom, alongX ? width : run],
        material,
      );
    }
  }

  /// One wall, in up to four pieces per hole, with [holes] cut out of it.
  ///
  /// A doorway is a hole from the floor up; a window starts above the floor.
  /// The pieces are: below each hole, above it, and the runs of solid wall
  /// between them.
  void _wallWithHoles(
    double fixed,
    _Axis axis,
    (double, double) span,
    double base,
    double height,
    List<_Hole> holes,
    String material,
  ) {
    // Stable, so two holes starting at the same place keep the order they
    // were asked for in — a document diffed against its last run should not
    // reorder its walls because a sort felt like it.
    final ordered =
        <(int, _Hole)>[for (var i = 0; i < holes.length; i++) (i, holes[i])]
          ..sort(((int, _Hole) a, (int, _Hole) b) {
            final byStart = (a.$2.centre - a.$2.width / 2.0).compareTo(
              b.$2.centre - b.$2.width / 2.0,
            );
            return byStart != 0 ? byStart : a.$1.compareTo(b.$1);
          });
    var cursor = span.$1;
    for (final (_, hole) in ordered) {
      final left = hole.centre - hole.width / 2.0;
      final right = hole.centre + hole.width / 2.0;
      if (left > cursor) {
        _piece(fixed, axis, cursor, left, base, base + height, material);
      }
      if (hole.sill > base) {
        _piece(fixed, axis, left, right, base, hole.sill, material);
      }
      if (hole.top < base + height) {
        _piece(fixed, axis, left, right, hole.top, base + height, material);
      }
      cursor = right;
    }
    if (cursor < span.$2) {
      _piece(fixed, axis, cursor, span.$2, base, base + height, material);
    }
  }

  /// One run of wall, and the reason every one of them says `doubleSided`.
  ///
  /// These walls are one brush thick with rooms on both sides, so the face a
  /// light reaches and the face it does not are a metre apart. Recorded from
  /// the far side only, light leaks along the seam where a wall meets the
  /// floor of the room in front of it.
  void _piece(
    double fixed,
    _Axis axis,
    double low,
    double high,
    double bottom,
    double top,
    String material,
  ) {
    if (high - low < 1e-6 || top - bottom < 1e-6) return;
    final along = (low + high) / 2.0;
    final middle = (bottom + top) / 2.0;
    switch (axis) {
      case _Axis.x:
        box(
          <num>[along, middle, fixed],
          <num>[high - low, top - bottom, thickness],
          material,
          shadows: 'doubleSided',
        );
      case _Axis.z:
        box(
          <num>[fixed, middle, along],
          <num>[thickness, top - bottom, high - low],
          material,
          shadows: 'doubleSided',
        );
    }
  }

  static List<(double, double)> _probeGrid(
    double cx,
    double cz,
    double w,
    double d,
  ) {
    List<double> positions(double centre, double extent) {
      final count = math.max(1, (extent / (probeReach * 2.0)).ceil());
      final step = extent / count;
      final start = centre - extent / 2.0 + step / 2.0;
      return <double>[for (var i = 0; i < count; i++) start + i * step];
    }

    return <(double, double)>[
      for (final x in positions(cx, w))
        for (final z in positions(cz, d)) (x, z),
    ];
  }
}

/// An opening in one of a room's walls.
///
/// [offset] is along that wall from its middle. [sill] is where the opening
/// starts, for a room whose floor is lower than its neighbour's; null is the
/// room's own floor.
final class RoomDoor {
  const RoomDoor(this.side, this.offset, this.width, this.height, {this.sill});

  /// `north`, `south`, `east` or `west`.
  final String side;
  final double offset;
  final double width;
  final double height;
  final double? sill;
}

enum _Axis { x, z }

typedef _Hole = ({double centre, double width, double sill, double top});

/// The keys a brush row writes to ask for the shadow [mode], and nothing it
/// need not.
///
/// `on` says nothing at all: it is the default, and a document that grew a
/// line per brush saying so is one nobody can read a diff of. `off` keeps
/// writing the older boolean, so every level already on disk stays the file it
/// is. The other two have no boolean that can say them.
Map<String, Object?> shadowKeys(String mode) => switch (mode) {
  'on' => const <String, Object?>{},
  'off' => const <String, Object?>{'castsShadow': false},
  'doubleSided' || 'shadowsOnly' => <String, Object?>{'shadowCasting': mode},
  _ => throw LevelFormatException(
    'a brush asks for shadowCasting "$mode", which is not one of on, off, '
    'doubleSided, shadowsOnly',
  ),
};

/// A vector at millimetre precision.
///
/// Three places rather than every digit a double has, because the difference
/// between `2.0999999999999996` and `2.1` is invisible in a game and enormous
/// in a diff: a generator run again on another machine should write the same
/// file or a deliberately different one, never a noisier one.
List<double> roundedVector(Iterable<num> values) => <double>[
  for (final value in values) roundDecimal(value.toDouble(), 3),
];

/// [value] rounded to [digits] decimal places, ties to even, on its exact
/// binary value.
///
/// **Exact, not `(value * 1000).round() / 1000`.** The multiply rounds once
/// before the rounding it was asked for, so a number just under a half-way
/// point can land on it and go up; and the level documents this repository
/// ships were written by a rounding that decides on the double's exact value
/// and breaks true ties towards the even digit. A generator that should write
/// those files byte for byte has to decide exactly where they did.
///
/// Integers and the other exact bits of arithmetic go through [BigInt], so the
/// answer is the same on the web, where an `int` is a double and a shift past
/// 32 bits is not what it is on the VM.
double roundDecimal(double value, int digits) {
  if (value.isNaN || value.isInfinite || value == 0.0) return value;
  final bytes = ByteData(8)..setFloat64(0, value);
  final high = bytes.getUint32(0);
  final low = bytes.getUint32(4);
  final biased = (high >> 20) & 0x7FF;
  final fraction = (BigInt.from(high & 0xFFFFF) << 32) | BigInt.from(low);
  final mantissa = biased == 0 ? fraction : fraction | (BigInt.one << 52);
  final exponent = (biased == 0 ? 1 : biased) - 1075;
  // An exponent at or above zero is an integer already, and every integer is
  // its own rounding at any number of places.
  if (exponent >= 0) return value;

  final scaled = mantissa * BigInt.from(10).pow(digits);
  final denominator = BigInt.one << -exponent;
  final quotient = scaled ~/ denominator;
  final twice = (scaled - quotient * denominator) * BigInt.two;
  final rounded =
      twice > denominator || (twice == denominator && quotient.isOdd)
      ? quotient + BigInt.one
      : quotient;
  return double.parse('${value < 0 ? '-' : ''}${rounded}e-$digits');
}
