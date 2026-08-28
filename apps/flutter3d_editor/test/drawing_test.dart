/// A document turned into something to look at.
///
///     flutter test test/drawing_test.dart
///
/// **The one thing this application does that a unit test cannot reach**, done
/// without a window. `LevelLoader.build` is new — the loader used to read the
/// asset and build the scene in one method, so a level had to be a bundled
/// file to be drawn at all, and an editor holds a document it has just changed
/// and has no asset to point at.
library;

import 'dart:convert';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_editor/src/editing.dart';
import 'package:flutter3d_editor/src/gizmos.dart';
import 'package:flutter3d_editor/src/vocabulary.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Small on purpose: what is being tested is the chain, and the chain runs at
/// any size.
GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 9,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

String _document() => jsonEncode(<String, Object?>{
  'version': 1,
  'name': 'test',
  'materials': <String, Object?>{
    'stone': <String, Object?>{
      'baseColor': <double>[0.5, 0.5, 0.5, 1.0],
    },
  },
  'brushes': <Object?>[
    <String, Object?>{
      'at': <double>[0.0, 0.0, 0.0],
      'size': <double>[8.0, 1.0, 8.0],
      'material': 'stone',
    },
  ],
  'entities': <Object?>[
    // A word this editor has never heard of, which is the point of
    // `vocabularyOf`: the game decides what a `wumpus` is worth, and an
    // editor that refused to open a level naming one would be an editor
    // that can only edit the games it was written beside.
    <String, Object?>{
      'type': 'wumpus',
      'at': <double>[1.0, 1.0, 1.0],
    },
  ],
});

void main() {
  test('a document in memory becomes a scene', () async {
    final editing = Editing.parse(_document(), path: '/levels/test.json');

    final loaded = await LevelLoader().build(
      editing.level,
      device: _device(),
      registry: vocabularyOf(editing.level),
    );

    expect(
      loaded.scene.root.children,
      isNotEmpty,
      reason: 'a level with a brush in it drew nothing',
    );
    expect(loaded.drawCallCount, greaterThan(0));
  });

  test('and a document this editor has just changed becomes a new one', () {
    // The loop the whole application is: change the document, draw the
    // document. Nothing is patched, because a brush is batched into its
    // material's mesh and there is nothing smaller to rebuild — and an editor
    // whose picture and document disagree is the one thing it must never be.
    final editing = Editing.parse(_document(), path: '/levels/test.json')
      ..select(Piece.brush, 0);

    editing.nudge(Vector3(0.0, 4.0, 0.0));

    expect(editing.level.brushes[0].centre.y, 4.0);
    expect(
      () async => LevelLoader().build(
        editing.level,
        device: _device(),
        registry: vocabularyOf(editing.level),
      ),
      returnsNormally,
    );
  });

  test('and an entity nobody here can vouch for is not an error', () {
    final editing = Editing.parse(_document(), path: '/levels/test.json');

    final registry = vocabularyOf(editing.level);

    expect(registry.knows('wumpus'), isTrue);
    expect(
      editing
          .issuesFor(registry)
          .where((LevelIssue it) => it.message.contains('wumpus')),
      isEmpty,
    );
  });
}
