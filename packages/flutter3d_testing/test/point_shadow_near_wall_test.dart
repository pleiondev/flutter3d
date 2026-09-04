/// A point light close to the wall it lights, which is what a torch is.
///
///     flutter test test/point_shadow_near_wall_test.dart
///
/// **The shape this catches is a rectangle.** Every golden scene with a cube
/// shadow in it puts the light in open space, a metre or more from anything —
/// and a light in open space never leaves the face of the cube map that is
/// pointing at the thing it lights. A torch does: it hangs a third of a metre
/// off a wall, so the wall it lights runs out of that face within a metre of
/// the flame and continues into the four faces beside it. What the player sees
/// is a lit rectangle around the flame with the rest of the wall in shadow, and
/// the edges of it are exactly the edges of one cube face.
///
/// So this is not a picture test. It reads the lit wall along a horizontal line
/// through the flame and asks whether brightness falls off the way distance
/// does — smoothly — or whether it drops off a cliff somewhere.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Where the flame is, and how far off the wall.
///
/// The crypt's numbers: `hall_west` sits at x −5.4 with its torch model at
/// −5.75 and the wall behind that. Moved to the origin here and kept at the
/// same 0.35 m standoff, because the standoff is the whole point.
const double _standoff = 0.35;

void main() {
  test('a wall lit by a torch has no straight edge across it', () async {
    final frame = await renderFrame(
      width: 240,
      height: 120,
      settings: const RenderSettings(
        // Nothing but the light and the geometry: no tone curve to flatten the
        // falloff being measured, no bloom to spill across the edge being
        // looked for.
        bloom: BloomSettings(enabled: false),
      ),
      build: (FrameRequest request) {
        final device = request.device;
        final scene = Scene();

        // A wall in the z = 0 plane, wide enough that the cube face the light
        // points at cannot cover it: at 0.35 m the face spans 0.7 m, and this
        // is eight metres of wall.
        final wall = MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3(8.0, 4.0, 0.4)).build(),
          ),
          Material(
            name: 'wall',
            baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
            roughness: 0.9,
          ),
          name: 'wall',
        )..setPosition(0.0, 0.0, -0.2);
        scene.add(wall);

        scene.add(
          LightNode(
            type: LightType.point,
            color: Vector3(1.0, 1.0, 1.0),
            intensity: 6.0,
            range: 13.0,
            castsShadow: true,
            name: 'torch',
          )..setPosition(0.0, 0.0, _standoff),
        );

        // Straight on, far enough back to see three metres of wall either side
        // of the flame.
        final camera = CameraNode(
          projection: const PerspectiveProjection(fovYRadians: 1.0),
        )..setPosition(0.0, 0.0, 6.0);
        return (scene: scene, camera: camera);
      },
    );

    // The row through the light, as brightness per column.
    final row = _rowLuminance(frame, y: frame.height ~/ 2);

    // Brightness falls with distance from the flame, so every step outward
    // should be a small step down. A cube-face edge is not a small step: it is
    // the same wall, the same normal and the same distance on both sides of it,
    // and one side is in shadow.
    //
    // Mutation this was written against: none needed — it failed on the day it
    // was written, at the two columns where the face changes.
    final worst = _sharpestStep(row);
    expect(
      worst.drop,
      lessThan(0.35),
      reason:
          'brightness falls by ${(worst.drop * 100).toStringAsFixed(0)}% '
          'between columns ${worst.at} and ${worst.at + 1} of ${row.length}, '
          'on a flat wall where the distance to the light barely changes — '
          'that is a cube-face boundary, not a falloff',
    );
  });
}

/// Perceived brightness of each column of one row, 0..1.
List<double> _rowLuminance(RenderedFrame frame, {required int y}) {
  final pixels = Uint8List.sublistView(frame.pixels);
  return <double>[
    for (var x = 0; x < frame.width; x++)
      () {
        final at = (y * frame.width + x) * 4;
        return (0.2126 * pixels[at] +
                0.7152 * pixels[at + 1] +
                0.0722 * pixels[at + 2]) /
            255.0;
      }(),
  ];
}

/// The largest fall between neighbouring columns, as a fraction of the brighter
/// one, and where it is.
///
/// Relative rather than absolute, because the wall is bright near the flame and
/// dim at the edges of the frame: a tenth of a unit is nothing in the middle
/// and everything at the edge.
({double drop, int at}) _sharpestStep(List<double> row) {
  var drop = 0.0;
  var at = 0;
  for (var i = 0; i < row.length - 1; i++) {
    // **Both sides have to be wall.** The wall ends before the frame does, and
    // its silhouette against the clear colour is a hundred-percent fall that
    // means nothing — the first version of this test found that edge and
    // reported it as the defect it was looking for.
    if (row[i] < 0.05 || row[i + 1] < 0.05) continue;
    final brighter = row[i] > row[i + 1] ? row[i] : row[i + 1];
    final step = (row[i] - row[i + 1]).abs() / brighter;
    if (step > drop) {
      drop = step;
      at = i;
    }
  }
  return (drop: drop, at: at);
}
