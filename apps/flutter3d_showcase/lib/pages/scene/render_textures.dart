/// A camera that draws into a texture: a monitor on a stand shows what a
/// second camera in the room sees, in the same frame it was taken.
///
/// Quoted by `render_textures.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class RenderTexturesDemo extends ShowcaseDemo {
  bool everyFrame = true;
  bool _retakeAsked = false;

  late final CameraNode _watcher;
  late final RenderView _picture;
  late final MeshNode _spinner;
  late final Renderer _renderer;
  double _age = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.5
      ..pitch = 0.35
      ..yaw = 0.3;
    context.orbit.target.setValues(0.4, 0.8, 0.0);
  }

  MeshNode _slab(
    DemoContext context,
    String name,
    Vector3 size,
    Vector3 at,
    Vector4 color,
  ) => MeshNode(
    DeviceMesh.upload(context.device, CuboidShape(size: size).build()),
    RenderMaterial(name: name, baseColor: _fromSrgb(color), roughness: 0.7),
    name: name,
  )..setPositionFrom(at);

  @override
  Scene build(DemoContext context) {
    _renderer = context.renderer;
    final Scene scene = Scene()
      ..ambientColor = LinearColor(0.55, 0.6, 0.7)
      ..ambientIntensity = 0.3 * Photometric.legacyUnit
      ..add(
        _slab(
          context,
          'floor',
          Vector3(6.0, 0.1, 6.0),
          Vector3(0.0, -0.05, 0.0),
          Vector4(0.6, 0.62, 0.6, 1.0),
        ),
      )
      ..add(
        _slab(
          context,
          'red block',
          Vector3(0.6, 0.6, 0.6),
          Vector3(-1.4, 0.3, -0.6),
          Vector4(0.85, 0.2, 0.15, 1.0),
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.0 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.6, -1.0, -0.4)),
      );
    _spinner = _slab(
      context,
      'spinner',
      Vector3(0.5, 0.9, 0.5),
      Vector3(-0.6, 0.45, 0.6),
      Vector4(0.2, 0.45, 0.9, 1.0),
    );
    scene.add(_spinner);

    // #region watcher
    // An ordinary camera, put in the scene like any node, with a projection
    // of its own. The texture sets its aspect.
    _watcher = CameraNode(name: 'watcher')
      ..projection = const PerspectiveProjection(
        fovY: math.pi / 4,
        near: 0.1,
        far: 50.0,
      )
      ..setPosition(-3.0, 1.6, 2.4)
      ..lookAt(Vector3(-0.9, 0.4, 0.0));
    scene.add(_watcher);
    // #endregion watcher

    // #region texture
    _picture = RenderView.texture(
      context.device,
      camera: _watcher,
      width: 160,
      height: 120,
      clearColorSrgb: Vector4(0.35, 0.45, 0.6, 1.0),
    );
    // #endregion texture

    // #region screen
    // An unlit plane shows the picture exactly as the camera took it. A
    // plane stood up has v running down it, the way a picture's rows do.
    final MeshNode screen = MeshNode(
      DeviceMesh.upload(
        context.device,
        const PlaneShape(width: 1.6, depth: 1.2).build(),
      ),
      RenderMaterial(
        name: 'screen',
        lighting: LightingModel.unlit,
        albedo: _picture.texture,
      ),
      name: 'screen',
    )..setPosition(1.4, 1.3, -0.6);
    screen.setRotation(
      Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), -0.4) *
          Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2),
    );
    final MeshNode stand = _slab(
      context,
      'stand',
      Vector3(0.12, 0.7, 0.12),
      Vector3(1.4, 0.35, -0.6),
      Vector4(0.2, 0.2, 0.22, 1.0),
    );
    scene
      ..add(screen)
      ..add(stand);
    // #endregion screen

    // #region add
    // The monitor is left out of its own picture, and the texture joins the
    // scene, which draws it before the frame's own meshes.
    _picture.excluded.addAll(<MeshNode>[screen, stand]);
    scene.addTextureView(_picture);
    // #endregion add
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    _age += dt;
    _spinner.setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), _age));
    // #region refresh
    // Every frame, or once and then only when asked: a picture of a room
    // nobody changes does not need taking sixty times a second.
    _picture.options = _picture.options.copyWith(refreshEveryFrame: everyFrame);
    if (_retakeAsked) {
      _retakeAsked = false;
      _picture.invalidate();
    }
    // #endregion refresh
  }

  @override
  void dispose() => _renderer.releaseTextureAfterFrame(_picture.texture!);

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Every frame',
      value: () => everyFrame,
      onChanged: (bool v) => everyFrame = v,
    ),
    ToggleControl(
      'Take the picture again',
      value: () => _retakeAsked,
      onChanged: (bool v) => _retakeAsked = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // The pass that draws the scene's textures ran, and the texture holds a
    // picture rather than whatever its allocation held.
    final PassSkip? skipped = frame.skipReasonOf('render textures');
    if (skipped != null) {
      throw StateError('the render textures pass was skipped: $skipped');
    }
    if (!frame.passes.any((FramePass p) => p.name == 'render textures')) {
      throw StateError('the render textures pass did not run');
    }
    if (!_picture.isDrawn) {
      throw StateError('the camera never drew into its texture');
    }
    // #endregion check
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
