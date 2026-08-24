/// What this game's circuit is made of, and what the car is.
///
/// The same division the platformer keeps: the genre package says where the
/// road is and how wide, and this file says what colour it is. Nothing here is
/// simulation — swapping every material would not change a lap time.
library;

// Not hiding `Material`: this file draws a road rather than a widget, so the
// one that matters here is the engine's.
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game_racing/bridge.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
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

  /// The lap somebody already drove, drawn beside the one they are driving.
  ///
  /// Translucent and pale, in a colour no rival wears: a ghost has to be
  /// readable as *not a car you can hit* at the glance a driver can spare, and
  /// the two ways to say that are through it and unlike everything else.
  ///
  /// `blend` puts it in the transparent half of the render list, so the road
  /// shows through rather than being drawn over.
  static Material ghost() => Material(
        baseColor: Vector4(0.65, 0.85, 1.0, 0.32),
        roughness: 0.3,
        alphaMode: MaterialAlphaMode.blend,
        // Nothing writes depth through a ghost: two of them overlapping should
        // be brighter, not a hole in the one behind.
        depthWrite: false,
        lighting: LightingModel.unlit,
      );

  /// The colour car [index] is painted, model and box alike.
  ///
  /// One list, read by both, so a rival does not change colour at the moment
  /// its model arrives — the box it replaces was already wearing this.
  static Vector4 carPaint(int index) {
    const palette = <List<double>>[
      <double>[0.85, 0.16, 0.12],
      <double>[0.12, 0.35, 0.85],
      <double>[0.95, 0.72, 0.10],
      <double>[0.15, 0.70, 0.35],
      <double>[0.70, 0.20, 0.75],
    ];
    final colour = palette[index % palette.length];
    return Vector4(colour[0], colour[1], colour[2], 1.0);
  }

  /// What a car is before its model has loaded.
  ///
  /// Every car on the grid is now a real one; this is what stands in for the
  /// few frames between the grid being formed and the model being decoded and
  /// uploaded, and what the whole field falls back to if that fails. A box that
  /// is only ever seen for a moment still has to be the right colour, or the
  /// field appears to change livery as it loads.
  static Material rival(int index) => Material(
        baseColor: carPaint(index),
        roughness: 0.4,
        metallic: 0.2,
        lighting: LightingModel.pbr,
      );

  /// The materials of the car model that carry its livery.
  ///
  /// The asset is a real racing car with forty materials — tyres, glass, brake
  /// discs, carbon, a steering wheel with an LCD on it. Painting all of them
  /// would give a rival coloured tyres and a coloured windscreen, so only the
  /// panels are painted, and they are found by the name the artist gave them.
  ///
  /// Matched on a substring rather than the whole name because the exporter
  /// suffixes duplicates: the panels arrive as `car_chassis.005` and
  /// `car_chassis2.005`, and a new export would renumber both.
  static bool isBodywork(String? name) =>
      name != null && name.toLowerCase().contains('chassis');

  /// Paints [colour] onto the bodywork of one car.
  ///
  /// **Only ever call this on materials the instance owns.** [Material.baseColor]
  /// multiplies the livery texture, and the materials of a model instantiated
  /// with `shareMaterials: true` are the asset's own — painting those paints
  /// every car drawn from that asset, which is the whole field.
  ///
  /// Set rather than multiplied, so that painting the same instance twice
  /// leaves it the colour asked for instead of a darker one. Nothing does that
  /// today; it is a cheap property to have and an unpleasant bug to find.
  static void paint(List<MeshNode> meshes, Vector4 colour) {
    for (final mesh in meshes) {
      if (isBodywork(mesh.material.name)) mesh.material.baseColor.setFrom(colour);
    }
  }

  /// Turns one car into the ghost of one.
  ///
  /// Every part, not the bodywork only: a ghost is one translucent shape rather
  /// than a car with a livery, and a ghost with solid tyres and a solid engine
  /// inside it would read as a car somebody could hit.
  ///
  /// **Replaces the materials rather than editing them.** [Looks.ghost] is
  /// unlit, blended and writes no depth, and the model's own materials are
  /// textured, opaque and lit — turning one into the other means changing more
  /// than a colour. Replacing also drops the livery texture, which is the
  /// point: a ghost is a shape, not a car with sponsors on it.
  ///
  /// One material across all forty parts, deliberately. Nothing colours a
  /// ghost per part, and one material is one fewer state change per part in the
  /// pass that draws it.
  static void haunt(List<MeshNode> meshes) {
    final look = ghost();
    for (final mesh in meshes) {
      mesh.material = look;
    }
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
