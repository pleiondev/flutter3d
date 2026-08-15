/// What this game's circuit is made of, and what the car is.
///
/// The same division the platformer keeps: the genre package says where the
/// road is and how wide, and this file says what colour it is. Nothing here is
/// simulation — swapping every material would not change a lap time.
library;

// Not hiding `Material`: this file draws a road rather than a widget, so the
// one that matters here is the engine's.
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_racing/bridge.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:vector_math/vector_math.dart';

/// The asset the player drives.
const String kCarModel = 'assets/models/car.glb';

/// What the surfaces look like.
///
/// Flat colours, because the circuit has no texture set drawn for it yet and a
/// road that will not load until somebody paints one is a road nobody can
/// drive. The tarmac is deliberately dark and rough: a bright road washes out
/// under a sun bright enough to light a car, and every arcade racer's tarmac is
/// darker than the real thing for the same reason.
abstract final class Looks {
  static Material get road => Material(
        // Dark, but not as dark as the first attempt: at (0.085, 0.088, 0.095)
        // the tarmac was within a few percent of the renderer's default clear
        // colour, so on a circuit with sky at the end of every straight the
        // road and the void were the same grey and the track looked like it
        // stopped at the horizon.
        baseColor: Vector4(0.17, 0.175, 0.185, 1.0),
        roughness: 0.92,
        lighting: LightingModel.pbr,
      );

  static Material get verge => Material(
        baseColor: Vector4(0.14, 0.24, 0.11, 1.0),
        roughness: 1.0,
        lighting: LightingModel.pbr,
      );

  static Material get barrier => Material(
        baseColor: Vector4(0.72, 0.72, 0.75, 1.0),
        roughness: 0.55,
        metallic: 0.1,
        lighting: LightingModel.pbr,
      );

  /// What a car is before its model has loaded, and what the other cars are.
  ///
  /// A box is not a placeholder that got left in: a field of eight of these
  /// draws in eight draw calls and reads perfectly well at the distance an
  /// opponent is usually seen from.
  static Material rival(int index) {
    const palette = <List<double>>[
      <double>[0.85, 0.16, 0.12],
      <double>[0.12, 0.35, 0.85],
      <double>[0.95, 0.72, 0.10],
      <double>[0.15, 0.70, 0.35],
      <double>[0.70, 0.20, 0.75],
    ];
    final colour = palette[index % palette.length];
    return Material(
      baseColor: Vector4(colour[0], colour[1], colour[2], 1.0),
      roughness: 0.4,
      metallic: 0.2,
      lighting: LightingModel.pbr,
    );
  }
}

/// Builds the circuit's own geometry and puts it in [scene].
///
/// Returns the nodes, so that a circuit can be taken out again when another is
/// loaded — a scene that only ever gains nodes is a scene that leaks a whole
/// track every time somebody restarts.
List<SceneNode> addTrackTo(
  Scene scene,
  TrackSpline track, {
  required GraphicsDevice device,
}) {
  final added = <SceneNode>[];

  void put(String name, MeshData mesh, Material material) {
    if (mesh.indices.isEmpty) return;
    final node = MeshNode(
      DeviceMesh.upload(device, mesh),
      material,
      name: name,
    );
    scene.add(node);
    added.add(node);
  }

  // The verges first, then the road on top of them. Both are flat ribbons and
  // they meet exactly at the kerb, so which is drawn first decides nothing —
  // but the road is the thing with markings on it later, and a road drawn last
  // is a road whose markings are not fighting anything for the depth buffer.
  put('verge-left', buildVergeMesh(track, side: -1), Looks.verge);
  put('verge-right', buildVergeMesh(track, side: 1), Looks.verge);
  put('road', buildRoadMesh(track), Looks.road);

  for (final side in <int>[-1, 1]) {
    final walls = buildBarrierMeshes(track, side: side);
    for (var i = 0; i < walls.length; i++) {
      put('barrier-$side-$i', walls[i], Looks.barrier);
    }
  }

  return added;
}

/// A car-shaped box, for an opponent or for the player before the model
/// arrives.
MeshNode carBox(GraphicsDevice device, Material material, {String? name}) =>
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(1.8, 1.0, 4.3))
            .build(),
      ),
      material,
      name: name,
    );
