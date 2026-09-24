/// The pieces the dungeon's levels are built out of.
///
/// The platformer has `platform_kit.dart`, and this is its opposite number
/// rather than a copy of it. What differs is the vocabulary, and the vocabulary
/// differs because the shape of the game does: a platformer level is a
/// **route** — a chain of places to land, with air between them — and a crypt
/// is a **plan**, rooms with walls between them and doors in the walls.
///
/// **Walls are built, not drawn.** A room is six brushes with holes cut in them
/// by the doorways it is given, because a wall with a hole in it is four
/// brushes and getting those four right by hand is where hand-authored levels
/// go wrong. The arithmetic is `LevelSketch`'s, the same the `room` recipe
/// draws with.
///
/// Numbers that go into the document as they are — an amount, an intensity, a
/// yaw — are `num` rather than `double` on purpose: `25` and `25.0` are
/// different bytes in the file, and the file is what is diffed.
library;

import 'dart:math' as math;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

typedef Row = Map<String, Object?>;

/// One level's worth of rooms, lights and things in them.
final class CryptKit {
  CryptKit();

  final LevelSketch _sketch = LevelSketch();

  List<Row> get brushes => _sketch.brushes;
  List<Row> get entities => _sketch.entities;
  List<Row> get lights => _sketch.lights;

  /// Where the ceiling goes when a room does not say.
  static const double height = LevelSketch.defaultHeight;

  // MARK: - Architecture

  /// One brush, as it is: a pier, a dais, a slab of water.
  ///
  /// [shadows] is one of the four shadow words, for a block that wants a finer
  /// answer than [casts] can give.
  Row block(
    List<num> at,
    List<num> size,
    String material, {
    bool casts = true,
    bool solid = true,
    String? shadows,
  }) => _sketch.box(
    at,
    size,
    material,
    shadows: shadows ?? (casts ? 'on' : 'off'),
    solid: solid,
  );

  /// A room: floor, ceiling, and four walls with [doors] cut through them.
  ///
  /// [centre] is the middle of the floor and [size] is the inside, so two
  /// rooms whose centres are `size` apart share a wall rather than
  /// overlapping. **North is −Z**, the direction the camera faces at yaw zero.
  void room(
    List<num> centre,
    List<num> size, {
    double height = CryptKit.height,
    double base = 0.0,
    List<RoomDoor> doors = const <RoomDoor>[],
    bool probe = true,
  }) => _sketch.room(
    centre,
    size,
    height: height,
    base: base,
    doors: doors,
    probe: probe,
  );

  /// A passage between two points along one axis. See `LevelSketch.corridor`.
  void corridor(
    List<num> from,
    List<num> to, {
    double width = 3.0,
    double height = 3.0,
    List<RoomDoor> doors = const <RoomDoor>[],
  }) => _sketch.corridor(from, to, width: width, height: height, doors: doors);

  void pillar(List<num> at, {List<num> size = const <num>[1.2, height, 1.2]}) =>
      _sketch.box(at, size, 'stone');

  /// A flight, as steps rather than a ramp. See `LevelSketch.stair`.
  void stair(
    List<num> from,
    List<num> to, {
    int steps = 8,
    double bottom = 0.0,
  }) => _sketch.stair(from, to, steps: steps, bottom: bottom);

  // MARK: - Light

  /// A torch on a wall, and the light it drives.
  ///
  /// One call rather than two, because the light and the fixture are the same
  /// thing said twice: the fixture drives the light by name, and generating
  /// both here means the name cannot be mistyped in one of them.
  void torch(
    List<num> at, {
    required String name,
    num yaw = 0.0,
    List<num> colour = const <num>[1.0, 0.68, 0.34],
    num intensity = 6.5,
    num range = 13.0,
    bool shadow = true,
  }) {
    lights.add(<String, Object?>{
      'type': 'point',
      'at': roundedVector(at),
      'color': colour,
      'intensity': intensity,
      'range': range,
      'castsShadow': shadow,
      'name': name,
    });
    entities.add(<String, Object?>{
      'type': 'torch',
      'at': roundedVector(_offset(at, yaw, 0.35)),
      'yaw': roundNumber(yaw, 4),
      'light': name,
    });
  }

  void lamp(
    List<num> at, {
    required String name,
    List<num> colour = const <num>[1.0, 0.78, 0.42],
    num intensity = 5.0,
    num range = 11.0,
  }) {
    lights.add(<String, Object?>{
      'type': 'point',
      'at': roundedVector(at),
      'color': colour,
      'intensity': intensity,
      'range': range,
      'castsShadow': true,
      'name': name,
    });
    entities.add(<String, Object?>{
      'type': 'lamp',
      'at': roundedVector(at),
      'light': name,
      'color': colour,
    });
  }

  /// A step along [yaw] from [at]. Yaw zero faces −Z.
  static List<num> _offset(List<num> at, num yaw, double distance) => <num>[
    at[0] - math.sin(yaw) * distance,
    at[1],
    at[2] - math.cos(yaw) * distance,
  ];

  // MARK: - What is in the rooms

  void spawn(List<num> at, {num yaw = 0.0}) => entities.add(<String, Object?>{
    'type': 'player_spawn',
    'at': roundedVector(at),
    'yaw': roundNumber(yaw, 4),
  });

  void monster(String kind, List<num> at) => entities.add(<String, Object?>{
    'type': 'monster',
    'at': roundedVector(at),
    'kind': kind,
  });

  void pickup(String gives, List<num> at, {num? amount, num? ammo}) =>
      entities.add(<String, Object?>{
        'type': 'pickup',
        'at': roundedVector(at),
        'gives': gives,
        'amount': ?amount,
        'ammo': ?ammo,
      });

  void door(
    String name,
    List<num> at, {
    String? key,
    List<num> size = const <num>[4.0, 5.0, 1.0],
    List<num> travel = const <num>[0.0, 4.4, 0.0],
    num speed = 2.2,
    num wait = 4.0,
    String material = 'iron',
  }) => entities.add(<String, Object?>{
    'type': 'door',
    'at': roundedVector(at),
    'name': name,
    'size': roundedVector(size),
    'travel': roundedVector(travel),
    'speed': speed,
    'wait': wait,
    'material': material,
    if (key != null && key.isNotEmpty) 'key': key,
  });

  void key(String colour, List<num> at, {String? name}) =>
      entities.add(<String, Object?>{
        'type': 'key',
        'at': roundedVector(at),
        'color': colour,
        'name': name ?? '${colour}_key',
        'model': 'assets_src/models/key.glb',
        'material': 'keymetal',
        'size': <num>[0.7, 0.7, 0.7],
        'tint': <num>[0.95, 0.6, 0.2],
      });

  void lift(
    String name,
    List<num> at, {
    List<num> size = const <num>[2.6, 0.5, 3.0],
    List<num> travel = const <num>[0.0, 3.0, 0.0],
    num speed = 1.5,
    num wait = 5.0,
    String material = 'iron',
  }) => entities.add(<String, Object?>{
    'type': 'lift',
    'at': roundedVector(at),
    'size': roundedVector(size),
    'travel': roundedVector(travel),
    'speed': speed,
    'wait': wait,
    'name': name,
    'material': material,
  });

  /// A slab that goes back and forth on its own, with nothing to switch it.
  void platform(
    String name,
    List<num> at, {
    List<num> size = const <num>[3.0, 0.4, 3.0],
    List<num> travel = const <num>[0.0, 0.0, -4.0],
    num speed = 1.1,
    num wait = 2.0,
    String material = 'stone',
  }) => entities.add(<String, Object?>{
    'type': 'platform',
    'at': roundedVector(at),
    'size': roundedVector(size),
    'travel': roundedVector(travel),
    'speed': speed,
    'wait': wait,
    'name': name,
    'material': material,
  });

  void button(
    String target,
    List<num> at, {
    List<num> size = const <num>[0.25, 0.7, 0.7],
  }) => entities.add(<String, Object?>{
    'type': 'button',
    'at': roundedVector(at),
    'size': roundedVector(size),
    'target': target,
  });

  void trigger(
    String target,
    List<num> at, {
    List<num> size = const <num>[4.0, 3.0, 2.0],
    bool once = false,
  }) => entities.add(<String, Object?>{
    'type': 'trigger',
    'at': roundedVector(at),
    'size': roundedVector(size),
    'target': target,
    'once': once,
  });

  void note(List<num> at, String text, {num yaw = 0.0}) =>
      entities.add(<String, Object?>{
        'type': 'note',
        'at': roundedVector(at),
        'yaw': roundNumber(yaw, 4),
        'text': text,
      });

  /// A live widget drawn on a surface in the world; [widget] is the name a
  /// registry in the application resolves.
  void widgetSurface(
    String name,
    List<num> at, {
    required String widget,
    num yaw = 0.0,
    num width = 1.2,
    num height = 0.9,
  }) => entities.add(<String, Object?>{
    'type': 'widget_surface',
    'name': name,
    'at': roundedVector(at),
    'yaw': roundNumber(yaw, 4),
    'widget': widget,
    'width': width,
    'height': height,
  });

  /// A place that counts the first time somebody walks into it. Nothing is
  /// drawn for it: what makes it a secret is where it was put.
  void secret(List<num> at, {List<num> size = const <num>[2.0, 2.5, 2.0]}) =>
      entities.add(<String, Object?>{
        'type': 'secret',
        'at': roundedVector(at),
        'size': roundedVector(size),
      });

  /// How tall the arch a way out is drawn as stands, in metres.
  static const double exitHeight = 2.6;

  /// A way out, standing on whatever the player stands on at [at].
  ///
  /// **[at] is where the feet go.** Written as a centre it was authored by eye
  /// and the arch, whose model is centred, came out hanging a metre off the
  /// floor in two crypts.
  void exitAt(String name, List<num> at) => entities.add(<String, Object?>{
    'type': 'exit',
    'name': name,
    'at': roundedVector(<num>[at[0], at[1] + exitHeight / 2.0, at[2]]),
  });

  // MARK: - Writing it down

  static Row _textured(
    String name, {
    required List<num> base,
    required num roughness,
    required num texels,
    String? image,
  }) {
    final file = image ?? name;
    return <String, Object?>{
      'baseColor': base,
      'roughness': roughness,
      'texelsPerMetre': texels,
      'albedo': 'assets/textures/${file}_albedo.jpg',
      'normal': 'assets/textures/${file}_normal.png',
      'orm': 'assets/textures/${file}_orm.png',
    };
  }

  /// The table every crypt level carries. The numbers are the ones the
  /// hand-authored crypt shipped with: chosen against the textures by eye.
  static final Map<String, Row> materials = <String, Row>{
    'floor': _textured(
      'floor',
      base: <num>[0.62, 0.6, 0.56, 1.0],
      roughness: 0.9,
      texels: 0.5,
    ),
    'wall': _textured(
      'wall',
      base: <num>[0.7, 0.66, 0.6, 1.0],
      roughness: 0.85,
      texels: 0.4,
    ),
    'ceiling': _textured(
      'ceiling',
      base: <num>[0.34, 0.32, 0.3, 1.0],
      roughness: 0.95,
      texels: 0.35,
    ),
    'stone': _textured(
      'stone',
      base: <num>[0.68, 0.65, 0.6, 1.0],
      roughness: 0.8,
      texels: 0.7,
    ),
    'iron': _textured(
      'iron',
      base: <num>[0.72, 0.7, 0.68, 1.0],
      roughness: 0.6,
      texels: 1.2,
      image: 'metal',
    ),
    // No maps: a key is a small bright thing and a metal texture on it at
    // this size is noise.
    'keymetal': <String, Object?>{
      'baseColor': <num>[0.92, 0.72, 0.26, 1.0],
      'roughness': 0.35,
      'metallic': 0.9,
    },
  };

  /// Standing water: dark, near-black green, glossy, and no maps. Only the
  /// cistern has any, so it is not in [materials].
  static const Row water = <String, Object?>{
    'baseColor': <num>[0.08, 0.16, 0.15, 1.0],
    'roughness': 0.12,
    'metallic': 0.0,
  };

  /// Things a player is meant to reach. One inside a wall is a key nobody can
  /// take, and it looks perfectly fine in the document — which is why this is
  /// checked rather than reviewed.
  static const List<String> reachable = <String>['pickup', 'key'];

  List<String> _buried() => <String>[
    for (final row in entities)
      if (reachable.contains(row['type']))
        if (_wallOf(row) case final brush?) _inside(row, brush),
  ];

  static String _inside(Row row, Row brush) =>
      '  ${row['type']} at ${row['at']} is inside a ${brush['material']} '
      'brush at ${brush['at']}';

  Row? _wallOf(Row row) {
    final at = (row['at']! as List<Object?>).cast<num>();
    for (final brush in brushes) {
      // Water is not a wall: a thing standing in it stands in the room.
      if (brush['solid'] == false) continue;
      final c = (brush['at']! as List<Object?>).cast<num>();
      final s = (brush['size']! as List<Object?>).cast<num>();
      if ((at[0] - c[0]).abs() < s[0] / 2.0 &&
          (at[1] - c[1]).abs() < s[1] / 2.0 &&
          (at[2] - c[2]).abs() < s[2] / 2.0) {
        return brush;
      }
    }
    return null;
  }

  /// The document, as text, after refusing one a player cannot finish.
  ///
  /// [extra] are this level's own materials, added to the shared table.
  String write({
    required String file,
    required String name,
    required String tool,
    List<num> fog = const <num>[0.034, 0.034, 0.034],
    num density = 0.035,
    String? next,
    Map<String, Row> extra = const <String, Row>{},
  }) {
    final walledIn = _buried();
    if (walledIn.isNotEmpty) {
      throw GeneratorRefused(
        '${walledIn.length} things a player is meant to reach are inside '
        'solid brushes:\n${walledIn.join('\n')}',
      );
    }
    if (!entities.any((Row e) => e['type'] == 'player_spawn')) {
      throw GeneratorRefused('$file has nowhere for the player to start');
    }
    final document = <String, Object?>{
      'version': 1,
      'name': name,
      'generatedBy': tool,
      'fogColor': fog,
      'fogDensity': density,
      'materials': <String, Object?>{...materials, ...extra},
      'brushes': brushes,
      'lights': lights,
      'entities': entities,
      'next': ?next,
    };
    return '${DocumentText.compact(document)}\n';
  }
}
