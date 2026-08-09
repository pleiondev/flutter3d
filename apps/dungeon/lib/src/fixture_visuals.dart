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

  /// The level's lights, by name, so a fixture can dim the one it owns.
  final Map<String, LightNode> _lights = <String, LightNode>{};

  /// Materials whose emissive is driven every frame. Kept per fixture rather
  /// than shared, because two torches at different points of their flicker
  /// cannot be one material.
  final Map<LightFixture, engine.Material> _glowing =
      <LightFixture, engine.Material>{};

  /// Learns where the level's named lights are. Called once, after the scene
  /// is built.
  void bindLights() {
    for (final node in scene.lights) {
      final name = node.name;
      if (name != null) _lights[name] = node;
    }
    for (final node in scene.lights) {
      _baseIntensity[node] = node.intensity;
    }
  }

  final Map<LightNode, double> _baseIntensity = <LightNode, double>{};

  void add(Fixture fixture) {
    final mechanism = fixture.mechanism;
    if (mechanism is LightFixture) {
      _addLightFixture(fixture, mechanism);
      return;
    }

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
      _box(fixture.size),
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

  /// Builds the visible part of a torch, a lamp or a window.
  ///
  /// Shape by kind rather than one box for all three: what makes a torch read
  /// as a torch at ten metres in a dark corridor is its silhouette, and a
  /// glowing cube is a glowing cube whatever the level calls it.
  void _addLightFixture(Fixture fixture, LightFixture mechanism) {
    final size = fixture.size;
    final colour = fixture.entity.vector('color') ?? Vector3(1.0, 0.72, 0.36);

    final glow = engine.Material(
      name: '${fixture.entity.type} glow',
      baseColor: Vector4(colour.x * 0.4, colour.y * 0.4, colour.z * 0.4, 1.0),
      roughness: 0.9,
      // The light itself is a scene light; this is only the thing that looks
      // hot. Emissive rather than a bright base colour, so the bloom picks it
      // up — an unbloomed flame reads as a painted orange square.
      emissive: Vector3(colour.x, colour.y, colour.z),
      emissiveStrength: fixture.entity.number('glow') ?? 3.0,
    );
    _glowing[mechanism] = glow;
    _baseGlow[mechanism] = glow.emissiveStrength;

    final holder = SceneNode(name: fixture.entity.type)
      ..setPositionFrom(fixture.position)
      ..setRotation(
        Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), fixture.entity.yaw),
      );
    scene.add(holder);

    switch (fixture.entity.type) {
      case EntityTypes.window:
        // One pane, flat, emissive across its whole face. A box is right here:
        // a window in a wall is a box.
        holder.add(MeshNode(_box(size), glow, name: 'pane'));

      case EntityTypes.lamp:
        holder
          ..add(
            MeshNode(
              _shape('globe${size.x}', SphereShape(radius: size.x * 0.5)),
              glow,
              name: 'globe',
            ),
          )
          ..add(
            MeshNode(
              _shape('stem', CylinderShape(radiusTop: 0.03, radiusBottom: 0.03, height: 0.6)),
              _bracket,
              name: 'stem',
            )..setPosition(0.0, size.y * 0.5 + 0.3, 0.0),
          );

      default:
        // A torch is a silhouette before it is anything else, and the
        // silhouette is a stick coming out of the wall with a flame on the end
        // of it. Two boxes read as a glowing crate, which is what the first
        // version of this was.
        //
        // Local +Z points into the wall, so the level's yaw turns the whole
        // thing to face out of whichever wall it is on.
        final cup = MeshNode(
          _shape('cup', CylinderShape(radiusTop: 0.075, radiusBottom: 0.05, height: 0.1)),
          _bracket,
          name: 'cup',
        )..setPosition(0.0, 0.08, -0.24);

        holder
          ..add(
            MeshNode(
              _shape('plate', CuboidShape(size: Vector3(0.16, 0.3, 0.06))),
              _bracket,
              name: 'plate',
            )..setPosition(0.0, -0.18, 0.06),
          )
          ..add(
            MeshNode(
              _shape('shaft', CylinderShape(radiusTop: 0.035, radiusBottom: 0.035, height: 0.42)),
              _bracket,
              name: 'shaft',
            )
              ..setPosition(0.0, -0.06, -0.08)
              // Angled up and out, the way a bracket holds one.
              ..setRotation(
                Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), -0.5),
              ),
          )
          ..add(cup);
        // No mesh for the flame: it is particles. Where they come from is the
        // cup's own world position, read every frame rather than recomputed
        // from the yaw — a second copy of the placement is a second chance to
        // put the fire inside the wall, which is what the first version did.
        _flames[mechanism] = TorchFire(cup);
    }

    _pieces.add(_Piece(fixture, holder));
  }

  /// One mesh per distinct shape, shared. A crypt with twenty torches should
  /// upload one flame.
  GpuMesh _box(Vector3 size) =>
      _shape('box${size.x},${size.y},${size.z}', CuboidShape(size: size));

  GpuMesh _shape(String key, Shape shape) =>
      _meshes.putIfAbsent(key, () => GpuMesh.upload(shape.build()));

  final Map<String, GpuMesh> _meshes = <String, GpuMesh>{};

  /// The fire of each torch: where it comes out, and what it is worth.
  final Map<LightFixture, TorchFire> _flames = <LightFixture, TorchFire>{};

  /// Every torch that wants particles.
  Map<LightFixture, TorchFire> get flames => _flames;

  /// Just above the rim, in world space.
  ///
  /// From the node's own transform, so the fire is wherever the cup ended up
  /// however the level turned it.
  Vector3 flamePointOf(TorchFire fire, Vector3 out) {
    final world = fire.cup.worldMatrix;
    out.setValues(world.entry(0, 3), world.entry(1, 3), world.entry(2, 3));
    return out..y += 0.07;
  }

  /// Iron, for the parts that are not on fire.
  static final engine.Material _bracket = engine.Material(
    name: 'bracket',
    baseColor: Vector4(0.16, 0.15, 0.14, 1.0),
    roughness: 0.6,
  );

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
  /// Emissive strength at full brightness, remembered per fixture so a level
  /// can set one window brighter than another.
  final Map<LightFixture, double> _baseGlow = <LightFixture, double>{};

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

      // The flame and the light it casts move together, off one number. A
      // torch whose flame stays bright while its light dims is a torch nobody
      // believes.
      if (mechanism is LightFixture) {
        final brightness = mechanism.brightness;
        final glow = _glowing[mechanism];
        if (glow != null) {
          glow.emissiveStrength = (_baseGlow[mechanism] ?? 3.0) * brightness;
        }

        final name = mechanism.light;
        final node = name == null ? null : _lights[name];
        if (node != null) {
          node.intensity = (_baseIntensity[node] ?? 0.0) * brightness;
        }
      }
    }
  }
}

final class _Piece {
  _Piece(this.fixture, this.node);

  final Fixture fixture;
  final SceneNode node;
}


/// One torch's fire.
///
/// A [LightEmitter], so the particle system measures it — and the object the
/// emission is keyed on, which means the thing that burns and the thing that
/// is measured are the same thing rather than two that have to be kept in
/// step.
final class TorchFire with LightEmitter {
  TorchFire(this.cup);

  /// The node the flame rises from, read every frame so the fire is wherever
  /// the mesh ended up.
  final SceneNode cup;
}
