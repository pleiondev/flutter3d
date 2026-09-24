/// The racing game's five circuits, each written twice: `<name>.json`, the
/// track with its level inside it, and `<name>_level.json`, the level on its
/// own for `LevelLoader`.
///
/// **Edit this, not the JSON.** A circuit is several hundred numbers that have
/// to agree with each other — a width that changes over four metres of a
/// corner, a barrier that stops halfway along a straight, a checkpoint behind
/// the one before it — and a person editing those by hand introduces exactly
/// one of them and does not notice.
///
/// The shape is a closed curve with a varying radius: the lobes become corners
/// of different speeds, and where the radius closes fastest is where the road
/// narrows and tilts. Everything downstream is measured in metres along that
/// curve.
///
/// **The arithmetic is the one the documents were first written with**, down
/// to the order of the operations, because the files are diffed byte for
/// byte. What still depends on the machine — a sine is libm's, and a norm's
/// last bit is how it was summed — is rounded before it is written: a
/// position to a millimetre, a width, a bank and the lap length to a
/// centimetre.
library;

import 'dart:math' as math;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

const String _tracks = 'apps/flutter3d_demo_racing/assets/tracks';
const String _tool = 'tool/make_track.py';

typedef _Row = Map<String, Object?>;
typedef _Vec = (double, double, double);

/// Everything that makes one circuit different from another.
final class _Circuit {
  const _Circuit({
    required this.name,
    required this.preset,
    this.points = 32,
    this.baseRadius = 150.0,
    this.lobeTwo = 34.0,
    this.lobeThree = 22.0,
    this.lobeFour = 0.0,
    this.relief = 9.0,
    this.widest = 18.0,
    this.narrowest = 11.0,
    this.shoulder = 5.0,
    this.maxBank = 7.0,
    this.lapCheckpoints = 4,
    this.barriers = const <(double, double)>[(0.08, 0.22), (0.58, 0.72)],
    this.pillarClearance = 55.0,
  });

  final String name;

  /// Which hour this circuit is raced at: a key of [_skyPresets].
  final String preset;

  /// How many control points the curve is authored with.
  final int points;

  /// The shape: [baseRadius] sets the size, and each lobe is the amplitude of
  /// one harmonic of the radius — two stretch the ring into an oval, three
  /// bend it into a rounded triangle, four put a corner on each side. The
  /// lobes together have to stay under the base, or the curve crosses itself.
  final double baseRadius;
  final double lobeTwo;
  final double lobeThree;
  final double lobeFour;

  /// How much the circuit climbs and falls, top to bottom.
  final double relief;

  final double widest;
  final double narrowest;

  /// How far the ground either side stays part of the track.
  final double shoulder;

  /// The most a corner is tilted, in degrees, at the tightest radius.
  final double maxBank;

  final int lapCheckpoints;

  /// Walls, as fractions of a lap, down the outside of the fastest corners.
  final List<(double, double)> barriers;

  /// How far out the pillars stand beyond the widest part of the circuit.
  /// Scenery a car can reach is scenery a car will hit.
  final double pillarClearance;
}

/// The season, in the order it is raced.
const List<_Circuit> _circuits = <_Circuit>[
  // The circuit this game has always been raced on, unchanged: every recorded
  // lap, golden frame and playthrough test is of it.
  _Circuit(name: 'ring', preset: 'morning'),
  // Tighter, twice the climb, a road that narrows to nine metres, raced at
  // the end of the day. **How tight is decided by what can be driven**: at a
  // 36-metre radius the reference driver went off at the same corner on every
  // lap; sixty-eight is slower than anything on the ring and still a corner.
  _Circuit(
    name: 'gorge',
    preset: 'golden',
    baseRadius: 120.0,
    lobeTwo: 34.0,
    lobeThree: 18.0,
    relief: 18.0,
    widest: 15.0,
    narrowest: 9.0,
    maxBank: 9.0,
    lapCheckpoints: 6,
    barriers: <(double, double)>[(0.03, 0.17), (0.41, 0.55), (0.70, 0.86)],
    pillarClearance: 70.0,
  ),
  // The flats, first light: a banked oval driven flat out, the one lap in the
  // season about speed rather than the wheel.
  _Circuit(
    name: 'flats',
    preset: 'dawn',
    points: 40,
    baseRadius: 195.0,
    lobeTwo: 34.0,
    lobeThree: 0.0,
    relief: 3.0,
    widest: 24.0,
    narrowest: 18.0,
    shoulder: 7.0,
    maxBank: 11.0,
    barriers: <(double, double)>[(0.0, 0.11), (0.39, 0.61), (0.89, 1.0)],
    pillarClearance: 60.0,
  ),
  // The quarry, noon: corners no tighter than the gorge's and everything else
  // worse — nine and a half metres of road and the most climb in the season,
  // under the clearest air, because a circuit this hilly has to be seen.
  _Circuit(
    name: 'quarry',
    preset: 'noon',
    points: 36,
    baseRadius: 135.0,
    lobeTwo: 24.0,
    lobeThree: 22.0,
    relief: 24.0,
    widest: 14.0,
    narrowest: 9.5,
    maxBank: 8.0,
    lapCheckpoints: 6,
    barriers: <(double, double)>[(0.03, 0.15), (0.36, 0.50), (0.68, 0.82)],
    pillarClearance: 70.0,
  ),
  // The ridge, dusk: the last circuit and the longest lap, with every
  // harmonic the shape has, so the corners come at every rhythm.
  _Circuit(
    name: 'ridge',
    preset: 'dusk',
    points: 48,
    baseRadius: 190.0,
    lobeTwo: 40.0,
    lobeThree: 36.0,
    lobeFour: 20.0,
    relief: 20.0,
    widest: 15.0,
    narrowest: 9.0,
    maxBank: 9.0,
    lapCheckpoints: 8,
    barriers: <(double, double)>[
      (0.02, 0.12),
      (0.27, 0.38),
      (0.52, 0.64),
      (0.78, 0.90),
    ],
    pillarClearance: 75.0,
  ),
];

/// Every circuit's two documents.
Map<String, String> tracks(GeneratorSource _) => <String, String>{
  for (final circuit in _circuits) ..._write(circuit),
};

Map<String, String> _write(_Circuit circuit) {
  _check(circuit);
  final points = _centreLine(circuit);
  final length = _lapLength(points);
  final sky = _skyPresets[circuit.preset]!;
  final level = <String, Object?>{
    'version': 1,
    'name': circuit.name,
    'generatedBy': _tool,
    // Derived from the sky and not read back by the application, which asks
    // the preset; written so anything loading this level alone gets air of
    // the right colour.
    'fogColor': roundedVector(_list(_horizonFogColour(sky))),
    'fogDensity': sky['fogDensity'],
    'materials': _materials,
    'brushes': _ground(circuit, points),
    'lights': _lights(sky),
    'entities': const <Object?>[],
  };
  // The lap length is a sum over points that came out of libm, so it is
  // rounded to a centimetre before anything is written from it.
  final document = <String, Object?>{
    'version': 1,
    'name': circuit.name,
    'generatedBy': _tool,
    'track': <String, Object?>{
      'closed': true,
      'shoulder': circuit.shoulder,
      'points': _build(circuit, points),
      'surfaces': <_Row>[
        <String, Object?>{
          'fromS': 0.0,
          'toS': roundDecimal(length, 2),
          'centre': 'asphalt',
          'shoulder': 'grass',
        },
      ],
      'barriers': <_Row>[
        for (final (start, end) in circuit.barriers)
          <String, Object?>{
            'fromS': roundDecimal(length * start, 2),
            'toS': roundDecimal(length * end, 2),
            'right': true,
          },
      ],
      'checkpoints': <_Row>[
        for (var i = 1; i < circuit.lapCheckpoints; i++)
          <String, Object?>{
            's': roundDecimal(length * i / circuit.lapCheckpoints, 2),
          },
      ],
      'grid': const <String, Object?>{
        's': -14.0,
        'columns': 2,
        'rowGap': 7.0,
        'columnGap': 4.0,
      },
    },
    'sky': sky,
    'level': level,
  };
  return <String, String>{
    '$_tracks/${circuit.name}.json': '${DocumentText.indented(document, 1)}\n',
    '$_tracks/${circuit.name}_level.json':
        '${DocumentText.indented(level, 1)}\n',
  };
}

/// Refuses a circuit that cannot be raced, before it is written: the number
/// at fault is named here rather than as a car off the road later.
void _check(_Circuit c) {
  final lobes = c.lobeTwo.abs() + c.lobeThree.abs() + c.lobeFour.abs();
  final refusal = switch (c) {
    _ when c.baseRadius <= lobes =>
      'the lobes ($lobes) reach the base radius (${c.baseRadius}), so the '
          'circuit would cross itself',
    // The grid starts two cars abreast, four metres apart.
    _ when c.narrowest < 8.0 => 'narrower than the grid at ${c.narrowest} m',
    _ when c.narrowest > c.widest => 'narrowest is wider than widest',
    // One checkpoint is none: a car reversed over the line would count a lap.
    _ when c.lapCheckpoints < 2 => 'a lap needs at least two checkpoints',
    _
        when c.barriers.any(
          ((double, double) b) => !(0.0 <= b.$1 && b.$1 < b.$2 && b.$2 <= 1.0),
        ) =>
      'a barrier is not a stretch of one lap',
    _ when !_skyPresets.containsKey(c.preset) => 'no preset called ${c.preset}',
    _ => null,
  };
  if (refusal != null) throw GeneratorRefused('${c.name}: $refusal');
}

/// The control points.
List<_Vec> _centreLine(_Circuit c) => <_Vec>[
  for (var i = 0; i < c.points; i++)
    () {
      final angle = 2 * math.pi * i / c.points;
      final radius =
          c.baseRadius +
          c.lobeTwo * math.cos(2 * angle) +
          c.lobeThree * math.cos(3 * angle) +
          c.lobeFour * math.cos(4 * angle);
      return (
        radius * math.cos(angle),
        c.relief * 0.5 * math.sin(angle) -
            c.relief * 0.25 * math.cos(2 * angle),
        radius * math.sin(angle),
      );
    }(),
];

/// How sharply the line bends at point [i], from its neighbours: the angle
/// between the two chords over the distance they cover. An estimate, used
/// only to decide where the road narrows and tilts.
double _curvatureAt(List<_Vec> points, int i) {
  final n = points.length;
  final before = points[(i - 1) % n];
  final here = points[i];
  final after = points[(i + 1) % n];
  final ax = here.$1 - before.$1;
  final az = here.$3 - before.$3;
  final bx = after.$1 - here.$1;
  final bz = after.$3 - here.$3;
  final la = _norm(<double>[ax, az]);
  final lb = _norm(<double>[bx, bz]);
  if (la < 1e-6 || lb < 1e-6) return 0.0;
  final cross = (ax * bz - az * bx) / (la * lb);
  final dot = (ax * bx + az * bz) / (la * lb);
  return math.atan2(cross, dot) / ((la + lb) / 2);
}

List<_Row> _build(_Circuit c, List<_Vec> points) {
  final curves = <double>[
    for (var i = 0; i < points.length; i++) _curvatureAt(points, i),
  ];
  final most = curves.map((double v) => v.abs()).reduce(math.max);
  final sharpest = most == 0.0 ? 1.0 : most;
  return <_Row>[
    for (final (i, (x, y, z)) in points.indexed)
      () {
        final tightness = curves[i].abs() / sharpest;
        return <String, Object?>{
          'at': roundedVector(<double>[x, y, z]),
          // The road closes down through the tight stuff.
          'width': roundDecimal(
            c.widest - (c.widest - c.narrowest) * tightness,
            2,
          ),
          // Tilted into the turn: a left-hand corner — positive curvature —
          // throws the car right, so the right edge comes up. The wrong way
          // round is a circuit off-camber everywhere, which looks fine.
          'bank': roundDecimal(c.maxBank * tightness * curves[i].sign, 2),
        };
      }(),
  ];
}

/// The chord length round the control points.
double _lapLength(List<_Vec> points) {
  var total = 0.0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    total += _norm(<double>[b.$1 - a.$1, b.$2 - a.$2, b.$3 - a.$3]);
  }
  return total;
}

/// The level around the circuit: ground to land on, whose top sits below the
/// lowest point of the road — a plane at zero would be above it wherever it
/// dips — and a ring of pillars to measure speed against.
List<_Row> _ground(_Circuit c, List<_Vec> points) {
  final reach = _groundReach(c);
  final floor = points.map((_Vec p) => p.$2).reduce(math.min) - 1.5;
  const thickness = 4.0;
  final radius = _pillarRadius(c);
  return <_Row>[
    <String, Object?>{
      'at': <double>[0.0, roundDecimal(floor - thickness / 2, 3), 0.0],
      'size': <double>[reach * 2, thickness, reach * 2],
      'material': 'grass',
      'surface': 'grass',
    },
    for (var i = 0; i < 24; i++)
      () {
        final angle = 2 * math.pi * i / 24;
        return <String, Object?>{
          'at': roundedVector(<double>[
            radius * math.cos(angle),
            floor + 6.0,
            radius * math.sin(angle),
          ]),
          'size': const <double>[4.0, 12.0, 4.0],
          'material': 'stone',
        };
      }(),
  ];
}

/// Flat colours rather than texture maps: a circuit that has not been
/// dressed yet should still load.
const Map<String, _Row> _materials = <String, _Row>{
  'grass': <String, Object?>{
    'baseColor': <double>[0.18, 0.3, 0.14, 1.0],
    'roughness': 1.0,
  },
  'stone': <String, Object?>{
    'baseColor': <double>[0.45, 0.44, 0.42, 1.0],
    'roughness': 0.9,
  },
};

// MARK: - The sky

/// One preset decides the sun, the gradient, the haze and the exposure, and
/// everything else about the light is derived from it here, so the four places
/// the atmosphere used to be written cannot disagree.
///
/// These are `SkyPresets` in `flutter3d_game_racing`, and `frame_test.dart`
/// compares the block written into each track with the Dart constant of the
/// same name, so the copy cannot drift without a test saying so.
const Map<String, _Row> _skyPresets = <String, _Row>{
  'dawn': <String, Object?>{
    'name': 'dawn',
    'sunElevationDeg': 4.0,
    'sunAzimuthDeg': 95.0,
    'sunColor': <double>[1.0, 0.62, 0.38],
    'sunIntensity': 2.1,
    'zenith': <double>[0.16, 0.24, 0.42],
    'horizon': <double>[0.72, 0.52, 0.44],
    'belowHorizon': <double>[0.16, 0.15, 0.17],
    'glowWide': 5.0,
    'glowStrength': 0.55,
    'fogDensity': 0.006,
    'fogBacklitExponent': 5.0,
    'fogBacklitStrength': 0.45,
    'ambientIntensity': 0.08,
    'exposure': 1.85,
    'sunDisc': 26.0,
  },
  'morning': <String, Object?>{
    'name': 'morning',
    'sunElevationDeg': 34.0,
    'sunAzimuthDeg': 112.0,
    'sunColor': <double>[1.0, 0.95, 0.86],
    'sunIntensity': 3.1,
    'zenith': <double>[0.26, 0.42, 0.72],
    'horizon': <double>[0.66, 0.75, 0.85],
    'belowHorizon': <double>[0.2, 0.21, 0.22],
    'glowWide': 6.0,
    'glowStrength': 0.3,
    'fogDensity': 0.0042,
    'fogBacklitExponent': 6.0,
    'fogBacklitStrength': 0.35,
    'ambientIntensity': 0.1,
    'exposure': 1.6,
    'sunDisc': 14.0,
  },
  'noon': <String, Object?>{
    'name': 'noon',
    'sunElevationDeg': 78.0,
    'sunAzimuthDeg': 150.0,
    'sunColor': <double>[1.0, 0.99, 0.96],
    'sunIntensity': 3.6,
    'zenith': <double>[0.2, 0.38, 0.76],
    'horizon': <double>[0.62, 0.72, 0.86],
    'belowHorizon': <double>[0.22, 0.23, 0.24],
    'glowWide': 8.0,
    'glowStrength': 0.18,
    'fogDensity': 0.003,
    'fogBacklitExponent': 8.0,
    'fogBacklitStrength': 0.22,
    'ambientIntensity': 0.12,
    'exposure': 1.45,
    'sunDisc': 9.0,
  },
  'golden': <String, Object?>{
    'name': 'golden',
    'sunElevationDeg': 11.0,
    'sunAzimuthDeg': 285.0,
    'sunColor': <double>[1.0, 0.78, 0.52],
    'sunIntensity': 2.6,
    'zenith': <double>[0.22, 0.34, 0.6],
    'horizon': <double>[0.86, 0.62, 0.4],
    'belowHorizon': <double>[0.2, 0.17, 0.15],
    'glowWide': 4.5,
    'glowStrength': 0.7,
    'fogDensity': 0.005,
    'fogBacklitExponent': 4.5,
    'fogBacklitStrength': 0.6,
    'ambientIntensity': 0.09,
    'exposure': 1.75,
    'sunDisc': 34.0,
  },
  'dusk': <String, Object?>{
    'name': 'dusk',
    'sunElevationDeg': -2.0,
    'sunAzimuthDeg': 292.0,
    'sunColor': <double>[0.72, 0.6, 0.66],
    'sunIntensity': 1.2,
    'zenith': <double>[0.1, 0.14, 0.3],
    'horizon': <double>[0.44, 0.38, 0.48],
    'belowHorizon': <double>[0.09, 0.09, 0.12],
    'glowWide': 4.0,
    'glowStrength': 0.4,
    'fogDensity': 0.0075,
    'fogBacklitExponent': 4.0,
    'fogBacklitStrength': 0.3,
    'ambientIntensity': 0.14,
    'exposure': 2.05,
    'sunDisc': 0.0,
  },
};

/// How much of the far edge of the ground may still show through the haze:
/// `exp(-density * reach)` of it survives.
const double _groundFade = 0.12;

/// And the ground is not free at any size — the last shadow cascade is
/// fitted to the scene — so clear air does not get a kilometre.
const double _groundMin = 300.0;
const double _groundMax = 700.0;

double _number(_Row preset, String key) => (preset[key]! as num).toDouble();

List<double> _colour(_Row preset, String key) =>
    (preset[key]! as List<Object?>).cast<double>();

/// A unit vector pointing up at the sun. Mirrors `SkyPreset.directionToSun`.
_Vec _directionToSun(_Row preset) {
  final elevation = _radians(_number(preset, 'sunElevationDeg'));
  final azimuth = _radians(_number(preset, 'sunAzimuthDeg'));
  final flat = math.cos(elevation);
  return (
    flat * math.sin(azimuth),
    math.sin(elevation),
    flat * math.cos(azimuth),
  );
}

double _radians(double degrees) => degrees * (math.pi / 180.0);

/// The sky in [direction]. Mirrors `SkyPreset.colourAt`.
_Vec _skyColourAt(_Row preset, _Vec direction) {
  final horizon = _colour(preset, 'horizon');
  final length = _norm(_list(direction));
  if (length <= 0.0) return (horizon[0], horizon[1], horizon[2]);
  final y = math.max(-1.0, math.min(1.0, direction.$2 / length));
  final other = _colour(preset, y >= 0.0 ? 'zenith' : 'belowHorizon');
  final a = y.abs();
  final t = a * a * (3.0 - 2.0 * a);
  final base = <double>[
    for (var i = 0; i < 3; i++) horizon[i] + (other[i] - horizon[i]) * t,
  ];
  final toSun = _directionToSun(preset);
  final d = _list(direction);
  final s = _list(toSun);
  final towards = (d[0] * s[0] + d[1] * s[1] + d[2] * s[2]) / length;
  if (towards <= 0.0) return (base[0], base[1], base[2]);
  final lobe =
      _number(preset, 'glowStrength') *
      math.pow(towards, _number(preset, 'glowWide'));
  final sun = _colour(preset, 'sunColor');
  return (
    base[0] + sun[0] * lobe,
    base[1] + sun[1] * lobe,
    base[2] + sun[2] * lobe,
  );
}

/// What distance settles to: the sky at the horizon, across the sun.
/// **Deliberately not a field anybody sets**, so the haze and the sky cannot
/// be authored apart. Mirrors `SkyPreset.horizonFogColour`.
_Vec _horizonFogColour(_Row preset) {
  final toSun = _directionToSun(preset);
  final across = (toSun.$3, 0.0, -toSun.$1);
  final length = _norm(_list(across));
  final unit = length < 1e-5
      ? (1.0, 0.0, 0.0)
      : (across.$1 / length, across.$2 / length, across.$3 / length);
  return _skyColourAt(preset, unit);
}

/// Half the width of the ground, in metres, sized by the haze.
double _groundReach(_Circuit c) {
  final density = _number(_skyPresets[c.preset]!, 'fogDensity');
  final reach = math.log(1.0 / _groundFade) / density;
  return roundDecimal(math.max(_groundMin, math.min(_groundMax, reach)), 1);
}

/// Where the pillars stand: well outside the road, and inside the ground.
double _pillarRadius(_Circuit c) => math.min(
  c.baseRadius + c.lobeTwo + c.pillarClearance,
  _groundReach(c) - 30.0,
);

/// The one sun, derived from the preset rather than typed out beside it.
List<_Row> _lights(_Row preset) {
  final (x, y, z) = _directionToSun(preset);
  return <_Row>[
    <String, Object?>{
      'type': 'directional',
      // Where the light goes, which is away from where the sun is.
      'direction': roundedVector(<double>[-x, -y, -z]),
      'color': preset['sunColor'],
      'intensity': preset['sunIntensity'],
      'castsShadow': true,
    },
  ];
}

List<double> _list(_Vec v) => <double>[v.$1, v.$2, v.$3];

/// The Euclidean length of [v].
double _norm(List<double> v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  return math.sqrt(sum);
}
