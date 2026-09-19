/// The small scene the post-processing pages share, and one check they share.
///
/// **Not a page.** A post effect is a change to a picture, so every page in this
/// category needs a picture to change: a floor, three shapes in three colours,
/// and a sun.
/// The pages keep only the lines about their own effect and call this for the
/// rest. It stays here, beside the pages that use it, because it is only
/// meaningful next to them.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

/// The pieces of the stage a page may want to reach after it is built.
final class PostStage {
  PostStage._(this.scene, this.sun, this.shapes);

  final Scene scene;
  final LightNode sun;

  /// The three shapes on the floor, left to right.
  final List<MeshNode> shapes;

  /// Builds the stage on the device of [context].
  ///
  /// [shadows] lets the sun cast, for the effects that read the shadow map.
  static PostStage build(
    DemoContext context, {
    bool shadows = false,
    double sunIntensity = 3.0,
    double floorSize = 14.0,
  }) {
    final GraphicsDevice device = context.device;
    final MeshNode floor = MeshNode(
      DeviceMesh.upload(
        device,
        PlaneShape(width: floorSize, depth: floorSize).build(),
      ),
      Material(
        name: 'floor',
        baseColor: Vector4(0.62, 0.6, 0.56, 1.0),
        roughness: 0.9,
      ),
      name: 'floor',
    );

    final MeshNode ball = MeshNode(
      DeviceMesh.upload(device, const SphereShape(radius: 0.6).build()),
      Material(
        name: 'red',
        baseColor: Vector4(0.85, 0.22, 0.18, 1.0),
        roughness: 0.35,
      ),
      name: 'ball',
    )..setPosition(-1.7, 0.6, 0.0);

    final MeshNode block = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build(),
      ),
      Material(
        name: 'blue',
        baseColor: Vector4(0.18, 0.36, 0.85, 1.0),
        roughness: 0.6,
      ),
      name: 'block',
    )..setPosition(0.0, 0.5, 0.0);

    final MeshNode ring = MeshNode(
      DeviceMesh.upload(
        device,
        const TorusShape(radius: 0.45, tubeRadius: 0.2).build(),
      ),
      Material(
        name: 'gold',
        baseColor: Vector4(0.95, 0.75, 0.25, 1.0),
        metallic: 1.0,
        roughness: 0.3,
      ),
      name: 'ring',
    )..setPosition(1.7, 0.65, 0.0);

    final LightNode sun = LightNode(
      name: 'sun',
      intensity: sunIntensity,
      castsShadow: shadows,
    )..setLocalForward(Vector3(-0.5, -0.8, -0.35));

    final Scene scene = Scene()
      ..add(floor)
      ..add(ball)
      ..add(block)
      ..add(ring)
      ..add(sun);
    return PostStage._(scene, sun, <MeshNode>[ball, block, ring]);
  }

  /// A view that sees the whole stage from a little above.
  static void frame(DemoContext context, {double distance = 8.0}) {
    context.orbit
      ..distance = distance
      ..pitch = 0.32
      ..yaw = 0.35;
    context.orbit.target.setValues(0.0, 0.7, 0.0);
    context.orbit.apply();
  }
}

/// Whether [frame] ran the pass called [name].
bool passRan(FrameResult frame, String name) =>
    frame.passes.any((FramePass pass) => pass.name == name);

/// The claim most pages make: the pass they are about ran, or the frame says
/// the device could not run it.
///
/// A pass that neither ran nor said why is the failure. A pass the device
/// declines is not: the page then shows the picture without it, and the frame
/// carries [PassSkip.unsupported] for it, which is what the host reports to the
/// person.
void expectPassOrDecline(FrameResult frame, String name) {
  if (passRan(frame, name)) return;
  final PassSkip? why = frame.skipReasonOf(name);
  if (why == PassSkip.unsupported) return;
  throw StateError(
    'the "$name" pass did not run and the frame did not say the device '
    'declined it (reason: ${why ?? 'not registered'})',
  );
}
