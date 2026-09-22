/// The weight gradient, drawn — `anim-11`'s own acceptance checked against a
/// picture rather than only against `weight_gradient_test.dart`'s own
/// arithmetic: a vertex painted at full weight reads back `#FF3B5C` on
/// screen, and one painted at none reads back `#2A3A7A`.
///
///     flutter test test/weight_gradient_frame_test.dart
///
/// Two cubes, both the stage's own default geometry, one painted fully onto a
/// joint and one painted fully away from it — through `paintWeightGradient`,
/// under `kWeightGradientMaterial` and `weightGradientSettings`, the same
/// three `weight_gradient.dart` hands whatever later wires a real brush to
/// them. Through `staging.dart`'s own `ModelerStage.build`, because `no test
/// builds its own world` in `tool/structure.dart` says so — only the second
/// cube and the paint are this test's own.
// Draws real pixels: a scene through the software rasteriser, a reference
// picture, or both. Tagged so a run that only wants the logic skips the whole
// slow class at once:
//
//     very_good test -x golden
//
// Not optional in CI, which runs the suite without the flag.
@Tags(<String>['golden'])
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/display_modes.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/weight_gradient.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 160;
const int _height = 100;

/// A cube of the stage's own default size, uploaded fresh and painted so
/// every one of its vertices reads either full or no weight for joint zero —
/// full by leaving a mesh nobody has ever skinned at `weightsOf`'s own
/// documented default, none by assigning one vertex onto a different joint,
/// which — `assignSelection` replacing the whole list rather than
/// accumulating onto the default `paintWeight` would — is enough to allocate
/// the whole mesh's storage to real, stored zero.
(EditMesh, DeviceMesh) _cube(GraphicsDevice device, {required bool full}) {
  final edit = EditMesh.cuboid();
  if (!full) {
    edit.beginStep();
    assignSelection(edit, <int>[0], 1, 1.0);
    edit.endStep();
  }
  final plan = MeshLayoutPlan()..build(edit);
  final deviceMesh = DeviceMesh.upload(device, edit.toMeshData());
  paintWeightGradient(
    device: device,
    mesh: deviceMesh,
    plan: plan,
    vertexWeights: vertexWeightsForJoint(edit, 0),
  );
  return (edit, deviceMesh);
}

void main() {
  test('a fully-weighted cube paints #FF3B5C and an unweighted one paints '
      '#2A3A7A, side by side in the same frame', () async {
    final frame = await renderFrame(
      width: _width,
      height: _height,
      settings: weightGradientSettings(const RenderSettings()),
      build: (FrameRequest request) {
        final stage = ModelerStage.build(device: request.device);

        final zero = _cube(request.device, full: false);
        final full = _cube(request.device, full: true);

        final subject = stage.subject as MeshNode
          ..mesh = zero.$2
          ..material = kWeightGradientMaterial
          ..setPosition(-0.75, 0, 0);
        subject.add(
          MeshNode(full.$2, kWeightGradientMaterial, name: 'full')
            ..setPosition(1.5, 0, 0),
        );

        lookFrom(stage.orbit, StandardView.front, seconds: 0.0);
        stage.frameSubject();
        return (scene: stage.scene, camera: stage.camera);
      },
    );

    await expectMatchesGolden(frame, 'test/goldens/weights-gradient.png');

    // The explicit pixel check `anim-11`'s own acceptance names — not only
    // the golden diff above, which would pass just as happily against a
    // picture nobody looked at. Both faces are flat: every corner of the
    // `+Z` face `paintWeightGradient` touched carries the same weight, so
    // the sample does not have to land on any particular vertex, only
    // somewhere inside the square that face projects to.
    ({int r, int g, int b}) at(int x, int y) {
      final i = (y * _width + x) * 4;
      return (
        r: frame.pixels[i],
        g: frame.pixels[i + 1],
        b: frame.pixels[i + 2],
      );
    }

    final left = at(60, _height ~/ 2);
    final right = at(100, _height ~/ 2);

    // Mutation: write the sRGB stop straight into the vertex colour with no
    // linearisation, and both of these come back noticeably darker than the
    // hex the design named — the gap `weight_gradient.dart`'s own doc
    // comment warns a naive write leaves.
    expect(left.r, closeTo(0x2A, 3));
    expect(left.g, closeTo(0x3A, 3));
    expect(left.b, closeTo(0x7A, 3));

    expect(right.r, closeTo(0xFF, 3));
    expect(right.g, closeTo(0x3B, 3));
    expect(right.b, closeTo(0x5C, 3));
  });
}
