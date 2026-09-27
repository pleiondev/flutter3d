/// A wall marked as an occluder, a yard of crates behind it, and a lookout in
/// front: the crates the lookout cannot see are the ones occlusion culling
/// leaves out.
///
/// Quoted by `occlusion_culling.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class OcclusionCullingDemo extends ShowcaseDemo {
  double wallX = 0.0;
  bool wallOccludes = true;
  int mode = 1;

  static const List<OcclusionMode> _modes = <OcclusionMode>[
    OcclusionMode.none,
    OcclusionMode.software,
    OcclusionMode.hiZ,
  ];

  /// The lookout's picture is wider than it is tall, like the 256 by 128
  /// buffer the software test draws into.
  static const double _lookoutAspect = 2.0;

  late final MeshNode _wall;
  late final List<MeshNode> _crates;
  late final CameraNode _lookout;
  late final Material _seen;
  late final Material _hidden;

  final SoftwareOcclusion _probe = SoftwareOcclusion();
  int _hiddenCount = 0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 11.0
      ..pitch = 0.75
      ..yaw = 0.35;
  }

  @override
  Scene build(DemoContext context) {
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.42, 0.48, 0.6)
      ..ambientIntensity = 0.18
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 10, depth: 10).build(),
          ),
          Material(
            name: 'yard',
            baseColor: Vector4(0.5, 0.5, 0.48, 1.0),
            roughness: 0.9,
          ),
          name: 'ground',
        )..setPosition(0.0, 0.0, -0.5),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.8, -0.45)),
      );

    // #region wall
    _wall = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(2.6, 1.6, 0.15)).build(),
      ),
      Material(
        name: 'wall',
        baseColor: Vector4(0.36, 0.42, 0.5, 1.0),
        roughness: 0.8,
      ),
      name: 'wall',
    )..setPosition(0.0, 0.8, 1.5);
    _wall.occluder = true;
    scene.add(_wall);
    // #endregion wall

    // #region crates
    _seen = Material(
      name: 'seen',
      baseColor: Vector4(0.92, 0.55, 0.2, 1.0),
      roughness: 0.6,
    );
    _hidden = Material(
      name: 'hidden',
      baseColor: Vector4(0.22, 0.22, 0.24, 1.0),
      roughness: 0.6,
    );
    final DeviceMesh crate = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3.all(0.5)).build(),
    );
    _crates = <MeshNode>[
      for (var row = 0; row < 3; row++)
        for (var column = 0; column < 5; column++)
          MeshNode(crate, _seen, name: 'crate $row.$column')
            ..setPosition((column - 2) * 1.2, 0.25, -0.5 - row * 1.0),
    ];
    _crates.forEach(scene.add);
    // #endregion crates

    // #region lookout
    _lookout =
        CameraNode(
            name: 'lookout',
            projection: const PerspectiveProjection(
              fovYRadians: 60 * math.pi / 180,
              near: 0.1,
              far: 30.0,
            ),
          )
          ..setPosition(0.0, 1.0, 4.0)
          ..lookAt(Vector3(0.0, 0.6, -1.0));
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          context.device,
          SphereShape(radius: 0.15, segments: 16, rings: 8).build(),
        ),
        Material(
          name: 'lookout marker',
          baseColor: Vector4(0.3, 0.8, 0.95, 1.0),
          roughness: 0.4,
        ),
        name: 'lookout marker',
      )..setPosition(0.0, 1.0, 4.0),
    );
    // #endregion lookout
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    _wall
      ..setPosition(wallX, 0.8, 1.5)
      ..occluder = wallOccludes;

    // #region probe
    final Matrix4 viewProjection = _lookout.viewProjection(_lookoutAspect);
    final OcclusionTest test = _probe.prepare(
      meshes: <MeshNode>[_wall, ..._crates],
      viewProjection: viewProjection,
      frustum: Frustum.matrix(viewProjection),
      eye: _lookout.readWorldPosition(),
      layerMask: ~0,
    );
    var hidden = 0;
    for (final MeshNode crate in _crates) {
      final bool visible = test.mayBeVisible(crate.worldBounds);
      crate.material = visible ? _seen : _hidden;
      if (!visible) hidden++;
    }
    _hiddenCount = hidden;
    // #endregion probe
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    occlusion: _modes[mode],
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Wall position',
      min: -2.5,
      max: 2.5,
      value: () => wallX,
      onChanged: (double v) => wallX = v,
      format: (double v) => '${v.toStringAsFixed(2)} m',
    ),
    ToggleControl(
      'Wall is an occluder',
      value: () => wallOccludes,
      onChanged: (bool v) => wallOccludes = v,
    ),
    ChoiceControl(
      'This view culls with',
      options: const <String>['none', 'software', 'hiZ'],
      index: () => mode,
      onChanged: (int i) => mode = i,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_probe.occluders != 1) {
      throw StateError('the wall was not drawn into the occlusion buffer');
    }
    if (_hiddenCount == 0 || _hiddenCount == _crates.length) {
      throw StateError(
        'the wall should hide some crates from the lookout and not all of '
        'them; it hid $_hiddenCount of ${_crates.length}',
      );
    }
    // #endregion check
    if (frame.drawCalls < 1) {
      throw StateError('the yard did not reach the frame');
    }
  }
}
