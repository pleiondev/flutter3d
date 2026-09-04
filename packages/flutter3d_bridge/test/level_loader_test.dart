/// Building a level into a scene, and saying what would not build.
///
///     flutter test test/level_loader_test.dart
///
/// **The first test this package ever had.** A thousand lines binding the two
/// halves of the engine, and the only file under `test/` was the rule that it
/// names no genre. What made it testable was already here: `build` takes a
/// `Level` rather than an asset path, and `readAsset` is an argument — both
/// added for the editor, both exactly what a test wants.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The document a level with one wall, in one material, parses from.
Map<String, Object?> _levelJson({String? albedo}) => <String, Object?>{
  'version': 1,
  'materials': <String, Object?>{
    'wall': <String, Object?>{
      'albedo': ?albedo,
      'color': <double>[0.8, 0.8, 0.8],
    },
  },
  'brushes': <Object?>[
    <String, Object?>{
      'material': 'wall',
      'at': <double>[0.0, 1.5, -1.5],
      'size': <double>[4.0, 3.0, 1.0],
    },
  ],
  // A level with no lights is a level the validator warns about, and this
  // file is about the other warnings.
  'lights': <Object?>[
    <String, Object?>{
      'type': 'point',
      'at': <double>[0.0, 2.0, 0.0],
      'color': <double>[1.0, 1.0, 1.0],
      'range': 8.0,
    },
  ],
};

/// A level with one wall, in one material.
Level _level({String? albedo}) => Level.fromJson(_levelJson(albedo: albedo));

void main() {
  final device = CpuDevice(
    width: 16,
    height: 16,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final registry = EntityRegistry(<EntityKind>[]);

  test('a level with no textures builds with nothing to report', () async {
    final loaded = await const LevelLoader().build(
      _level(),
      device: device,
      registry: registry,
    );

    expect(loaded.issues, isEmpty);
    expect(
      loaded.drawCallCount,
      greaterThan(0),
      reason: 'the one brush did not become geometry',
    );
  });

  test(
    'and a texture that will not load is a warning, not a console line',
    () async {
      // **It printed and returned null.** The level plays and the wall is flat,
      // which is right — but a flat wall and a wall meant to be flat look the
      // same, and the difference is a file somebody renamed. `LoadedLevel` has
      // carried `issues` since the validator did; this is the same kind of fact.
      final loaded = await const LevelLoader().build(
        _level(albedo: 'assets/textures/gone.png'),
        device: device,
        registry: registry,
        readAsset: (AssetRequest request) async =>
            throw StateError('no such asset'),
      );

      expect(loaded.issues, hasLength(1));
      expect(
        loaded.issues.single.isError,
        isFalse,
        reason: 'a missing texture stopped the level',
      );
      expect(loaded.issues.single.where, contains('gone.png'));
    },
  );

  test('and a texture that loads is not reported', () async {
    final loaded = await const LevelLoader().build(
      _level(albedo: 'assets/textures/wall.png'),
      device: device,
      registry: registry,
      readAsset: (AssetRequest request) async => _onePixelPng(),
    );

    expect(
      loaded.issues,
      isEmpty,
      reason: 'a texture that loaded was reported as missing',
    );
    expect(loaded.materialTextures['assets/textures/wall.png'], isNotNull);
  });

  test(
    'load reads its document through readDocument, not just its textures',
    () async {
      // The editor's whole reason to want this: a level on disk, read the same
      // way `readAsset` already lets its textures be. Nothing here touches the
      // asset bundle, so a real one is never needed to prove it.
      final read = <String>[];
      final loaded = await const LevelLoader().load(
        'levels/wall.level.json',
        device: device,
        registry: registry,
        readDocument: (AssetRequest request) async {
          final path = request.uri;
          read.add(path);
          // Only the document is there; a reader that answered every path
          // with it would hand the loader a level where it expects a
          // visibility table.
          if (path != 'levels/wall.level.json') {
            throw StateError('no such document: $path');
          }
          return jsonEncode(_levelJson());
        },
      );

      // The document, and then the visibility table that may sit beside it.
      // The second read failing is a level without a table, which is every
      // level that has not been baked, and is not an issue.
      expect(read, <String>[
        'levels/wall.level.json',
        'levels/wall.level.visibility.json',
      ]);
      expect(loaded.issues, isEmpty);
      expect(loaded.drawCallCount, greaterThan(0));
    },
  );

  group('a lightmap', () {
    test('goes onto every brush batch as a second coordinate', () async {
      final level = _level();
      final map = const LightmapBaker(
        texelsPerMetre: 1.0,
        bounces: 0,
        includeDirect: true,
      ).bake(level);

      final loaded = await const LevelLoader().build(
        level,
        device: device,
        registry: registry,
        lightmap: map,
      );

      expect(loaded.issues, isEmpty);
      expect(loaded.lightmap, isNotNull);
      expect(loaded.brushNodes, isNotEmpty);
      for (final node in loaded.brushNodes) {
        expect(node.lightmapped, isTrue);
        expect(node.material.lightmap, same(loaded.lightmap));
      }
    });

    test('baked from other walls is refused with a word', () async {
      final level = _level();
      final map = Lightmap(
        width: 64,
        height: 64,
        texelsPerMetre: 1.0,
        levelHash: 0,
      );

      final loaded = await const LevelLoader().build(
        level,
        device: device,
        registry: registry,
        lightmap: map,
      );

      expect(loaded.lightmap, isNull);
      expect(loaded.issues, hasLength(1));
      expect(loaded.issues.single.message, contains('bake_lightmap'));
      expect(loaded.brushNodes.every((n) => !n.lightmapped), isTrue);
    });

    // The hash says the level is the level the bake read. It cannot say that
    // this build packs that level's faces where the baking build packed
    // them, and a map whose atlas is a different size is proof they do not:
    // every face would sample somebody else's texels. So the size is
    // compared too. Mutation: dropping the `layout.width != lightmap.width`
    // check in `LevelLoader.build` binds the map anyway, and both the
    // `isNull` and the issue expectations report false.
    test('the size of which disagrees with the plan is refused too', () async {
      final level = _level();
      final baked = const LightmapBaker(
        texelsPerMetre: 1.0,
        bounces: 0,
      ).bake(level);
      // Fresh by the hash — same level, same lights — and half the atlas the
      // planner asks for, which is what a changed packer would look like.
      final wrongSize = Lightmap(
        width: baked.width ~/ 2,
        height: baked.height,
        texelsPerMetre: baked.texelsPerMetre,
        levelHash: baked.levelHash,
      );
      expect(wrongSize.isStaleFor(level), isFalse, reason: 'the hash agrees');

      final loaded = await const LevelLoader().build(
        level,
        device: device,
        registry: registry,
        lightmap: wrongSize,
      );

      expect(loaded.lightmap, isNull);
      expect(loaded.issues.single.message, contains('this build plans'));
      expect(loaded.brushNodes.every((n) => !n.lightmapped), isTrue);
    });

    test('is looked for beside the document', () async {
      final asked = <String>[];
      final loaded = await const LevelLoader().load(
        'levels/wall.level.json',
        device: device,
        registry: registry,
        readDocument: (AssetRequest request) async {
          final path = request.uri;
          if (path != 'levels/wall.level.json') {
            throw StateError('no such document: $path');
          }
          return jsonEncode(_levelJson());
        },
        readAsset: (AssetRequest request) async {
          final path = request.uri;
          asked.add(path);
          throw StateError('no such asset: $path');
        },
      );

      expect(asked, contains('levels/wall.level.lightmap.bin'));
      expect(loaded.lightmap, isNull);
      expect(loaded.issues, isEmpty, reason: 'a missing map is not an issue');
    });
  });

  group('a breach', () {
    Future<(LoadedLevel, Breaches)> breached() async {
      final level = _twoWalls();
      final loaded = await const LevelLoader().build(
        level,
        device: device,
        registry: registry,
        lightmap: const LightmapBaker(
          texelsPerMetre: 1.0,
          bounces: 0,
          includeDirect: true,
        ).bake(level),
      );
      expect(loaded.lightmap, isNotNull, reason: 'the level loaded lit');

      final world = CollisionWorld();
      level.addTo(world);
      return (
        loaded,
        Breaches(level, world)
          ..hole(Aabb3.minMax(Vector3(5.0, 1.0, -3.0), Vector3(7.0, 3.0, 1.0))),
      );
    }

    test('keeps the baked light on the walls it did not touch', () async {
      // The decision this was written for. Before it, one rocket into one wall
      // dropped the atlas from the whole level — in the crypt, the light in
      // every room changing because a corridor lost a metre of stone.
      //
      // That the pieces read the *right* texels is `flutter3d_sim`'s
      // `breached_lightmap_test.dart`; what is held here is that the atlas
      // reaches the rebuild at all.
      //
      // Mutation: stop keeping the plan — `..lightmapLayout = null` at the
      // foot of `build`. Every batch comes back unlightmapped and the level
      // goes flat on the first rocket.
      final (loaded, breaches) = await breached();
      final atlas = loaded.lightmap;

      const LevelLoader().rebuildBrushes(
        loaded,
        device: device,
        brushes: breaches.brushes,
        origins: breaches.origins,
      );

      expect(loaded.brushNodes, isNotEmpty);
      for (final node in loaded.brushNodes) {
        expect(node.lightmapped, isTrue);
        expect(node.material.lightmap, same(atlas));
      }
    });

    test(
      'and asks for none when it cannot say where its walls came from',
      () async {
        // The honest fallback, and the reason it is one: a layout is keyed by
        // brush index, so a caller with no origins has no way to tell a piece
        // which face it is part of. Flat is a limit; a face reading somebody
        // else's texels is a bug that looks like light.
        //
        // Mutation: pass `loaded.lightmapLayout` regardless of `origins`.
        final (loaded, breaches) = await breached();

        const LevelLoader().rebuildBrushes(
          loaded,
          device: device,
          brushes: breaches.brushes,
        );

        expect(loaded.brushNodes, isNotEmpty);
        expect(loaded.brushNodes.every((MeshNode n) => !n.lightmapped), isTrue);
      },
    );
  });

  group('the shadow mode a document asks for', () {
    test('reaches the node the batch is drawn through', () async {
      // A crypt's walls are one brush thick and lit from both sides, which is
      // the case `ShadowCastingMode.doubleSided` was written for and the case
      // a level document could not ask for.
      //
      // Mutation: `..castsShadow = surface.castsShadow` on the node again.
      // `doubleSided` reads as true, so the wall loads as an ordinary caster
      // and leaks light along its seam with nothing said.
      final loaded = await const LevelLoader().build(
        Level.fromJson(<String, Object?>{
          ..._levelJson(),
          'brushes': <Object?>[
            <String, Object?>{
              'material': 'wall',
              'at': <double>[0.0, 1.5, -1.5],
              'size': <double>[4.0, 3.0, 1.0],
              'shadowCasting': 'doubleSided',
            },
          ],
        }),
        device: device,
        registry: registry,
      );

      expect(
        loaded.brushNodes.single.shadowCasting,
        ShadowCastingMode.doubleSided,
      );
    });
  });
}

/// Two walls twelve metres apart: one for a blast to cut, one for it to miss.
Level _twoWalls() => Level.fromJson(<String, Object?>{
  ..._levelJson(),
  'brushes': <Object?>[
    <String, Object?>{
      'material': 'wall',
      'at': <double>[6.0, 2.0, -1.0],
      'size': <double>[4.0, 4.0, 1.0],
    },
    <String, Object?>{
      'material': 'wall',
      'at': <double>[-6.0, 2.0, -1.0],
      'size': <double>[4.0, 4.0, 1.0],
    },
  ],
});

/// One opaque white pixel, as a PNG.
///
/// Written out rather than read from a file, because a package's test that
/// reaches into an application's assets is the dependency this package's other
/// test file exists to forbid.
ByteData _onePixelPng() => ByteData.sublistView(
  Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0xF8, 0x0F, 0x04, 0x00,
    0x09, 0xFB, 0x03, 0xFD, 0xFB, 0x5E, 0x6B, 0x2B,
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
    0xAE, 0x42, 0x60, 0x82,
  ]),
);
