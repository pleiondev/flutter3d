/// What a template gives a new game: a vocabulary and a first level.
///
/// **A new game has told the editor nothing, and cannot.** The palette is
/// built from the document, and a game says what its own words look like in
/// `assets/editor.json` — both of which need a game that already exists. A
/// template is that file and that level, written before there is anybody to
/// write them, and read back from the new project by the same `Looks.parse`
/// that reads the crypt's.
///
/// The words are not invented here: they are the genre packages' own, at the
/// sizes those packages give as defaults, and a test asserts every one still
/// exists. `secret` is deliberately absent: it is not in `sampleRegistry()`,
/// so a level containing one does not validate.
///
/// ## The first level is the part that is easy to get wrong
///
/// `LevelLoader.build` throws on a validation error, so a bad starter level is
/// a game that will not start. The room is one storey, walls butted to the
/// floor and to each other (more than 0.05 m³ of shared volume is a warning
/// per pair), lit by one lamp with a range, with exactly one spawn and an
/// exit — and the test that matters asserts zero errors and zero warnings.
///
/// Racing gets a field and no road, because a circuit is a second document
/// and nothing in this repository edits one. Strategy gets the map the demo
/// plays, read rather than guessed at.
library;

import 'dart:convert';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

typedef _Row = Map<String, Object?>;

const String _templates = 'apps/flutter3d_editor/assets/templates';

/// One genre's template.
final class _Template {
  const _Template({
    required this.name,
    required this.about,
    required this.types,
    required this.level,
  });

  final String name;
  final String about;

  /// What a level of this genre can hold, and at what size a click hits it.
  final Map<String, _Row> types;

  /// The first level, from the genre and what the generator may read.
  final _Row Function(String genre, _Template template, GeneratorSource source)
  level;
}

/// Every template, and the files that come with each.
Map<String, String> templates(GeneratorSource source) {
  final out = <String, String>{
    // The list the editor reads first. A bundle cannot be listed, so what
    // templates exist has to be written down like everything else.
    '$_templates/index.json': _dump(<String, Object?>{
      'templates': _all.keys.toList()..sort(),
    }),
  };
  for (final MapEntry(key: genre, value: template) in _all.entries) {
    final where = '$_templates/$genre';
    // The models a template ships are the ones the model generator wrote
    // beside it: `model.<name>.glb`.
    final models = <String>[
      for (final file in source.list(where))
        if (file.startsWith('model.') && file.endsWith('.glb'))
          file.substring('model.'.length, file.length - '.glb'.length),
    ]..sort();
    // Every model path written the way it will be read: from inside the
    // project this gets copied into.
    final types = <String, Object?>{
      for (final MapEntry(key: name, value: look) in template.types.entries)
        name: <String, Object?>{
          ...look,
          if (models.contains(name)) 'model': 'assets/models/$name.glb',
        },
    };
    out['$where/editor.json'] = _dump(types);
    out['$where/level.first.json'] = _dump(
      template.level(genre, template, source),
    );
    for (final MapEntry(key: name, value: (from, _)) in _app.entries) {
      out['$where/$name'] = source.read(from);
    }
    // The manifest: what to copy, and where it lands in a new project. A file
    // missing from `pubspec.yaml`'s `assets:` throws at scaffold time in front
    // of somebody; a test walks this list instead.
    out['$where/index.json'] = _dump(<String, Object?>{
      'name': template.name,
      'about': template.about,
      'files': <String, Object?>{
        'editor.json': 'assets/editor.json',
        'level.first.json': 'assets/levels/first.json',
        for (final MapEntry(key: name, value: (_, to)) in _app.entries)
          name: to,
        for (final name in models) 'model.$name.glb': 'assets/models/$name.glb',
      },
    });
  }
  return out;
}

/// Two spaces and a trailing newline, which is what `Editing.write` produces
/// — otherwise the first save in a new project rewrites the whole file.
String _dump(Object? document) => '${DocumentText.indented(document, 2)}\n';

/// Four walls, a floor and a ceiling that share faces and nothing else: the
/// long walls run the full width and the end walls fill what is left.
List<_Row> _room({double size = 16.0, double height = 4.0}) {
  final half = size / 2;
  return <_Row>[
    <String, Object?>{
      'at': <double>[0.0, -0.5, 0.0],
      'size': <double>[size, 1.0, size],
      'material': 'floor',
    },
    <String, Object?>{
      'at': <double>[0.0, height + 0.5, 0.0],
      'size': <double>[size, 1.0, size],
      'material': 'ceiling',
    },
    <String, Object?>{
      'at': <double>[0.0, height / 2, -(half + 0.5)],
      'size': <double>[size, height, 1.0],
      'material': 'wall',
    },
    <String, Object?>{
      'at': <double>[0.0, height / 2, half + 0.5],
      'size': <double>[size, height, 1.0],
      'material': 'wall',
    },
    <String, Object?>{
      'at': <double>[-(half + 0.5), height / 2, 0.0],
      'size': <double>[1.0, height, size + 2.0],
      'material': 'wall',
    },
    <String, Object?>{
      'at': <double>[half + 0.5, height / 2, 0.0],
      'size': <double>[1.0, height, size + 2.0],
      'material': 'wall',
    },
  ];
}

/// A document in the shape the writer produces, so it round-trips: the keys
/// in the order `Level.toJson` writes them, with what the format does not
/// know — `generatedBy`, `editor`, strategy's `goal` — where it should stay.
/// [before] and [after] put a genre's own section somewhere and keep it there.
_Row _level(
  String name,
  String template, {
  required Object? materials,
  required Object? brushes,
  required Object? lights,
  required Object? entities,
  required Object? fog,
  num density = 0.0,
  _Row before = const <String, Object?>{},
  _Row after = const <String, Object?>{},
}) => <String, Object?>{
  'version': 1,
  'name': name,
  'generatedBy': 'tool/make_templates.py',
  // Which template this came from, so the palette can be rebuilt if
  // `assets/editor.json` is lost; `Level.toJson` writes unknown keys back.
  'editor': <String, Object?>{'template': template},
  ...before,
  'fogColor': fog,
  'fogDensity': density,
  'materials': materials,
  'brushes': brushes,
  'lights': lights,
  'entities': entities,
  ...after,
};

/// One lamp, with a range: a point light without one lights the level through
/// its own walls.
const List<_Row> _indoorLight = <_Row>[
  <String, Object?>{
    'type': 'point',
    'at': <double>[0.0, 3.2, 0.0],
    'color': <double>[1.0, 0.92, 0.78],
    'intensity': 9.0,
    'range': 16.0,
  },
];

/// The first level of a genre played inside a building: one room.
_Row Function(String, _Template, GeneratorSource) _indoors({
  required _Row materials,
  required List<double> fog,
  required List<_Row> entities,
}) =>
    (String genre, _Template template, GeneratorSource _) => _level(
      '${template.name.toLowerCase()} start',
      genre,
      materials: materials,
      brushes: _room(),
      lights: _indoorLight,
      entities: entities,
      fog: fog,
    );

const _Row _stone = <String, Object?>{
  'floor': <String, Object?>{
    'baseColor': <double>[0.42, 0.40, 0.38, 1.0],
    'roughness': 0.9,
  },
  'wall': <String, Object?>{
    'baseColor': <double>[0.50, 0.47, 0.44, 1.0],
    'roughness': 0.85,
  },
  'ceiling': <String, Object?>{
    'baseColor': <double>[0.28, 0.27, 0.26, 1.0],
    'roughness': 0.95,
  },
};

const _Row _paint = <String, Object?>{
  'floor': <String, Object?>{
    'baseColor': <double>[0.35, 0.45, 0.32, 1.0],
    'roughness': 0.9,
  },
  'wall': <String, Object?>{
    'baseColor': <double>[0.52, 0.44, 0.36, 1.0],
    'roughness': 0.85,
  },
  'ceiling': <String, Object?>{
    'baseColor': <double>[0.30, 0.34, 0.42, 1.0],
    'roughness': 0.9,
  },
};

const _Row _turf = <String, Object?>{
  'grass': <String, Object?>{
    'baseColor': <double>[0.18, 0.30, 0.14, 1.0],
    'roughness': 1.0,
  },
  'stone': <String, Object?>{
    'baseColor': <double>[0.45, 0.44, 0.42, 1.0],
    'roughness': 0.9,
  },
};

/// The coordinates along one side of a square of posts, ends included.
List<double> _fence(double extent, double step) => <double>[
  for (var i = 0; i < (2 * extent / step).toInt() + 1; i++)
    roundDecimal(-extent + i * step, 3),
];

/// Somewhere to drive, with nothing to drive on yet: **the half of a circuit
/// that is a level.** The turf's top is [floor] rather than zero because a
/// road dips; `surface` is on the turf because a racing game asks the brush
/// under a wheel what it is. The posts stand on a square rather than a ring:
/// a fence needs no trigonometry, and trigonometry is libm's last bit.
List<_Row> _paddock({
  double reach = 200.0,
  double extent = 150.0,
  double step = 50.0,
  double floor = -1.5,
}) {
  const thickness = 4.0;
  const height = 12.0;
  final posts = <(double, double)>[
    for (final x in _fence(extent, step))
      for (final z in <double>[-extent, extent]) (x, z),
    for (final x in <double>[-extent, extent])
      for (final z in _fence(extent - step, step)) (x, z),
  ];
  return <_Row>[
    <String, Object?>{
      'at': <double>[0.0, floor - thickness / 2, 0.0],
      'size': <double>[reach * 2, thickness, reach * 2],
      'material': 'grass',
      'surface': 'grass',
    },
    for (final (x, z) in posts)
      <String, Object?>{
        'at': <double>[x, floor + height / 2, z],
        'size': const <double>[4.0, height, 4.0],
        'material': 'stone',
      },
  ];
}

/// The air the racing template is raced in: `SkyPresets.morning`, not numbers
/// chosen beside it, so the sky and the fog cannot disagree.
/// `templates_test.dart` checks these against the preset.
const List<_Row> _morningSun = <_Row>[
  <String, Object?>{
    'type': 'directional',
    // `SkyPreset.sunDirection`, rounded the way the track generator rounds it.
    'direction': <double>[-0.769, -0.559, 0.311],
    'color': <double>[1.0, 0.95, 0.86],
    'intensity': 3.1,
    'castsShadow': true,
  },
];
const List<double> _morningHaze = <double>[0.66, 0.75, 0.85];
const double _morningDensity = 0.0042;

/// A field, a fence and a morning — and no circuit.
_Row _racingLevel(String genre, _Template template, GeneratorSource _) =>
    _level(
      '${template.name.toLowerCase()} start',
      genre,
      materials: _turf,
      brushes: _paddock(),
      lights: _morningSun,
      // **Empty on purpose**: a circuit places nothing, and the racing demo
      // loads its level with an empty `EntityRegistry` for that reason.
      entities: const <Object?>[],
      fog: _morningHaze,
      density: _morningDensity,
    );

/// The map the strategy demo plays, as the first level of a new project —
/// read rather than invented, with three lines changed: what it is called,
/// what wrote it, and which template it belongs to.
_Row _strategyLevel(String genre, _Template template, GeneratorSource source) {
  final played =
      jsonDecode(
            source.read(
              'apps/flutter3d_demo_strategy/assets/levels/map_a.json',
            ),
          )
          as Map<String, Object?>;
  return _level(
    '${template.name.toLowerCase()} start',
    genre,
    materials: played['materials'],
    brushes: played['brushes'],
    lights: played['lights'],
    entities: played['entities'],
    // Open air under one sun and no density: a map this size read through
    // fog is a map nobody can command from above.
    fog: const <double>[0.58, 0.66, 0.74],
    before: <String, Object?>{'goal': played['goal']},
    after: <String, Object?>{'heightfield': played['heightfield']},
  );
}

// What each genre can put in a level, at the sizes its own package gives.
// `size` is the box a click has to hit, never written into a document;
// `defaults` is written, and only where the game needs it.

const Map<String, _Row> _shooterTypes = <String, _Row>{
  'player_spawn': <String, Object?>{
    'size': <double>[0.7, 1.8, 0.7],
  },
  'monster': <String, Object?>{
    'size': <double>[0.7, 1.7, 0.7],
    'defaults': <String, Object?>{'kind': 'runner'},
  },
  'pickup': <String, Object?>{
    'size': <double>[0.45, 0.45, 0.45],
    'defaults': <String, Object?>{'gives': 'health', 'amount': 25},
  },
  'key': <String, Object?>{
    'size': <double>[0.4, 0.4, 0.4],
    'defaults': <String, Object?>{'color': 'iron'},
  },
  'note': <String, Object?>{
    'size': <double>[0.4, 0.5, 0.06],
    'defaults': <String, Object?>{'text': 'Somebody wrote something here.'},
  },
  'torch': <String, Object?>{
    'size': <double>[0.3, 0.55, 0.4],
  },
  'lamp': <String, Object?>{
    'size': <double>[0.34, 0.34, 0.34],
    'defaults': <String, Object?>{'color': 'warm'},
  },
  'window': <String, Object?>{
    'size': <double>[1.4, 2.2, 0.12],
    'defaults': <String, Object?>{
      'size': <double>[1.4, 2.2, 0.12],
    },
  },
  'door': <String, Object?>{
    'size': <double>[4.0, 4.0, 1.0],
    'defaults': <String, Object?>{
      'size': <double>[4.0, 4.0, 1.0],
      'travel': <double>[0.0, 3.8, 0.0],
      'speed': 2.2,
      'wait': 4.0,
    },
  },
  'lift': <String, Object?>{
    'size': <double>[3.0, 0.5, 3.0],
    'defaults': <String, Object?>{
      'size': <double>[3.0, 0.5, 3.0],
      'travel': <double>[0.0, 4.0, 0.0],
      'speed': 1.5,
      'wait': 2.0,
    },
  },
  'platform': <String, Object?>{
    'size': <double>[3.0, 0.4, 3.0],
    'defaults': <String, Object?>{
      'size': <double>[3.0, 0.4, 3.0],
      'travel': <double>[4.0, 0.0, 0.0],
      'speed': 1.5,
    },
  },
  'button': <String, Object?>{
    'size': <double>[0.6, 0.6, 0.15],
    'defaults': <String, Object?>{
      'size': <double>[0.6, 0.6, 0.15],
    },
  },
  'trigger': <String, Object?>{
    'size': <double>[4.0, 3.0, 2.0],
    'defaults': <String, Object?>{
      'size': <double>[4.0, 3.0, 2.0],
      'once': false,
    },
  },
  'exit': <String, Object?>{
    'size': <double>[1.5, 2.5, 1.5],
  },
};

const Map<String, _Row> _platformerTypes = <String, _Row>{
  'player_spawn': <String, Object?>{
    'size': <double>[0.7, 1.8, 0.7],
  },
  'collectible': <String, Object?>{
    'size': <double>[0.5, 0.5, 0.5],
    'defaults': <String, Object?>{'what': 'coin'},
  },
  'key': <String, Object?>{
    'size': <double>[0.5, 0.5, 0.5],
    'defaults': <String, Object?>{'color': 'green'},
  },
  'enemy': <String, Object?>{
    'size': <double>[0.7, 0.7, 0.7],
    'defaults': <String, Object?>{
      'size': <double>[0.7, 0.7, 0.7],
      'kind': 'patrol',
    },
  },
  'lamp': <String, Object?>{
    'size': <double>[0.4, 1.6, 0.4],
    'defaults': <String, Object?>{
      'size': <double>[0.4, 1.6, 0.4],
    },
  },
  'checkpoint': <String, Object?>{
    'size': <double>[0.35, 2.2, 0.35],
    'defaults': <String, Object?>{
      'size': <double>[3.0, 3.0, 3.0],
    },
  },
  'crate': <String, Object?>{
    'size': <double>[1.2, 1.2, 1.2],
    'defaults': <String, Object?>{
      'size': <double>[1.2, 1.2, 1.2],
      'mass': 40.0,
    },
  },
  'breakable': <String, Object?>{
    'size': <double>[2.0, 1.2, 2.0],
    'defaults': <String, Object?>{
      'size': <double>[2.0, 1.2, 2.0],
    },
  },
  'climbable': <String, Object?>{
    'size': <double>[1.0, 6.0, 1.0],
    'defaults': <String, Object?>{
      'size': <double>[1.0, 6.0, 1.0],
    },
  },
  'conveyor': <String, Object?>{
    'size': <double>[4.0, 0.4, 8.0],
    'defaults': <String, Object?>{
      'size': <double>[4.0, 0.4, 8.0],
      'flow': 3.0,
    },
  },
  'crumbling': <String, Object?>{
    'size': <double>[3.0, 0.4, 3.0],
    'defaults': <String, Object?>{
      'size': <double>[3.0, 0.4, 3.0],
    },
  },
  'hazard': <String, Object?>{
    'size': <double>[4.0, 0.8, 4.0],
    'defaults': <String, Object?>{
      'size': <double>[4.0, 0.8, 4.0],
    },
  },
  'oneway': <String, Object?>{
    'size': <double>[4.0, 0.3, 4.0],
    'defaults': <String, Object?>{
      'size': <double>[4.0, 0.3, 4.0],
    },
  },
  'spring': <String, Object?>{
    'size': <double>[1.6, 0.4, 1.6],
    'defaults': <String, Object?>{
      'size': <double>[1.6, 0.4, 1.6],
    },
  },
  'door': <String, Object?>{
    'size': <double>[4.0, 5.0, 2.0],
    'defaults': <String, Object?>{
      'size': <double>[4.0, 5.0, 2.0],
      'travel': <double>[0.0, 5.0, 0.0],
      'speed': 2.0,
      'wait': 3.0,
    },
  },
  'lift': <String, Object?>{
    'size': <double>[4.0, 0.6, 4.0],
    'defaults': <String, Object?>{
      'size': <double>[4.0, 0.6, 4.0],
      'travel': <double>[0.0, 6.0, 0.0],
      'speed': 2.0,
      'wait': 1.5,
    },
  },
  'platform': <String, Object?>{
    'size': <double>[4.0, 0.6, 4.0],
    'defaults': <String, Object?>{
      'size': <double>[4.0, 0.6, 4.0],
      'travel': <double>[6.0, 0.0, 0.0],
      'speed': 2.0,
    },
  },
  'button': <String, Object?>{
    'size': <double>[0.6, 0.6, 0.15],
    'defaults': <String, Object?>{
      'size': <double>[0.6, 0.6, 0.15],
    },
  },
  'trigger': <String, Object?>{
    'size': <double>[4.0, 2.0, 4.0],
    'defaults': <String, Object?>{
      'size': <double>[4.0, 2.0, 4.0],
      'once': false,
    },
  },
  'exit': <String, Object?>{
    'size': <double>[5.0, 3.0, 5.0],
    'defaults': <String, Object?>{
      'size': <double>[5.0, 3.0, 5.0],
    },
  },
};

/// What a strategy map has on it, at the sizes the strategy package draws
/// them. `defaults` carries only what a document can be right about without
/// the rest of the map: no name a worker or producer points at, because a
/// default naming some other entity is wrong on a map without it.
const Map<String, _Row> _strategyTypes = <String, _Row>{
  'camp': <String, Object?>{
    'size': <double>[12.0, 3.0, 10.0],
    'defaults': <String, Object?>{'side': 0, 'width': 12.0, 'depth': 10.0},
  },
  'worker': <String, Object?>{
    'size': <double>[0.8, 1.2, 0.8],
    'defaults': <String, Object?>{
      'side': 0,
      'count': 10,
      'across': 5,
      'spacing': 1.1,
    },
  },
  'resource_node': <String, Object?>{
    'size': <double>[4.0, 1.0, 4.0],
    'defaults': <String, Object?>{'amount': 1600.0},
  },
  'stockpile': <String, Object?>{
    'size': <double>[1.2, 1.2, 1.2],
    'defaults': <String, Object?>{'side': 0, 'amount': 0.0},
  },
  'producer': <String, Object?>{
    'size': <double>[1.2, 1.2, 1.2],
    // `Producer`'s own defaults, which `openMatch` falls back to as well.
    'defaults': <String, Object?>{'cost': 25.0, 'seconds': 4.0},
  },
};

final Map<String, _Template> _all = <String, _Template>{
  'shooter': _Template(
    name: 'Shooter',
    about: 'Rooms, monsters, keys and a way down.',
    types: _shooterTypes,
    level: _indoors(
      materials: _stone,
      fog: const <double>[0.05, 0.04, 0.06],
      entities: const <_Row>[
        <String, Object?>{
          'type': 'player_spawn',
          'at': <double>[0.0, 0.0, 5.0],
          'yaw': 0.0,
        },
        <String, Object?>{
          'type': 'torch',
          'at': <double>[-7.7, 2.6, 0.0],
          'yaw': 1.5708,
        },
        <String, Object?>{
          'type': 'pickup',
          'at': <double>[3.0, 0.6, 1.0],
          'gives': 'health',
          'amount': 25,
        },
        <String, Object?>{
          'type': 'exit',
          'at': <double>[0.0, 1.25, -6.5],
          'yaw': 0.0,
        },
      ],
    ),
  ),
  'platformer': _Template(
    name: 'Platformer',
    about: 'A room to jump around, coins to take and a way out.',
    types: _platformerTypes,
    level: _indoors(
      materials: _paint,
      fog: const <double>[0.06, 0.07, 0.10],
      entities: const <_Row>[
        <String, Object?>{
          'type': 'player_spawn',
          'at': <double>[0.0, 0.0, 5.0],
          'yaw': 0.0,
        },
        <String, Object?>{
          'type': 'lamp',
          'at': <double>[-6.0, 0.8, -6.0],
          'yaw': 0.0,
          'size': <double>[0.4, 1.6, 0.4],
        },
        <String, Object?>{
          'type': 'collectible',
          'at': <double>[2.0, 0.8, 0.0],
          'what': 'coin',
        },
        <String, Object?>{
          'type': 'collectible',
          'at': <double>[3.5, 0.8, 0.0],
          'what': 'coin',
        },
        <String, Object?>{
          'type': 'exit',
          'at': <double>[0.0, 1.5, -6.0],
          'yaw': 0.0,
          'size': <double>[5.0, 3.0, 5.0],
        },
      ],
    ),
  ),
  // Racing places nothing: the vocabulary a racing project starts with is
  // empty, which is a sentence about the genre and not a gap.
  'racing': const _Template(
    name: 'Racing',
    about: 'Turf to land on, a fence to measure speed against.',
    types: <String, _Row>{},
    level: _racingLevel,
  ),
  'strategy': const _Template(
    name: 'Strategy',
    about: 'A hillside, two halls, two seams and a crowd apiece.',
    types: _strategyTypes,
    level: _strategyLevel,
  ),
};

/// The application a new game starts as, copied beside each template as text
/// — **a real application in this repository, not a string in a
/// scaffolder**, so CI analyses it like everything else. It is the game
/// package's example, because walking a level is game code.
const String _gameSeed = 'packages/flutter3d_game/example';
const Map<String, (String, String)> _app = <String, (String, String)>{
  'app.main.dart.txt': ('$_gameSeed/lib/main.dart', 'lib/main.dart'),
  'app.backend.dart.txt': (
    '$_gameSeed/lib/src/backend.dart',
    'lib/src/backend.dart',
  ),
  // The test a new project comes with, for the same reason.
  'app.test.dart.txt': (
    '$_gameSeed/test/widget_test.dart',
    'test/widget_test.dart',
  ),
};
