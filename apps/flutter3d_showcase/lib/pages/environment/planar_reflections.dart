/// Planar reflections: the scene drawn again by a camera mirrored in a floor,
/// and laid over the floor in proportion to its reflectance and the angle.
///
/// Quoted by `planar_reflections.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class PlanarReflectionsDemo extends ShowcaseDemo {
  bool reflections = true;
  double reflectance = 0.3;
  double resolution = 0.5;

  late final PlanarReflectorNode _mirror;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.0
      ..pitch = 0.3
      ..yaw = 0.5;
    context.orbit.target.setValues(0.0, 0.8, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region floor
    // A dark polished floor: the surface the reflection is laid over. It keeps
    // its own material, lit and shadowed as any floor is.
    final MeshNode floor = MeshNode(
      DeviceMesh.upload(
        context.device,
        const PlaneShape(width: 14, depth: 14).build(),
      ),
      Material(
        name: 'polished floor',
        baseColor: Vector4(0.08, 0.08, 0.09, 1.0),
        roughness: 0.2,
      ),
      name: 'floor',
    );
    // #endregion floor

    final Scene scene = Scene()
      ..ambientIntensity = 0.3
      ..add(floor)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.5, -0.7, -0.4)),
      );

    // #region objects
    // Something to see in it: a red ball, a gold block and a tall blue post.
    scene
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            SphereShape(radius: 0.8, segments: 32, rings: 16).build(),
          ),
          Material(name: 'red', baseColor: Vector4(0.8, 0.12, 0.1, 1.0)),
          name: 'ball',
        )..setPosition(-1.2, 0.8, 0.4),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build(),
          ),
          Material(
            name: 'gold',
            baseColor: Vector4(1.0, 0.75, 0.3, 1.0),
            metallic: 1.0,
            roughness: 0.3,
          ),
          name: 'block',
        )..setPosition(1.3, 0.5, -0.3),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(0.4, 3.0, 0.4)).build(),
          ),
          Material(name: 'blue', baseColor: Vector4(0.15, 0.3, 0.8, 1.0)),
          name: 'post',
        )..setPosition(0.2, 1.5, -2.0),
      );
    // #endregion objects

    // #region mirror
    // The plane is the node's own: through its origin, seen from its +Y. The
    // floor lies in it, so the floor is the surface the picture goes on.
    _mirror = PlanarReflectorNode(
      surfaces: <MeshNode>[floor],
      reflectance: reflectance,
      resolution: resolution,
      name: 'mirror',
    );
    scene.add(_mirror);
    // #endregion mirror
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    _mirror
      ..reflectance = reflectance
      ..resolution = resolution;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    sky: const SkySettings(enabled: true),
    // #region switch
    planarReflections: PlanarReflectionSettings(enabled: reflections),
    // #endregion switch
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Planar reflections',
      value: () => reflections,
      onChanged: (bool v) => reflections = v,
    ),
    SliderControl(
      'Reflectance',
      min: 0.02,
      max: 1,
      value: () => reflectance,
      onChanged: (double v) => reflectance = v,
      format: (double v) => v.toStringAsFixed(2),
    ),
    SliderControl(
      'Resolution',
      min: 0.25,
      max: 1,
      value: () => resolution,
      onChanged: (double v) => resolution = v,
      format: (double v) => '${(v * 100).round()} %',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // On, the mirrored camera draws the scene before the scene pass does: the
    // three objects, not the floor, which stands in the plane.
    final FramePass? pass = frame.passes
        .where((FramePass p) => p.name == 'planar reflections')
        .firstOrNull;
    if (!reflections) {
      if (pass != null) throw StateError('off should not run the pass');
      return;
    }
    if (pass == null) {
      throw StateError('the reflection was not drawn: ${frame.skipped}');
    }
    if (pass.drawCalls < 3) {
      throw StateError(
        'the mirrored camera drew ${pass.drawCalls} meshes; three stand '
        'above the floor',
      );
    }
    // #endregion check
  }
}
