/// What stands beside the road: sheds, and a sign whose face is a widget.
///
/// The circuit is a ribbon in an empty field, and an empty field gives a driver
/// nothing to judge speed by. Anything with a known size at a known distance
/// does — which is why the first thing here is a row of plain sheds rather than
/// anything ornamental.
///
/// **Placed against the spline rather than authored into the level.** The level
/// document beside each track says it was written by `tool/make_track.py`, and
/// that script is not in the repository, so a brush added to it by hand is a
/// brush nobody can regenerate. The spline is the thing that actually knows
/// where the road goes, and it is here at run time anyway.
///
/// Scenery only: nothing here reaches the collision world, so a car drives
/// through a shed. The barriers are what stop a car, they are already there,
/// and they stand between the road and everything this file puts down.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:vector_math/vector_math.dart';

/// The look of the things beside the road.
abstract final class Roadside {
  /// Walls. Three of them, so a row of sheds is not one colour repeated.
  static final List<Material> walls = <Material>[
    Material(
      baseColor: Vector4(0.62, 0.58, 0.52, 1.0),
      roughness: 0.9,
      lighting: LightingModel.pbr,
    ),
    Material(
      baseColor: Vector4(0.48, 0.44, 0.42, 1.0),
      roughness: 0.95,
      lighting: LightingModel.pbr,
    ),
    Material(
      baseColor: Vector4(0.55, 0.5, 0.45, 1.0),
      roughness: 0.85,
      lighting: LightingModel.pbr,
    ),
  ];

  /// Roofs, darker than any wall so the shape reads as a building at distance.
  static Material get roof => Material(
    baseColor: Vector4(0.24, 0.22, 0.24, 1.0),
    roughness: 0.8,
    lighting: LightingModel.pbr,
  );

  /// The posts a sign stands on.
  static Material get post => Material(
    baseColor: Vector4(0.3, 0.3, 0.32, 1.0),
    roughness: 0.7,
    metallic: 0.2,
    lighting: LightingModel.pbr,
  );

  /// The face of a sign, given the texture drawn for it.
  ///
  /// Emissive as well as albedo, and that is the difference between a sign and
  /// a painted board: a lit sign is legible when the sun is behind it, which on
  /// a circuit is half of every lap. The strength is low enough that it does
  /// not glow in daylight.
  static Material sign(TextureHandle face) => Material(
    baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
    albedo: face,
    emissiveTexture: face,
    emissiveStrength: 0.35,
    roughness: 0.6,
    // **Both sides, or half the signs are two posts holding nothing.** A plane
    // has one face, and which way it points depends on the sign of the pitch
    // that stands it up. Rather than get that right for a board whose yaw
    // comes off the spline, the board is drawn from either side — which is
    // also what a sign beside a road looks like to a driver who has passed it.
    doubleSided: true,
    lighting: LightingModel.pbr,
  );
}

/// Puts sheds and signs along [track] and returns what it added.
///
/// [signs] are the faces to hang, in the order they are met. An empty list is a
/// circuit with sheds and no signs, which is what a caller gets when the widget
/// textures did not come back — see [drawSignFaces].
List<SceneNode> addRoadsideTo(
  Scene scene,
  TrackSpline track, {
  required GraphicsDevice device,
  CollisionWorld? ground,
  List<ModelAsset> buildings = const <ModelAsset>[],
  List<TextureHandle> signs = const <TextureHandle>[],
}) {
  final added = <SceneNode>[];
  final frame = TrackFrame();
  final hit = RayHit();
  final down = Vector3(0.0, -1.0, 0.0);

  /// Where the ground is under [x], [z].
  ///
  /// **The centre line is not the ground, and assuming it was put the first
  /// row of sheds five metres in the air.** A circuit's road sits on an
  /// embankment: the ring's field is a slab whose top is at −4.861 while the
  /// spline runs about zero. A ray down through the collision world is the
  /// only answer that also holds where the land rises, which it does on three
  /// of the five circuits.
  double groundAt(double x, double z, double fallback) {
    if (ground == null) return fallback;
    final from = Vector3(x, fallback + 200.0, z);
    if (!ground.raycast(from, down, 400.0, hit)) return fallback;
    return hit.point.y;
  }

  void putMesh(
    String name,
    MeshData mesh,
    Material material,
    Vector3 at,
    double yaw,
  ) {
    final node = MeshNode(DeviceMesh.upload(device, mesh), material, name: name)
      ..setPositionFrom(at)
      ..setRotationYawPitchRoll(yaw, 0.0, 0.0);
    scene.add(node);
    added.add(node);
  }

  // Every ninety metres, alternating sides. Ninety because a lap of the ring
  // is about a kilometre and a building every ninety puts a dozen of them out
  // there: enough to read speed by, few enough that the field still looks like
  // a field.
  const spacing = 90.0;
  final count = (track.length / spacing).floor();
  for (var i = 0; i < count; i++) {
    final s = i * spacing;
    track.frameAt(s, frame);
    final side = i.isEven ? 1.0 : -1.0;
    // Clear of the road by its own width again, so nothing stands where a car
    // that has run wide is about to be.
    final offset = track.widthAt(s) * 0.5 + 14.0 + (i % 3) * 4.0;
    final centre = frame.position + frame.right * (side * offset);
    final base = Vector3(
      centre.x,
      groundAt(centre.x, centre.z, centre.y),
      centre.z,
    );
    // Turned away from the road by a few degrees each, so a row of the same
    // four models does not read as a row.
    final yaw =
        math.atan2(-frame.forward.x, -frame.forward.z) + (i % 5 - 2) * 0.18;

    final model = buildings.isEmpty ? null : buildings[i % buildings.length];
    if (model == null) {
      // No models loaded, so a box: a circuit with plain sheds beats a circuit
      // with an empty field, and this is the path a device that refused the
      // upload takes.
      final wide = 6.0 + (i % 3) * 2.0;
      final high = 3.5 + (i % 4) * 0.8;
      putMesh(
        'shed-$i',
        CuboidShape(size: Vector3(wide, high, 5.0 + (i % 2) * 3.0)).build(),
        Roadside.walls[i % Roadside.walls.length],
        Vector3(base.x, base.y + high * 0.5, base.z),
        yaw,
      );
      continue;
    }

    // The kit is authored two units to a building, and a suburban house is
    // eight to ten metres across — so four and a bit, varied a little so the
    // same model twice is not the same house twice.
    final scale = 4.2 + (i % 4) * 0.5;
    final instance = model.instantiate(scene, name: 'building-$i');
    instance.root
      ..setPosition(base.x, base.y, base.z)
      ..setRotationYawPitchRoll(yaw, 0.0, 0.0)
      ..setUniformScale(scale);
    added.add(instance.root);
  }

  // The signs, spread evenly around the lap and always on the outside of the
  // road, facing the way a car arrives.
  for (var i = 0; i < signs.length; i++) {
    final s = track.length * (i + 0.5) / signs.length;
    track.frameAt(s, frame);
    final offset = track.widthAt(s) * 0.5 + 9.0;
    final beside = frame.position + frame.right * offset;
    final base = Vector3(
      beside.x,
      groundAt(beside.x, beside.z, beside.y),
      beside.z,
    );
    // **Across the road, not along it.** A node faces its own −Z, and a board
    // pitched upright wears that as its front. Aiming −Z down the track put
    // the sign side-on to the driver and showed them its back, which reads as
    // a mirrored sign. The sign sits at +right of the centre line, so the face
    // has to look back along −right, and this is the yaw that does it.
    final yaw = math.atan2(frame.right.x, frame.right.z);

    const boardWidth = 10.0;
    const boardHeight = 5.0;
    const standHeight = 3.0;

    // The face is a plane, and a plane is built lying down — so it is pitched
    // a quarter turn to stand up. `setRotationYawPitchRoll` takes the yaw
    // first, which is why the sign's facing survives the tilt.
    final face =
        MeshNode(
            DeviceMesh.upload(
              device,
              const PlaneShape(width: boardWidth, depth: boardHeight).build(),
            ),
            Roadside.sign(signs[i]),
            name: 'sign-$i',
          )
          ..setPosition(
            base.x,
            base.y + standHeight + boardHeight * 0.5,
            base.z,
          )
          ..setRotationYawPitchRoll(yaw + math.pi, 1.5707963267948966, 0.0);
    scene.add(face);
    added.add(face);

    for (final lean in <double>[-1.0, 1.0]) {
      final foot = base + frame.forward * (lean * boardWidth * 0.35);
      putMesh(
        'sign-$i-post-$lean',
        CuboidShape(
          size: Vector3(0.4, standHeight + boardHeight * 0.5, 0.4),
        ).build(),
        Roadside.post,
        Vector3(
          foot.x,
          foot.y + (standHeight + boardHeight * 0.5) * 0.5,
          foot.z,
        ),
        yaw,
      );
    }
  }

  return added;
}

/// The buildings the roadside is made of, or an empty list when they will not
/// load.
///
/// Four of the forty in Kenney's suburban city kit, which is CC0 — see
/// `assets/models/LICENSES.md`. Four rather than forty because a lap goes past
/// a dozen of them and a fifth model would cost a hundred kilobytes to be
/// noticed by nobody.
Future<List<ModelAsset>> loadBuildings(GraphicsDevice device) async {
  const paths = <String>[
    'assets/models/building-a.glb',
    'assets/models/building-e.glb',
    'assets/models/building-k.glb',
    'assets/models/building-q.glb',
  ];
  final loaded = <ModelAsset>[];
  for (final path in paths) {
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: BundleAssetSource(path)),
      );
      loaded.add(
        await ModelAsset.fromDocument(document, device: device, name: path),
      );
    } catch (error) {
      // One building missing is a shorter list, not a circuit without
      // scenery: `addRoadsideTo` falls back to boxes when the list is empty.
      debugPrint('roadside: $path did not load ($error)');
    }
  }
  return loaded;
}

/// Draws the faces the signs wear.
///
/// Widgets, so what a sign says is written the way the rest of this application
/// writes text rather than authored as an image and shipped. [WidgetTexture]
/// explains what that costs; the answer is once, here, before the first frame.
///
/// Returns as many textures as it managed: a device that refuses an upload
/// gives a circuit with fewer signs rather than no circuit.
Future<List<TextureHandle>> drawSignFaces(GraphicsDevice device) async {
  const faces = <Widget>[
    _SignFace(top: 'PIT', bottom: 'LANE', tint: Color(0xFF1B4F9C)),
    _SignFace(top: 'FLUTTER', bottom: '3D', tint: Color(0xFF0B6E4F)),
    _SignFace(top: 'LAP', bottom: 'RECORD', tint: Color(0xFF8A2B2B)),
    _SignFace(top: 'DRIVE', bottom: 'FAST', tint: Color(0xFF7A5C10)),
  ];

  final drawer = WidgetTexture(device);
  final drawn = <TextureHandle>[];
  for (final face in faces) {
    // Twice the board's ten by five metres in pixels per metre, which at the
    // distance a sign is read from is the point where more pixels stop being
    // visible and start being memory.
    final texture = await drawer.draw(face, width: 512, height: 256);
    if (texture != null) drawn.add(texture);
  }
  return drawn;
}

/// One sign's artwork.
class _SignFace extends StatelessWidget {
  const _SignFace({
    required this.top,
    required this.bottom,
    required this.tint,
  });

  final String top;
  final String bottom;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: tint,
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFF2EFE6), width: 6.0),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  top,
                  style: const TextStyle(
                    color: Color(0xFFF2EFE6),
                    fontSize: 74,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    height: 1.0,
                  ),
                ),
                Text(
                  bottom,
                  style: const TextStyle(
                    color: Color(0xFFF2EFE6),
                    fontSize: 52,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 10,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
