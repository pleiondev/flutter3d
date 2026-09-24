/// The map the strategy game is played on.
///
/// **Edit this, not the JSON.** A map is a hillside, two camps, the seams they
/// dig and the line that ends the match, and those numbers have to agree with
/// each other — a camp off the edge of the field, a seam nobody can reach, a
/// finishing line no seam holds enough ore to pay for. Eighty-one squared
/// heights edited by hand is one of those introduced and not noticed.
///
/// The map is a `Level` rather than a format of this genre's own: a
/// heightfield for the ground and entities for everything standing on it.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// How many samples across the field, and how far apart: a hundred and sixty
/// metres of hillside, about as far as this camera sees and as much ground as
/// a crowd of a hundred can fill.
const int _samples = 81;
const double _cell = 2.0;

/// How many camps play. Which one the mouse commands is the application's
/// business; the document only says where they stand.
const int _sides = 2;

/// What each camp opens with, ten across at eleven-tenths of a metre so
/// nobody starts inside anybody.
const int _workers = 60;
const int _across = 10;
const double _spacing = 1.1;

/// What a seam holds against how much a side must bring home: a side that
/// digs its own seam out still has to have done it faster than the other.
const double _seam = 1600.0;
const double _goal = 1200.0;

/// `map_a.json`.
Map<String, String> map(GeneratorSource _) {
  final field = _heights();
  final document = <String, Object?>{
    'version': 1,
    'name': 'Map A',
    'generatedBy': 'tool/make_map.py',
    // Where the match ends: not an entity, because it is not anywhere. The
    // format carries a section it does not know rather than losing it.
    'goal': <String, Object?>{'delivered': _goal},
    // Written although it is the fallback, because `Level` writes it on every
    // save and a document without it changes the first time it is opened.
    'fogColor': const <double>[0.05, 0.04, 0.06],
    'materials': const <String, Object?>{
      'rock': <String, Object?>{
        'baseColor': <double>[0.31, 0.29, 0.26, 1.0],
        'roughness': 0.95,
      },
    },
    'brushes': <Object?>[_bedrock(field)],
    // The sun the game already draws, so anything else opening this document
    // lights it the same way.
    'lights': <Object?>[
      <String, Object?>{
        'type': 'directional',
        'direction': roundedVector(const <double>[0.35, -1.0, 0.5]),
        'color': const <double>[1.0, 0.96, 0.88],
        'intensity': 3.2,
        'name': 'sun',
      },
    ],
    'entities': _entities(field),
    // Last, because it is thirty-five thousand characters of base64.
    'heightfield': <String, Object?>{
      'columns': _samples,
      'rows': _samples,
      'cellSize': _cell,
      'heights': _packed(field),
    },
  };
  return <String, String>{
    'apps/flutter3d_demo_strategy/assets/levels/map_a.json':
        '${DocumentText.compact(document)}\n',
  };
}

/// The ground: two ridges and a valley between them, **quantised to the
/// centimetre**, which is what makes the file the same on every machine — a
/// sine is libm's, and two machines agreeing to the last bit is a courtesy.
/// The steepest slope is about twenty-five degrees, under the forty the
/// navigation bake refuses.
List<double> _heights() => <double>[
  for (var row = 0; row < _samples; row++)
    for (var column = 0; column < _samples; column++)
      () {
        final x = column / (_samples - 1);
        final z = row / (_samples - 1);
        return roundDecimal(
          math.sin(x * math.pi * 2.0) * 9.0 +
              math.sin(z * math.pi * 3.0 + 1.0) * 6.0 +
              math.sin((x + z) * math.pi * 5.0) * 1.5 +
              14.0,
          2,
        );
      }(),
];

/// The ground under a world position that sits on a sample — looked up, not
/// interpolated, and refused anywhere else: a camp written half a metre off
/// its sample would load at a height the game then corrects.
double _heightAt(List<double> field, (double, double) at) {
  final (x, z) = at;
  if (x % _cell != 0 || z % _cell != 0) {
    throw GeneratorRefused(
      '($x, $z) is not on a sample, and this map places nothing between them',
    );
  }
  return field[(z ~/ _cell) * _samples + (x ~/ _cell)];
}

/// The heights as the document carries them: base64 of little-endian f32,
/// which is what `Heightfield.fromJson` views them as on every target this
/// repository builds for.
String _packed(List<double> field) {
  final bytes = ByteData(field.length * 4);
  for (final (i, h) in field.indexed) {
    bytes.setFloat32(i * 4, h, Endian.little);
  }
  return base64.encode(bytes.buffer.asUint8List());
}

/// Everything standing on the ground, in the order a side is assembled. The
/// names are how the pieces find each other: a producer names its hall, a
/// block of workers the seam it digs and the hall it carries to.
List<Map<String, Object?>> _entities(List<double> field) {
  List<double> on((double, double) p) =>
      roundedVector(<double>[p.$1, _heightAt(field, p), p.$2]);

  return <Map<String, Object?>>[
    for (var side = 0; side < _sides; side++)
      ...() {
        // Spread along the hillside's diagonal. Not mirrored: fair enough for
        // a demo; the tests that care use flat ground.
        final along = _sides == 1 ? 0.0 : side / (_sides - 1);
        final home = (36.0 + along * 88.0, 36.0 + along * 88.0);
        // The seam sits thirty-six metres from the hall towards the middle.
        const depth = (_samples - 1) * _cell;
        final seam = (
          home.$1,
          home.$2 + (home.$2 < depth / 2.0 ? 36.0 : -36.0),
        );
        final hall = side == 0 ? 'hall' : 'their hall';
        final deposit = side == 0 ? 'seam' : 'their seam';
        final block = (home.$1 - 12.0, home.$2 + 8.0);
        return <Map<String, Object?>>[
          <String, Object?>{
            'type': 'camp',
            'at': on(home),
            'name': hall,
            'side': side,
            'width': 12.0,
            'depth': 10.0,
          },
          <String, Object?>{
            'type': 'resource_node',
            'at': on(seam),
            'name': deposit,
            'amount': _seam,
          },
          // Written with its price and pace: the economy is the match, and
          // the document is where somebody tuning it looks first.
          <String, Object?>{
            'type': 'producer',
            'at': on(home),
            'target': hall,
            'cost': 25.0,
            'seconds': 4.0,
          },
          // The purse, which opens empty.
          <String, Object?>{
            'type': 'stockpile',
            'at': on(home),
            'side': side,
            'amount': 0.0,
          },
          // One entity for the block rather than sixty.
          <String, Object?>{
            'type': 'worker',
            'at': on(block),
            'side': side,
            'count': _workers,
            'across': _across,
            'spacing': _spacing,
            'digs': deposit,
            'home': hall,
          },
        ];
      }(),
  ];
}

/// The block the hillside is cut from: the field is the surface, and this is
/// what the format calls geometry. Its top is the lowest sample, so a body
/// that fell through the surface meets it.
Map<String, Object?> _bedrock(List<double> field) {
  const reach = (_samples - 1) * _cell;
  final floor = field.reduce(math.min);
  return <String, Object?>{
    'at': <double>[reach / 2.0, roundDecimal(floor - 2.0, 2), reach / 2.0],
    'size': const <double>[reach, 4.0, reach],
    'material': 'rock',
  };
}
