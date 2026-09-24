/// The pieces the platformer's levels are built out of.
///
/// What lives here is the vocabulary: a brush, a coin, a crate, a mover, a key
/// and its gate, a route guard and the writer. What lives in each level's
/// function in `platformer.dart` is the *arrangement*, which is the part worth
/// reading.
///
/// **Two lists of entities, and the order they are written in is the
/// document's.** A coin or a crate given a name is on the route, and goes with
/// the rest of the route's entities; one without a name is filling, numbered in
/// the order it was placed and written after everything else.
///
/// Numbers that go into the document as they are — a speed, a mass, an order —
/// are `num` rather than `double` on purpose: `15` and `15.0` are different
/// bytes in the file, and the file is what is diffed.
library;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

typedef Row = Map<String, Object?>;

/// A rectangle on the ground, `(x0, x1, z0, z1)`, that filling may not stand
/// on.
typedef Clear = (num, num, num, num);

/// One level's worth of route, filling and things in them.
final class PlatformKit {
  PlatformKit({this.clear = const <Clear>[]});

  /// The ground the filling may not stand on: the route's footprint.
  final List<Clear> clear;

  final List<Row> brushes = <Row>[];
  final List<Row> entities = <Row>[];
  final List<Row> _filling = <Row>[];
  int _coins = 0;
  int _crates = 0;

  static const String _coinModel = 'assets_src/models/coin.glb';

  /// Which way a ramp climbs, in the words the level format uses.
  static const List<String> ramps = <String>['+x', '-x', '+z', '-z'];

  /// A brush on the route. [casts] false writes the boolean; true says
  /// nothing, because it is the default.
  void route(
    List<num> at,
    List<num> size,
    String material, {
    String? surface,
    bool casts = true,
    String? ramp,
  }) {
    if (ramp != null) _checkRamp(ramp);
    brushes.add(<String, Object?>{
      'at': roundedVector(at),
      'size': roundedVector(size),
      'material': material,
      if (surface != null && surface.isNotEmpty) 'surface': surface,
      if (!casts) 'castsShadow': false,
      if (ramp != null && ramp.isNotEmpty) 'ramp': ramp,
    });
  }

  /// A typo here is a block where a slope was meant, and the reader would
  /// refuse the document — but at load, in front of a player.
  static void _checkRamp(String ramp) {
    if (!ramps.contains(ramp)) {
      throw GeneratorRefused('ramp "$ramp" is not one of ${ramps.join(', ')}');
    }
  }

  /// A brush with a corner cut off, climbing towards [uphill].
  ///
  /// There is no angle: the cut runs corner to corner, so the steepness is
  /// the size.
  void slope(
    List<num> at,
    List<num> size,
    String material,
    String uphill, {
    String? surface,
  }) {
    _checkRamp(uphill);
    brushes.add(<String, Object?>{
      'at': roundedVector(at),
      'size': roundedVector(size),
      'material': material,
      'ramp': uphill,
      if (surface != null && surface.isNotEmpty) 'surface': surface,
    });
  }

  /// A brush that is not the route, refused where it would stand on it.
  void fill(List<num> at, List<num> size, String material, {String? surface}) {
    final x0 = at[0] - size[0] / 2;
    final x1 = at[0] + size[0] / 2;
    final z0 = at[2] - size[2] / 2;
    final z1 = at[2] + size[2] / 2;
    for (final (cx0, cx1, cz0, cz1) in clear) {
      if (x0 < cx1 && x1 > cx0 && z0 < cz1 && z1 > cz0) {
        throw GeneratorRefused('filling at $at size $size sits on the route');
      }
    }
    brushes.add(<String, Object?>{
      'at': roundedVector(at),
      'size': roundedVector(size),
      'material': material,
      if (surface != null && surface.isNotEmpty) 'surface': surface,
    });
  }

  /// A coin, on the route if it is named and in the filling if it is not.
  void coin(List<num> at, [String? name]) {
    _coins++;
    (name != null ? entities : _filling).add(<String, Object?>{
      'type': 'collectible',
      'name': name ?? 'coin ${'$_coins'.padLeft(3, '0')}',
      'at': roundedVector(at),
      'what': 'coin',
      'model': _coinModel,
    });
  }

  /// A crate, on the route if it is named and in the filling if it is not.
  void crate(List<num> at, [String? name]) {
    _crates++;
    (name != null ? entities : _filling).add(<String, Object?>{
      'type': 'crate',
      'name': name ?? 'crate ${'$_crates'.padLeft(2, '0')}',
      'at': roundedVector(at),
      'size': const <num>[1.4, 1.4, 1.4],
      'mass': 30.0,
      'material': 'wood',
    });
  }

  void spring(String name, List<num> at, {num speed = 15.0, num size = 2.6}) =>
      entities.add(<String, Object?>{
        'type': 'spring',
        'name': name,
        'at': roundedVector(at),
        'size': <num>[size, 0.4, size],
        'speed': speed,
        'material': 'brass',
      });

  /// A post across the way, and where a death after it puts you back. [y] is
  /// the floor the post stands on.
  void checkpoint(
    String name,
    num z,
    int order, {
    num? respawn,
    num y = 0.0,
    num x = 0.0,
  }) => entities.add(<String, Object?>{
    'type': 'checkpoint',
    'name': name,
    'at': roundedVector(<num>[x, y + 1.0, z]),
    'order': order,
    'respawn': roundedVector(<num>[x, y, respawn ?? z]),
    'size': <num>[24.0, 3.0, 1.0],
  });

  void hazard(
    String name,
    List<num> at,
    List<num> size, {
    num? damage,
    bool instant = false,
  }) => entities.add(<String, Object?>{
    'type': 'hazard',
    'name': name,
    'at': roundedVector(at),
    'size': roundedVector(size),
    if (instant) 'instant': true else 'damage': damage ?? 45.0,
  });

  void mover(
    String kind,
    String name,
    List<num> at,
    List<num> size,
    List<num> travel,
    num speed,
    num wait, {
    num? phase,
  }) => entities.add(<String, Object?>{
    'type': kind,
    'name': name,
    'at': roundedVector(at),
    'size': roundedVector(size),
    'travel': roundedVector(travel),
    'speed': speed,
    'wait': wait,
    'material': 'brass',
    'phase': ?phase,
  });

  /// A platform you jump up through and land on top of.
  void oneway(
    String name,
    List<num> at, {
    List<num> size = const <num>[5.0, 0.3, 5.0],
  }) => entities.add(<String, Object?>{
    'type': 'oneway',
    'name': name,
    'at': roundedVector(at),
    'size': roundedVector(size),
    'material': 'wood',
  });

  /// A floor that carries whoever stands on it. The belt does not move.
  void conveyor(
    String name,
    List<num> at,
    List<num> flow, {
    List<num> size = const <num>[5.0, 0.4, 12.0],
  }) => entities.add(<String, Object?>{
    'type': 'conveyor',
    'name': name,
    'at': roundedVector(at),
    'size': roundedVector(size),
    'flow': roundedVector(flow),
    'material': 'brass',
  });

  void crumbling(
    String name,
    List<num> at, {
    List<num> size = const <num>[3.5, 0.4, 3.5],
    num delay = 0.45,
    num gone = 2.5,
  }) => entities.add(<String, Object?>{
    'type': 'crumbling',
    'name': name,
    'at': roundedVector(at),
    'size': roundedVector(size),
    'delay': delay,
    'gone': gone,
    'material': 'wood',
  });

  void breakable(
    String name,
    List<num> at, {
    List<num> size = const <num>[2.0, 2.0, 2.0],
  }) => entities.add(<String, Object?>{
    'type': 'breakable',
    'name': name,
    'at': roundedVector(at),
    'size': roundedVector(size),
    'material': 'stone',
  });

  /// A ladder, or — with a [swing] on it — a rope.
  void climbable(
    String name,
    List<num> at, {
    List<num> size = const <num>[1.2, 8.0, 1.2],
    num swing = 0.0,
    num period = 2.4,
    num phase = 0.0,
  }) => entities.add(<String, Object?>{
    'type': 'climbable',
    'name': name,
    'at': roundedVector(at),
    'size': roundedVector(size),
    // A rope is brass and keeps the key where the ladder's wood was.
    'material': swing != 0 ? 'brass' : 'wood',
    if (swing != 0) ...<String, Object?>{
      'swing': swing,
      'period': period,
      'phase': phase,
    },
  });

  /// Something that walks and hurts on contact.
  ///
  /// A `patrol` and a `leaper` walk the [route]; a `hunter` holds none, so the
  /// key is omitted for one rather than written empty. [sight] and [patience]
  /// left out mean the defaults in `EnemyKind`.
  void enemy(
    String name,
    List<num> at, {
    List<List<num>> route = const <List<num>>[],
    String kind = 'patrol',
    num speed = 0.55,
    List<num> size = const <num>[0.7, 0.7, 0.7],
    num? sight,
    num? patience,
  }) => entities.add(<String, Object?>{
    'type': 'enemy',
    'name': name,
    'at': roundedVector(at),
    'size': roundedVector(size),
    'kind': kind,
    'speed': speed,
    'material': 'brass',
    if (route.isNotEmpty)
      'route': <List<double>>[for (final point in route) roundedVector(point)],
    'sight': ?sight,
    'patience': ?patience,
  });

  /// Something to see by, and something to see.
  void lamp(
    String name,
    List<num> at, {
    List<num> size = const <num>[0.4, 1.6, 0.4],
  }) => entities.add(<String, Object?>{
    'type': 'lamp',
    'name': name,
    'at': roundedVector(at),
    'size': roundedVector(size),
    'material': 'brass',
  });

  /// A volume that works a mechanism by being walked into — how a platformer
  /// opens a door, having no use key.
  void plate(
    String name,
    String target,
    List<num> at, {
    List<num> size = const <num>[4.0, 2.0, 4.0],
  }) => entities.add(<String, Object?>{
    'type': 'trigger',
    'name': name,
    'at': roundedVector(at),
    'size': roundedVector(size),
    'target': target,
    'once': false,
  });

  void spawn(List<num> at) => entities.add(<String, Object?>{
    'type': 'player_spawn',
    'at': roundedVector(at),
  });

  /// A key on the floor. [colour] is the word a gate names to ask for it.
  void key(String name, List<num> at, String colour) =>
      entities.add(<String, Object?>{
        'type': 'key',
        'name': name,
        'at': roundedVector(at),
        'color': colour,
        'material': 'brass',
        'model': 'assets_src/models/key.glb',
      });

  /// A door that needs a key, and the stone over it.
  ///
  /// [lintel] is the top of the wall this door stands in. **Give it one and
  /// the slot above the door cannot be left open**: the wall from the door's
  /// head to [lintel] is written here, and a door with stone over it sinks
  /// rather than rising, because there is nowhere to rise into. Four of five
  /// gates once shipped with that hole, and an autopilot carrying no key went
  /// over one and finished the game. [travel] overrides all of that.
  void gate(
    String name,
    List<num> at,
    String colour, {
    List<num> size = const <num>[4.0, 5.0, 2.0],
    List<num>? travel,
    num? lintel,
    String material = 'stone',
  }) {
    final head = at[1] + size[1] / 2.0;
    final sunk = switch (lintel) {
      null => null,
      final top when top < head - 0.01 => throw GeneratorRefused(
        'gate "$name" is ${size[1]} m tall in a wall '
        '${top - at[1] + size[1] / 2.0} m tall: the door is taller than the '
        'wall it is set into',
      ),
      final top when top > head + 0.01 => top,
      _ => null,
    };
    if (sunk != null) {
      route(
        <num>[at[0], (head + sunk) / 2.0, at[2]],
        <num>[size[0], sunk - head, size[2]],
        material,
      );
    }
    final moves =
        travel ??
        (sunk != null
            ? <num>[0.0, -(size[1] + 0.2), 0.0]
            : <num>[0.0, size[1] + 0.2, 0.0]);
    entities.add(<String, Object?>{
      'type': 'door',
      'name': name,
      'at': roundedVector(at),
      'size': roundedVector(size),
      'travel': roundedVector(moves),
      'speed': 6.0,
      'wait': 0.0,
      'key': colour,
      'material': 'brass',
    });
  }

  void exitAt(
    String name,
    List<num> at,
    String text, {
    List<num> size = const <num>[5.0, 3.0, 5.0],
  }) => entities.add(<String, Object?>{
    'type': 'exit',
    'name': name,
    'at': roundedVector(at),
    'size': roundedVector(size),
    'text': text,
  });

  static Row pointLight(
    List<num> at,
    List<num> colour, {
    num intensity = 26.0,
    num range = 44.0,
  }) => <String, Object?>{
    'at': roundedVector(at),
    'color': colour,
    'intensity': intensity,
    'range': range,
  };

  void pillar(
    num x,
    num z,
    num height, {
    num width = 2.4,
    String material = 'stone',
    bool topCoin = true,
  }) {
    fill(<num>[x, height / 2, z], <num>[width, height, width], material);
    if (topCoin) coin(<num>[x, height + 0.8, z]);
  }

  void hut(
    num x,
    num z,
    num height, {
    num width = 7.0,
    String material = 'stone',
    bool topCoin = true,
  }) {
    fill(<num>[x, height / 2, z], <num>[width, height, width], material);
    if (topCoin) coin(<num>[x, height + 0.8, z]);
  }

  void plank(
    num x,
    num z,
    bool alongX,
    num length,
    num y, {
    String material = 'wood',
  }) => fill(
    <num>[x, y, z],
    alongX ? <num>[length, 0.3, 2.0] : <num>[2.0, 0.3, length],
    material,
  );

  /// A stepped block, coins on every terrace. Steps are climbable by design.
  void ziggurat(
    num x,
    num z,
    int levels,
    num stepHeight,
    num base, {
    String material = 'stone',
  }) {
    for (var i = 0; i < levels; i++) {
      final side = base - i * (base / (levels + 1));
      final top = (i + 1) * stepHeight;
      fill(<num>[x, top / 2, z], <num>[side, top, side], material);
      coin(<num>[x + side / 2 - 1.0, top + 0.8, z]);
      coin(<num>[x - side / 2 + 1.0, top + 0.8, z]);
    }
  }

  static Row _textured(String name, num texels) => <String, Object?>{
    'roughness': 1.0,
    'albedo': 'assets/textures/${name}_albedo.png',
    'normal': 'assets/textures/${name}_normal.png',
    'orm': 'assets/textures/${name}_orm.png',
    'texelsPerMetre': texels,
  };

  /// The table every platformer level carries.
  static final Map<String, Row> materials = <String, Row>{
    'moss': _textured('moss', 0.5),
    'stone': _textured('stone', 0.5),
    'brass': <String, Object?>{..._textured('brass', 1.0), 'metallic': 1.0},
    'wood': _textured('wood', 0.7),
    'ice': _textured('ice', 0.4),
  };

  /// The sun every level is lit by. Steep-ish, and it can afford to be: the
  /// renderer has cascades.
  static const Row sun = <String, Object?>{
    'type': 'directional',
    'direction': <num>[-0.35, -0.85, 0.4],
    'color': <num>[1.0, 0.96, 0.88],
    'intensity': 2.6,
    'castsShadow': true,
  };

  /// Things a player is meant to reach. A brush through one is a coin nobody
  /// can take, and it looks perfectly fine in the document — which is why this
  /// is checked rather than reviewed.
  static const List<String> reachable = <String>['collectible', 'crate', 'key'];

  /// Every reachable entity whose middle is inside a solid brush.
  ///
  /// The centre rather than the whole box: a coin whose edge grazes a wall is
  /// fine and common. A centre inside solid is never right.
  List<String> _buried() => <String>[
    for (final e in <Row>[...entities, ..._filling])
      if (reachable.contains(e['type']) && e['at'] != null)
        if (_wallOf((e['at']! as List<Object?>).cast<num>()) case final b?)
          _inside(e, b),
  ];

  /// The brush is named too: working out *which* one buried a coin by
  /// reading coordinates is the slow half of fixing it.
  static String _inside(Row e, Row b) =>
      '  ${e['name'] ?? e['type']} at ${_listText(e['at'])} is inside the '
      '${b['material']} at ${_listText(b['at'])} size ${_listText(b['size'])}';

  Row? _wallOf(List<num> at) {
    for (final b in brushes) {
      final c = (b['at']! as List<Object?>).cast<num>();
      final s = (b['size']! as List<Object?>).cast<num>();
      final inBox = <int>[0, 1, 2].every(
        (int i) =>
            c[i] - s[i] / 2 + 0.01 < at[i] && at[i] < c[i] + s[i] / 2 - 0.01,
      );
      if (inBox && _solidAt(b, at)) return b;
    }
    return null;
  }

  /// Whether a point inside a brush's box is inside the brush itself. **A
  /// ramp's box is half empty**, and that half is exactly where a coin wants
  /// to hang.
  static bool _solidAt(Row b, List<num> at) {
    final ramp = b['ramp'] as String?;
    if (ramp == null || ramp.isEmpty) return true;
    final c = (b['at']! as List<Object?>).cast<num>();
    final s = (b['size']! as List<Object?>).cast<num>();
    final axis = ramp[1] == 'x' ? 0 : 2;
    final sign = ramp[0] == '+' ? 1.0 : -1.0;
    final along = (sign * (at[axis] - c[axis]) / (s[axis] / 2) + 1.0) / 2.0;
    return at[1] < c[1] - s[1] / 2 + s[1] * along;
  }

  static String _listText(Object? list) => DocumentText.inline(list);

  /// The document, as text, after refusing one with something buried.
  String write({
    required String name,
    required List<Row> lights,
    required String tool,
    List<num> fog = const <num>[0.05, 0.07, 0.12],
    num density = 0.004,
    String? next,
  }) {
    final walledIn = _buried();
    if (walledIn.isNotEmpty) {
      throw GeneratorRefused(
        '${walledIn.length} things a player is meant to reach are inside '
        'solid brushes:\n${walledIn.join('\n')}',
      );
    }
    final document = <String, Object?>{
      'version': 1,
      'name': name,
      'generatedBy': tool,
      'fogColor': fog,
      'fogDensity': density,
      'materials': materials,
      'brushes': brushes,
      'lights': lights,
      'entities': <Row>[...entities, ..._filling],
      if (next != null && next.isNotEmpty) 'next': next,
    };
    return '${DocumentText.compact(document)}\n';
  }
}
