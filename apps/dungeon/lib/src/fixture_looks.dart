import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_shooter/flutter3d_shooter.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter3d_shooter/sample.dart';

/// What this game's fixtures look like.
///
/// The bridge already knows where a fixture goes, how to share its meshes, how
/// to override its material and how to drive its glow off the simulation's
/// brightness. None of that is dungeon-specific. The silhouettes are: a torch is
/// a plate, a shaft and a cup, a lamp is a globe on a stem, and a window is a
/// pane. Move those into the bridge and the next game gets torches whether it
/// wants them or not.
final class DungeonFixtures implements FixtureAppearance {
  const DungeonFixtures();

  /// Builds the visible part of a torch, a lamp or a window.
  ///
  /// Shape by kind rather than one box for all three: what makes a torch read
  /// as a torch at ten metres in a dark corridor is its silhouette, and a
  /// glowing cube is a glowing cube whatever the level calls it.
  @override
  TorchFire? buildLightFixture(LightFixtureBuild build) {
    final size = build.fixture.size;
    final holder = build.holder;
    final meshes = build.meshes;
    final glow = build.glow;

    switch (build.fixture.entity.type) {
      case SampleEntities.window:
        // One pane, flat, emissive across its whole face. A box is right here:
        // a window in a wall is a box.
        holder.add(MeshNode(meshes.box(size), glow, name: 'pane'));
        return null;

      case SampleEntities.lamp:
        holder
          ..add(
            MeshNode(
              meshes.shape(
                'globe${size.x}',
                () => SphereShape(radius: size.x * 0.5),
              ),
              glow,
              name: 'globe',
            ),
          )
          ..add(
            MeshNode(
              meshes.shape(
                'stem',
                () => CylinderShape(
                  radiusTop: 0.03,
                  radiusBottom: 0.03,
                  height: 0.6,
                ),
              ),
              _bracket,
              name: 'stem',
            )..setPosition(0.0, size.y * 0.5 + 0.3, 0.0),
          );
        return null;

      default:
        // A torch is a silhouette before it is anything else, and the
        // silhouette is a stick coming out of the wall with a flame on the end
        // of it. Two boxes read as a glowing crate, which is what the first
        // version of this was.
        //
        // Local +Z points into the wall, so the level's yaw turns the whole
        // thing to face out of whichever wall it is on.
        final cup = MeshNode(
          meshes.shape(
            'cup',
            () => CylinderShape(
              radiusTop: 0.075,
              radiusBottom: 0.05,
              height: 0.1,
            ),
          ),
          _bracket,
          name: 'cup',
        )..setPosition(0.0, 0.08, -0.24);

        holder
          ..add(
            MeshNode(
              meshes.shape(
                'plate',
                () => CuboidShape(size: Vector3(0.16, 0.3, 0.06)),
              ),
              _bracket,
              name: 'plate',
            )..setPosition(0.0, -0.18, 0.06),
          )
          ..add(
            MeshNode(
              meshes.shape(
                'shaft',
                () => CylinderShape(
                  radiusTop: 0.035,
                  radiusBottom: 0.035,
                  height: 0.42,
                ),
              ),
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

        // No mesh for the flame: it is particles, and they come out just clear
        // of the cup's rim.
        return TorchFire(cup, rise: 0.07);
    }
  }

  /// Iron, for the parts that are not on fire.
  static final Material _bracket = Material(
    name: 'bracket',
    baseColor: Vector4(0.16, 0.15, 0.14, 1.0),
    roughness: 0.6,
  );

  /// Something visible for a fixture whose material the level did not name.
  ///
  /// Colour-coded by what it is rather than a single debug pink: a key has to
  /// read as its own colour from across a room, and a button has to look like
  /// something you press.
  @override
  LevelMaterial fallbackFor(Fixture fixture) {
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

  /// A collected pickup is gone, and the node with it.
  @override
  bool isSpent(Fixture fixture) {
    final mechanism = fixture.mechanism;
    return mechanism is Pickup && mechanism.isTaken;
  }

  /// Pickups turn. Doors, lifts, buttons and torches do not.
  @override
  bool spins(Fixture fixture) => fixture.mechanism is Pickup;

  static final Map<String, Vector4> _keyColours = <String, Vector4>{
    'blue': Vector4(0.20, 0.42, 0.95, 1.0),
    'red': Vector4(0.90, 0.18, 0.16, 1.0),
    'yellow': Vector4(0.95, 0.82, 0.20, 1.0),
  };
}
