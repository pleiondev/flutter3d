/// A scene the parity fixture cannot be.
///
/// Its own file so that the app and the headless dump draw the same thing.
/// Written twice, any difference between the picture on screen and the picture
/// in the PNG would be as likely to be a difference in the two transcriptions
/// as in the backend — which is the reasoning `parity_scene.dart` already
/// spells out, and it applies just as well to a demo.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

/// A torus, a cone and a box, lit from above and to the right.
///
/// Chosen for what each one can fail at rather than for looking nice. The torus
/// occludes itself, so a wrong depth test draws the far side of the tube over
/// the near side and the hole fills in. The box has hard edges, where a
/// rasteriser interpolating a normal across a seam that has none produces a
/// rounded corner. The cone has a cap the tube meets at a sharp crease, and its
/// tip is where a perspective-correct interpolation and a naive one visibly
/// disagree.
({Scene scene, CameraNode camera}) buildShapesScene(GraphicsDevice device) {
  final scene = Scene(name: 'shapes');

  scene.root.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        const TorusShape(radius: 0.75, tubeRadius: 0.3).build(),
      ),
      Material(
        name: 'torus',
        baseColor: Vector4(0.85, 0.35, 0.15, 1.0),
        lighting: LightingModel.lambert,
      ),
      name: 'torus',
    )..setRotationYawPitchRoll(0.4, 0.9, 0.0),
  );

  scene.root.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(0.7, 0.7, 0.7)).build(),
      ),
      Material(
        name: 'box',
        baseColor: Vector4(0.25, 0.55, 0.85, 1.0),
        lighting: LightingModel.lambert,
      ),
      name: 'box',
    )..setPosition(-1.5, 0.6, -0.3),
  );

  scene.root.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        const ConeShape(radius: 0.45, height: 1.0).build(),
      ),
      Material(
        name: 'cone',
        baseColor: Vector4(0.35, 0.75, 0.4, 1.0),
        lighting: LightingModel.lambert,
      ),
      name: 'cone',
    )..setPosition(1.5, -0.5, 0.2),
  );

  scene.root.add(
    LightNode(name: 'key', type: LightType.directional)
      ..intensity = 3.5
      ..setPosition(1.5, 3.0, 2.0)
      ..lookAt(Vector3.zero()),
  );

  final camera = CameraNode(name: 'eye')
    ..setPosition(0.0, 0.4, 4.2)
    ..lookAt(Vector3.zero());
  scene.root.add(camera);

  return (scene: scene, camera: camera);
}
