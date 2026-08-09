import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// What the doors, lifts, platforms, buttons and keys look like.
///
/// The engine reports a [Fixture] — a box, a size, a material name and whatever
/// runs it — and this turns each one into a node and keeps that node where the
/// collider is. It is the whole of the application's side of stage 8, which is
/// the point: the simulation never learns that meshes exist.
final class FixtureVisuals {
  FixtureVisuals(this.scene, this.materials);

  final Scene scene;

  /// The level's palette, so a door authored as `stone` matches the wall it
  /// sits in rather than being whatever colour this file felt like.
  final Map<String, LevelMaterial> materials;

  final List<_Piece> _pieces = <_Piece>[];

  void add(Fixture fixture) {
    final source = materials[fixture.material] ?? _fallbackFor(fixture);
    final node = MeshNode(
      GpuMesh.upload(CuboidShape(size: fixture.size).build()),
      engine.Material(
        name: fixture.material,
        baseColor: source.baseColor,
        roughness: source.roughness,
        metallic: source.metallic,
      ),
      name: fixture.entity.name ?? fixture.entity.type,
    )..setPositionFrom(fixture.position);
    scene.add(node);
    _pieces.add(_Piece(fixture, node));
  }

  /// Something visible for a fixture whose material the level did not name.
  ///
  /// Colour-coded by what it is rather than a single debug pink: a key has to
  /// read as its own colour from across a room, and a button has to look like
  /// something you press.
  LevelMaterial _fallbackFor(Fixture fixture) {
    final mechanism = fixture.mechanism;
    if (mechanism is KeyPickup) {
      return LevelMaterial(
        baseColor: _keyColours[mechanism.colour] ?? Vector4(0.8, 0.8, 0.2, 1.0),
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
  void sync() {
    for (final piece in _pieces) {
      final mechanism = piece.fixture.mechanism;
      if (mechanism is KeyPickup && mechanism.isTaken) {
        piece.node.visible = false;
        continue;
      }
      piece.node.setPositionFrom(piece.fixture.position);
    }
  }
}

final class _Piece {
  _Piece(this.fixture, this.node);

  final Fixture fixture;
  final MeshNode node;
}
