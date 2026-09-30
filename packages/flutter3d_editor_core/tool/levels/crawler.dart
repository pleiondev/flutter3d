/// The crawl's three levels: the gatehouse, the kennels and the ossuary.
///
/// **Edit these, not the JSON.** Each function is one level's arrangement;
/// `dart run tool/regenerate_levels.dart` writes the documents, identical
/// unless something here changed.
///
/// A crawl is seen from above, so its rooms have **no ceilings** and their
/// walls stop at the waist of a two-storey view: tall enough to read as walls
/// and to stop a shot, low enough that the camera sees over them into the
/// next room. One sun lights all of it, casting the walls' shadows across the
/// floors, because a hundred monsters is a scene where eight point lights
/// would go on the rooms and none would be left for anything else.
///
/// Rooms sit on a grid of [_pitch] metres and **every edge of the grid is one
/// wall**, built once, whichever of the two rooms it divides asked for it.
/// `LevelSketch.room` gives each room its own four walls and a floor that
/// reaches under them, which is right for a crypt whose rooms stand apart and
/// wrong here: two neighbours would each build the wall between them, and
/// the validator counts every such pair as faces that will flicker.
library;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

typedef Row = Map<String, Object?>;

const String _levels = 'apps/flutter3d_demo_crawler/assets/levels';
const String _tool = 'packages/flutter3d_editor_core/tool/levels/crawler.dart';

/// Inside of a room, in metres.
const double _room = 12.0;

/// Room centre to room centre: the inside plus one wall.
const double _pitch = _room + LevelSketch.thickness;

const double _wallHeight = 2.2;

/// Doorways are this wide.
const double _gap = 3.0;

/// The colour of a key and of the doors it opens. Any key opens any door in a
/// crawl; the colour is the format's way of saying a locked door has a key
/// somewhere in the level.
const String _gold = 'gold';

final class _Crawl {
  final LevelSketch sketch = LevelSketch();

  List<Row> get entities => sketch.entities;

  /// The rooms, as grid cells.
  final Set<(int, int)> _cells = <(int, int)>{};

  /// The edges with a doorway in them. An edge is named by the cell south or
  /// east of it and the letter of its axis: `(x, z, 'n')` is the wall along
  /// the north of cell (x, z), `(x, z, 'w')` the one along its west.
  final Set<(int, int, String)> _openings = <(int, int, String)>{};

  /// The centre of the floor of the room at grid cell ([x], [z]).
  static List<num> at(int x, int z, [num dx = 0.0, num dz = 0.0]) => <num>[
    x * _pitch + dx,
    0.0,
    z * _pitch + dz,
  ];

  /// A room at grid cell ([x], [z]) with doorways on the named [sides].
  void room(int x, int z, List<String> sides) {
    _cells.add((x, z));
    for (final side in sides) {
      _openings.add(switch (side) {
        'north' => (x, z, 'n'),
        'south' => (x, z + 1, 'n'),
        'west' => (x, z, 'w'),
        'east' => (x + 1, z, 'w'),
        _ => throw GeneratorRefused('a room has no "$side" side'),
      });
    }
  }

  /// The floors and walls of every room, each edge once.
  ///
  /// A wall along X runs the pitch, meeting the next one along exactly, and
  /// reaches half a wall further at an end with no neighbour, so it owns the
  /// corners; one along Z stops half a wall short at each end. Where two meet
  /// nothing is built twice and nothing is left open.
  void _build() {
    const t = LevelSketch.thickness;
    const half = _pitch / 2.0;
    for (final (x, z) in _cells) {
      sketch.box(
        <num>[x * _pitch, -t / 2.0, z * _pitch],
        <num>[_pitch, t, _pitch],
        'floor',
      );
    }
    final edges = <(int, int, String)>{
      for (final (x, z) in _cells) ...<(int, int, String)>[
        (x, z, 'n'),
        (x, z, 'w'),
        if (!_cells.contains((x, z + 1))) (x, z + 1, 'n'),
        if (!_cells.contains((x + 1, z))) (x + 1, z, 'w'),
      ],
    };
    for (final edge in edges) {
      final (x, z, axis) = edge;
      final alongX = axis == 'n';
      // The wall's line across, and its middle and ends along.
      final across = alongX ? z * _pitch - half : x * _pitch - half;
      final middle = alongX ? x * _pitch : z * _pitch;
      final double start;
      final double end;
      if (alongX) {
        start =
            middle - half - (edges.contains((x - 1, z, 'n')) ? 0.0 : t / 2.0);
        end = middle + half + (edges.contains((x + 1, z, 'n')) ? 0.0 : t / 2.0);
      } else {
        start = middle - half + t / 2.0;
        end = middle + half - t / 2.0;
      }
      final spans = _openings.contains(edge)
          ? <(double, double)>[
              (start, middle - _gap / 2.0),
              (middle + _gap / 2.0, end),
            ]
          : <(double, double)>[(start, end)];
      for (final (from, to) in spans) {
        final centre = (from + to) / 2.0;
        final span = to - from;
        sketch.box(
          <num>[
            alongX ? centre : across,
            _wallHeight / 2.0,
            alongX ? across : centre,
          ],
          <num>[alongX ? span : t, _wallHeight, alongX ? t : span],
          'wall',
        );
      }
    }
  }

  /// Where every hero starts, side by side in the room at ([x], [z]).
  void spawns(int x, int z) {
    for (var slot = 0; slot < 4; slot++) {
      entities.add(<String, Object?>{
        'type': 'player_spawn',
        'at': roundedVector(at(x, z, -2.25 + 1.5 * slot, 3.0)),
        'slot': slot,
      });
    }
  }

  void thing(
    String type,
    List<num> at, [
    Row extra = const <String, Object?>{},
  ]) => entities.add(<String, Object?>{
    'type': type,
    'at': roundedVector(<num>[at[0], 0.4, at[2]]),
    ...extra,
  });

  void generator(String kind, List<num> at, {int cap = 6, num period = 2.5}) =>
      entities.add(<String, Object?>{
        'type': 'generator',
        'at': roundedVector(at),
        'kind': kind,
        'cap': cap,
        'period': period,
      });

  void monster(String kind, List<num> at) => entities.add(<String, Object?>{
    'type': 'monster',
    'at': roundedVector(at),
    'kind': kind,
  });

  /// A locked door in the doorway between room ([x], [z]) and the one to
  /// its east (along X) or south (along Z). It sinks into the floor when
  /// opened, which from above reads as a door that is gone.
  void lockedDoor(String name, int x, int z, {required bool east}) {
    final centre = at(
      x,
      z,
      east ? _pitch / 2.0 : 0.0,
      east ? 0.0 : _pitch / 2.0,
    );
    entities.add(<String, Object?>{
      'type': 'door',
      'name': name,
      'at': roundedVector(<num>[centre[0], _wallHeight / 2.0, centre[2]]),
      'size': roundedVector(
        east
            ? <num>[LevelSketch.thickness, _wallHeight, _gap]
            : <num>[_gap, _wallHeight, LevelSketch.thickness],
      ),
      'travel': <num>[0.0, -(_wallHeight + 0.1), 0.0],
      'speed': 3.0,
      'wait': 0,
      'key': _gold,
      'material': 'door',
    });
  }

  void key(List<num> at) => thing('key', at, <String, Object?>{'color': _gold});

  void exit(List<num> at) => entities.add(<String, Object?>{
    'type': 'exit',
    'at': roundedVector(<num>[at[0], 1.0, at[2]]),
    'size': <num>[2.0, 2.0, 2.0],
  });

  String write({required String name, String? next}) {
    if (!entities.any((Row e) => e['type'] == 'exit')) {
      throw GeneratorRefused('$name has no way out');
    }
    _build();
    final document = <String, Object?>{
      'version': 1,
      'name': name,
      'generatedBy': _tool,
      'fogColor': <num>[0.05, 0.045, 0.06],
      'fogDensity': 0.004,
      'materials': _materials,
      'brushes': sketch.brushes,
      'lights': <Row>[
        <String, Object?>{
          'type': 'directional',
          'direction': <num>[-0.35, -1.0, -0.25],
          'color': <num>[1.0, 0.9, 0.78],
          'intensity': 2.6,
        },
      ],
      'entities': entities,
      'next': ?next,
    };
    return '${DocumentText.compact(document)}\n';
  }

  static const Map<String, Row> _materials = <String, Row>{
    'floor': <String, Object?>{
      'baseColor': <num>[0.34, 0.31, 0.29, 1.0],
      'roughness': 0.92,
    },
    'wall': <String, Object?>{
      'baseColor': <num>[0.58, 0.54, 0.5, 1.0],
      'roughness': 0.85,
    },
    'door': <String, Object?>{
      'baseColor': <num>[0.62, 0.42, 0.18, 1.0],
      'roughness': 0.6,
      'metallic': 0.3,
    },
  };
}

/// The first level: four rooms round a square. Food by the start, a grunt
/// generator across the way, the key beside it, and the way out behind the
/// one locked door.
///
/// ```
///   [ start ] — [ grunts ]
///       |
///   [ key   ] =locked= [ exit ]
/// ```
Map<String, String> gatehouse(GeneratorSource _) {
  final k = _Crawl()
    ..room(0, 0, <String>['east', 'south'])
    ..room(1, 0, <String>['west'])
    ..room(0, 1, <String>['north', 'east'])
    ..room(1, 1, <String>['west'])
    ..spawns(0, 0)
    ..thing('food', _Crawl.at(0, 0, -4.0, -4.0))
    ..thing('treasure', _Crawl.at(0, 0, 4.0, -4.0), <String, Object?>{
      'worth': 100,
    })
    ..generator('grunt', _Crawl.at(1, 0, 3.0, -3.0), cap: 5)
    ..monster('grunt', _Crawl.at(1, 0, -3.0, 2.0))
    ..key(_Crawl.at(0, 1, -4.0, 3.0))
    ..thing('food', _Crawl.at(0, 1, 4.0, 4.0))
    ..lockedDoor('gatehouse_door', 0, 1, east: true)
    ..thing('potion', _Crawl.at(1, 1, -4.0, 4.0))
    ..exit(_Crawl.at(1, 1, 3.0, 3.0));
  return <String, String>{
    '$_levels/gatehouse.json': k.write(name: 'The gatehouse', next: 'kennels'),
  };
}

/// The second level: a row of three kennels and a yard below them. Two
/// generators, one of each kind; a thief loose in the yard, beside the
/// potion it will want.
///
/// ```
///   [ start ] — [ ghosts ] — [ grunts ]
///                   |            ‖ locked
///               [ yard  ]     [ exit ]
/// ```
Map<String, String> kennels(GeneratorSource _) {
  final k = _Crawl()
    ..room(0, 0, <String>['east'])
    ..room(1, 0, <String>['west', 'east', 'south'])
    ..room(2, 0, <String>['west', 'south'])
    ..room(1, 1, <String>['north'])
    ..room(2, 1, <String>['north'])
    ..spawns(0, 0)
    ..thing('food', _Crawl.at(0, 0, 4.0, -4.0))
    ..thing('potion', _Crawl.at(0, 0, -4.0, -4.0))
    ..generator('ghost', _Crawl.at(1, 0, 0.0, -3.5), cap: 4, period: 3.0)
    ..generator('grunt', _Crawl.at(2, 0, 3.0, -3.0), cap: 6)
    ..generator('grunt', _Crawl.at(2, 0, -3.0, -3.0), cap: 4)
    ..key(_Crawl.at(2, 0, 4.0, 4.0))
    ..thing('treasure', _Crawl.at(2, 0, -4.5, 4.5), <String, Object?>{
      'worth': 250,
    })
    ..monster('thief', _Crawl.at(1, 1, -3.0, 3.0))
    ..thing('food', _Crawl.at(1, 1, 0.0, 0.0))
    ..thing('potion', _Crawl.at(1, 1, 4.0, 4.0))
    ..lockedDoor('kennel_door', 2, 0, east: false)
    ..exit(_Crawl.at(2, 1, 3.0, 3.0));
  return <String, String>{
    '$_levels/kennels.json': k.write(name: 'The kennels', next: 'ossuary'),
  };
}

/// The third level: a ring of six rooms with the way out in the middle of
/// the far side, and Death walking it. A potion strong enough is the only
/// answer to it, so there are three, and the wizard is the one to carry them.
///
/// ```
///   [ start ] — [ bones ] — [ ghosts ]
///       |
///   [ grunts ] — [ Death ] =locked= [ exit ]
/// ```
Map<String, String> ossuary(GeneratorSource _) {
  final k = _Crawl()
    ..room(0, 0, <String>['east', 'south'])
    ..room(1, 0, <String>['west', 'east'])
    ..room(2, 0, <String>['west'])
    ..room(0, 1, <String>['north', 'east'])
    ..room(1, 1, <String>['west', 'east'])
    ..room(2, 1, <String>['west'])
    ..spawns(0, 0)
    ..thing('food', _Crawl.at(0, 0, 4.0, -4.0))
    ..thing('potion', _Crawl.at(0, 0, -4.0, -4.0))
    ..generator('grunt', _Crawl.at(1, 0, 0.0, -4.0), cap: 6, period: 2.0)
    ..thing('treasure', _Crawl.at(1, 0, 0.0, 4.0), <String, Object?>{
      'worth': 250,
    })
    ..generator('ghost', _Crawl.at(2, 0, 3.5, -3.5), cap: 5, period: 2.5)
    ..thing('potion', _Crawl.at(2, 0, -4.0, 4.0))
    ..generator('grunt', _Crawl.at(0, 1, -3.5, 3.5), cap: 6, period: 2.0)
    ..key(_Crawl.at(0, 1, 4.0, 4.0))
    ..thing('food', _Crawl.at(0, 1, -4.0, -4.0))
    ..monster('death', _Crawl.at(1, 1, 0.0, 0.0))
    ..thing('potion', _Crawl.at(1, 1, -4.5, 4.5))
    ..thing('food', _Crawl.at(1, 1, 4.5, -4.5))
    ..lockedDoor('ossuary_door', 1, 1, east: true)
    ..exit(_Crawl.at(2, 1, 0.0, 0.0));
  return <String, String>{
    '$_levels/ossuary.json': k.write(name: 'The ossuary'),
  };
}

/// The three, as the registry runs them.
Map<String, String> levels(GeneratorSource source) => <String, String>{
  ...gatehouse(source),
  ...kennels(source),
  ...ossuary(source),
};
