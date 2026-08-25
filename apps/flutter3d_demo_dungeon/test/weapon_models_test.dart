/// What the player is holding, checked against the files that ship.
///
///     flutter test test/weapon_models_test.dart
///
/// **The weapons were procedural blocks and the file said so.** Two of them are
/// models now, and the interesting half is not the mesh: a view model has to
/// point away from the player and be about the size of the blocks it replaced,
/// because the rest position, the bob and the recoil in `WeaponView` are all
/// tuned against that. Neither is visible in a test that only checks the file
/// exists — you have to read the geometry.
///
/// Read from the GLB directly rather than through the engine, which would need
/// a graphics device to upload meshes this test never draws. The same trick
/// `monster_looks_test.dart` uses, and for the same reason.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_demo_dungeon/src/weapon_models.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';

/// The JSON chunk of a GLB.
Map<String, Object?> _documentIn(String path) {
  final bytes = File(path).readAsBytesSync();
  final view = ByteData.sublistView(bytes);
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'glTF',
      reason: '$path is not a GLB');
  final length = view.getUint32(12, Endian.little);
  return jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)))
      as Map<String, Object?>;
}

/// The model's extent along each axis, walking the node hierarchy.
///
/// Only scale and the single quarter-turn `fetch_weapons.py` bakes are ever
/// present here, so a full matrix chain would be four times the code to reach
/// the same three numbers. A rotation about Y swaps X and Z; that is handled,
/// and anything else would be a file this test should fail on anyway.
({List<double> low, List<double> high}) _boundsOf(Map<String, Object?> document) {
  final nodes = (document['nodes']! as List).cast<Map<String, Object?>>();
  final meshes = (document['meshes']! as List).cast<Map<String, Object?>>();
  final accessors =
      (document['accessors']! as List).cast<Map<String, Object?>>();
  final scenes = (document['scenes']! as List).cast<Map<String, Object?>>();

  final low = <double>[1e9, 1e9, 1e9];
  final high = <double>[-1e9, -1e9, -1e9];

  void walk(int index, List<double> scale, bool turned) {
    final node = nodes[index];
    final own = (node['scale'] as List?)?.cast<num>() ?? const <num>[1, 1, 1];
    final next = <double>[
      for (var axis = 0; axis < 3; axis++) scale[axis] * own[axis].toDouble(),
    ];
    // The bake writes exactly one rotation, a quarter turn about Y, as
    // (0, sin45, 0, cos45). Anything with a non-zero y term is that turn.
    final spin = (node['rotation'] as List?)?.cast<num>();
    final spun = turned ^ (spin != null && spin[1].abs() > 1e-6);

    if (node['mesh'] != null) {
      for (final prim
          in (meshes[node['mesh']! as int]['primitives']! as List)
              .cast<Map<String, Object?>>()) {
        final attributes = prim['attributes']! as Map<String, Object?>;
        final accessor = accessors[attributes['POSITION']! as int];
        final min = (accessor['min']! as List).cast<num>();
        final max = (accessor['max']! as List).cast<num>();
        for (var axis = 0; axis < 3; axis++) {
          // A quarter turn about Y sends (x, y, z) to (z, y, -x): the new X
          // takes the old Z as it is, and the new Z takes the old X *negated*.
          // Leaving that sign out mirrors the model front to back, which is
          // exactly how this test first read a correctly turned pistol as
          // pointing backwards.
          final from = spun && axis != 1 ? 2 - axis : axis;
          final sign = spun && axis == 2 ? -1.0 : 1.0;
          final a = min[from].toDouble() * next[from] * sign;
          final b = max[from].toDouble() * next[from] * sign;
          low[axis] = low[axis] < a ? low[axis] : (a < b ? a : b);
          high[axis] = high[axis] > b ? high[axis] : (a > b ? a : b);
        }
      }
    }
    for (final child in (node['children'] as List?)?.cast<int>() ??
        const <int>[]) {
      walk(child, next, spun);
    }
  }

  for (final root in (scenes.first['nodes']! as List).cast<int>()) {
    walk(root, <double>[1.0, 1.0, 1.0], false);
  }
  return (low: low, high: high);
}

void main() {
  group('every weapon model that ships', () {
    test('is on disk under the name the game asks for', () {
      // Mutation: rename one file — fails here, rather than at load with a
      // weapon silently staying blocks and nobody noticing until they hold it.
      expect(kWeaponModels, isNotEmpty);
      for (final path in kWeaponModels.values) {
        expect(File(path).existsSync(), isTrue, reason: '$path is missing');
      }
    });

    test('and names a weapon that exists', () {
      // A key nothing matches is a model that loads and is never shown.
      final known = <String>{
        Weapons.fists.name,
        Weapons.pistol.name,
        Weapons.shotgun.name,
        Weapons.rocketLauncher.name,
      };
      for (final name in kWeaponModels.keys) {
        expect(known, contains(name));
      }
    });

    test('and carries its own provenance', () {
      // LICENSES.md can be separated from the file by a copy; this cannot.
      // Mutation: drop the `stamp` call in fetch_weapons.py — fails.
      for (final path in kWeaponModels.values) {
        final asset = _documentIn(path)['asset']! as Map<String, Object?>;
        final extras = asset['extras'];
        expect(extras, isA<Map<String, Object?>>(), reason: path);
        final fields = extras! as Map<String, Object?>;
        expect(fields['author'], contains('Quaternius'), reason: path);
        expect(fields['license'], contains('CC0'), reason: path);
        expect(fields['source'], contains('poly.pizza'), reason: path);
      }
    });

    test('and points away from the player', () {
      // The barrel has to run down -Z: the view-model camera looks that way,
      // and both of these are modelled down +X. Mutation: drop the quarter
      // turn in fetch_weapons.py — the long axis comes out X and this fails.
      for (final path in kWeaponModels.values) {
        final bounds = _boundsOf(_documentIn(path));
        final size = <double>[
          for (var axis = 0; axis < 3; axis++)
            bounds.high[axis] - bounds.low[axis],
        ];
        expect(size[2], greaterThan(size[0]),
            reason: '$path is wider than it is long');
        expect(size[2], greaterThan(size[1]),
            reason: '$path is taller than it is long');
        // More of it in front of the origin than behind: a weapon whose barrel
        // ran the other way would satisfy the two above and be back to front.
        expect(bounds.low[2].abs(), greaterThan(bounds.high[2].abs()),
            reason: '$path points backwards');
      }
    });

    test('and is a colour a torch can find', () {
      // **Both arrived black**, for the two reasons written above `_metal` in
      // `weapon_models.dart`. A metal surface reflects its surroundings and has
      // almost no diffuse response, and this channel has no image-based
      // lighting to reflect — so metallic renders very nearly black. On top of
      // that the base colours were darker again than the blocks: the pistol's
      // lightest material was 0.0998 against the blocks' 0.30.
      //
      // Mutation: drop `relight` from fetch_weapons.py — fails on both counts,
      // and note glTF's default `metallicFactor` is 1.0, so a material that
      // says nothing at all is fully metallic and therefore black.
      for (final path in kWeaponModels.values) {
        final document = _documentIn(path);
        final materials =
            (document['materials']! as List).cast<Map<String, Object?>>();
        expect(materials, isNotEmpty, reason: path);

        var lightest = 0.0;
        for (final material in materials) {
          final pbr = material['pbrMetallicRoughness'];
          expect(pbr, isA<Map<String, Object?>>(), reason: path);
          final pbrMap = pbr! as Map<String, Object?>;
          expect(pbrMap['metallicFactor'], 0.0,
              reason: '$path has a metallic material and will render black');
          final colour = (pbrMap['baseColorFactor']! as List).cast<num>();
          for (final channel in colour.take(3)) {
            lightest =
                channel.toDouble() > lightest ? channel.toDouble() : lightest;
          }
        }
        // The value the blocks used for gunmetal. Not brighter either: a
        // weapon lighter than the walls it is carried past reads as plastic.
        expect(lightest, closeTo(0.30, 1e-6), reason: path);
      }
    });

    test('and is the size of a thing a person holds', () {
      // Tuned against `WeaponView`'s rest position at 0.78 m from the eye. A
      // weapon much longer than this is a barrel across the whole screen, and
      // one much shorter is a dot in the corner. Mutation: drop the scale bake
      // — the pistol arrives at 1.8 and this fails.
      for (final path in kWeaponModels.values) {
        final bounds = _boundsOf(_documentIn(path));
        final length = bounds.high[2] - bounds.low[2];
        expect(length, greaterThan(0.15), reason: '$path is tiny');
        expect(length, lessThan(0.9), reason: '$path is enormous');
      }
    });
  });
}
