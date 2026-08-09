import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'level_scene.dart';

/// What the doors, lifts, platforms, buttons and keys look like.
///
/// The engine reports a [Fixture] — a box, a size, a material name and whatever
/// runs it — and this turns each one into a node and keeps that node where the
/// collider is. It is the whole of the application's side of stage 8, which is
/// the point: the simulation never learns that meshes exist.
final class FixtureVisuals {
  FixtureVisuals(this.scene, this.level);

  final Scene scene;

  /// The loaded level, for its palette and its already-uploaded maps: a door
  /// authored as `stone` should be the same stone as the wall it sits in, down
  /// to sharing the texture object rather than a second copy of the file.
  final LoadedLevel level;

  final List<_Piece> _pieces = <_Piece>[];

  /// Models already read off disk, by asset path.
  ///
  /// Ten torches sharing one model should be one decode and one upload. The
  /// cache is per-level for the same reason the texture cache is: a GPU
  /// resource outliving the level that owns it is a leak nobody notices.
  final Map<String, Future<ModelAsset?>> _models = <String, Future<ModelAsset?>>{};

  /// Whatever the renderer hands out for a material with no albedo of its own.
  ///
  /// Wanted only because the model loader insists on one; every model here has
  /// its material replaced immediately afterwards.
  gpu.Texture? fallbackAlbedo;

  void add(Fixture fixture) {
    final model = fixture.entity.string('model');
    if (model != null) {
      // Asynchronous, and deliberately not awaited: a level with twenty props
      // should not load them one after another, and a key that appears two
      // frames late is a key nobody saw appear.
      unawaited(_addModel(fixture, model));
      return;
    }

    final source = level.level.materials[fixture.material] ??
        _fallbackFor(fixture);
    final node = MeshNode(
      GpuMesh.upload(CuboidShape(size: fixture.size).build()),
      LevelLoader.materialFrom(
        source,
        level.materialTextures,
        name: fixture.material,
      ),
      name: fixture.entity.name ?? fixture.entity.type,
    )..setPositionFrom(fixture.position);
    _tint(node.material, fixture);
    scene.add(node);
    _pieces.add(_Piece(fixture, node));
  }

  /// Multiplies the entity's own tint into the material's base colour.
  ///
  /// This is what lets three keys share one model and one set of maps and
  /// still be a red key, a blue key and an iron one. The tint is a multiplier
  /// rather than a replacement, so the metal keeps its own scratches and
  /// shading — a flat recolour would look like a sticker.
  ///
  /// A material built per fixture rather than shared, because two keys with
  /// different tints cannot be the same Material object; the textures inside
  /// it are still shared, which is where the memory actually is.
  void _tint(engine.Material material, Fixture fixture) {
    final tint = fixture.entity.vector('tint');
    if (tint == null) return;
    material.baseColor.multiply(Vector4(tint.x, tint.y, tint.z, 1.0));
  }

  /// Puts a modelled fixture in the scene once its file has been read.
  Future<void> _addModel(Fixture fixture, String path) async {
    final asset = await _models.putIfAbsent(path, () => _load(path));
    if (asset == null) return;

    final instance = asset.instantiate(scene);

    // The model's own material is replaced by the level's, so a key and the
    // lock it opens are described in one place — the level document — rather
    // than half in the document and half inside a binary somebody exported.
    final source = level.level.materials[fixture.material];
    if (source != null && source.hasMaps) {
      final material = LevelLoader.materialFrom(
        source,
        level.materialTextures,
        name: fixture.material,
      );
      _tint(material, fixture);
      for (final node in instance.nodes) {
        if (node is MeshNode) node.material = material;
      }
    }

    instance.root.setPositionFrom(fixture.position);
    _pieces.add(_Piece(fixture, instance.root));
  }

  Future<ModelAsset?> _load(String path) async {
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: BundleAssetSource(path)),
      );
      return ModelAsset.fromDocument(
        document,
        fallbackAlbedo: fallbackAlbedo ?? SolidColorTexture.white.upload(),
        name: path,
      );
    } catch (error) {
      debugPrint('level: could not load model "$path": $error');
      return null;
    }
  }

  /// Something visible for a fixture whose material the level did not name.
  ///
  /// Colour-coded by what it is rather than a single debug pink: a key has to
  /// read as its own colour from across a room, and a button has to look like
  /// something you press.
  LevelMaterial _fallbackFor(Fixture fixture) {
    final mechanism = fixture.mechanism;
    if (mechanism is Pickup) {
      return LevelMaterial(
        baseColor: _keyColours[mechanism.detail] ?? Vector4(0.8, 0.8, 0.2, 1.0),
        roughness: 0.25,
        metallic: 0.6,
      );
    }
    if (mechanism is Button) {
      return LevelMaterial(
        baseColor: Vector4(0.75, 0.22, 0.16, 1.0),
        roughness: 0.4,
      );
    }
    return LevelMaterial(baseColor: Vector4(0.45, 0.42, 0.38, 1.0));
  }

  static final Map<String, Vector4> _keyColours = <String, Vector4>{
    'blue': Vector4(0.20, 0.42, 0.95, 1.0),
    'red': Vector4(0.90, 0.18, 0.16, 1.0),
    'yellow': Vector4(0.95, 0.82, 0.20, 1.0),
  };

  /// Moves every node to its collider, once a frame.
  ///
  /// Reading the collider rather than the mover's progress means a door that
  /// stopped because somebody was standing in it is drawn where it actually
  /// stopped, and there is no second copy of the travel arithmetic to disagree
  /// with the first.
  void sync(double elapsed) {
    for (final piece in _pieces) {
      final mechanism = piece.fixture.mechanism;
      if (mechanism is Pickup && mechanism.isTaken) {
        piece.node.visible = false;
        continue;
      }
      piece.node.setPositionFrom(piece.fixture.position);

      // A pickup turns. It is the oldest trick in the genre and it works for
      // the same reason it always did: a thing that moves in a still room is
      // a thing the player walks over to.
      if (mechanism is Pickup) {
        piece.node.setRotation(
          Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), elapsed * 1.4),
        );
      }
    }
  }
}

final class _Piece {
  _Piece(this.fixture, this.node);

  final Fixture fixture;
  final SceneNode node;
}
