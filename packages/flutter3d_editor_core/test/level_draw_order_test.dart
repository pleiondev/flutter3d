/// A brush's draw order through the editor — `P7`.
///
///     dart test test/level_draw_order_test.dart
///
/// The level document says where a brush draws among others of its bucket;
/// these hold that the scene the editor builds draws it there, that a copy
/// keeps it, and that the inspector offers it on a brush that has never said.
library;

import 'dart:convert';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

Map<String, Object?> _document() => <String, Object?>{
  'brushes': <Object?>[
    <String, Object?>{
      'at': <double>[0.0, 0.0, 0.0],
      'size': <double>[4.0, 1.0, 4.0],
      'material': 'stone',
    },
    <String, Object?>{
      'at': <double>[0.0, 0.6, 0.0],
      'size': <double>[4.0, 0.1, 4.0],
      'material': 'stone',
      'drawOrder': 1,
    },
  ],
};

void main() {
  test('each batch is drawn at its brushes\' place in the order', () {
    // Mutation: drop `..drawOrder = surface.drawOrder` from
    // `LevelScene._batchOf` — both batches draw at nought, and which of the
    // two lands on top is the sort's to decide.
    final level = Level.fromJson(_document());
    final batches = const LevelScene().brushBatches(
      level,
      device: CpuDevice(
        width: 4,
        height: 4,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      ),
    );
    expect(batches, hasLength(2));
    expect(batches.map((LevelBatch it) => it.node.drawOrder).toSet(), <int>{
      0,
      1,
    });
  });

  test('a copy keeps the order of the brush it copied', () {
    // Mutation: leave `drawOrder` out of the brush `Editing.duplicate` builds.
    final editing = Editing.parse(
      jsonEncode(_document()),
      path: '/levels/order.json',
    )..select(Piece.brush, 1);
    editing.duplicate();
    expect(editing.brush!.drawOrder, 1);
  });

  test('the inspector offers it on a brush that has never said', () {
    final editing = Editing.parse(
      jsonEncode(_document()),
      path: '/levels/order.json',
    )..select(Piece.brush, 0);
    expect(editing.offerable, containsPair('drawOrder', 0));
    expect(editing.setField('drawOrder', 2), isTrue);
    expect(editing.brush!.drawOrder, 2);
  });
}
