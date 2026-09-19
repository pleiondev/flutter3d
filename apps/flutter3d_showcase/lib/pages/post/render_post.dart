/// Post effects on an image of your own: one render, then `renderPost` over the
/// result, then the answer shown on a screen in the scene.
///
/// Quoted by `render_post.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class RenderPostDemo extends ShowcaseDemo {
  double threshold = 0.6;
  double intensity = 0.6;
  double exposure = 1.0;

  static const int _width = 320;
  static const int _height = 180;

  late final Scene _source;
  late final RenderView _sourceView;
  late final TextureHandle _output;

  /// What the last call to `renderPost` handed back.
  PostFrameResult? result;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 2.3
      ..pitch = 0.0
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
    context.orbit.apply();
  }

  @override
  Scene build(DemoContext context) {
    // #region source
    final CameraNode eye = CameraNode(name: 'source eye')
      ..setPosition(0.0, 0.0, 4.0);
    _source = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(2.4, 0.5, 0.2)).build(),
          ),
          Material(
            name: 'bar',
            baseColor: Vector4(0.0, 0.0, 0.0, 1.0),
            emissive: Vector3(1.0, 0.55, 0.2),
            emissiveStrength: 6.0,
          ),
          name: 'bar',
        ),
      )
      ..add(eye);
    _sourceView = RenderView(
      camera: eye,
      clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
    );
    // #endregion source

    // #region screen
    _output = context.device.createTexture(
      RenderTargetSpec(
        width: _width,
        height: _height,
        format: context.device.defaultColorFormat,
      ),
    );
    final MeshNode screen = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(3.2, 1.8, 0.02)).build(),
      ),
      Material(name: 'screen', lighting: LightingModel.unlit, albedo: _output),
      name: 'screen',
    );
    // #endregion screen

    return Scene()..add(screen);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region first
    final TextureHandle picture = context.renderer
        .render(
          width: _width,
          height: _height,
          scene: _source,
          views: <RenderView>[_sourceView],
          settings: const RenderSettings(
            bloom: BloomSettings(enabled: false),
            shadows: ShadowSettings(enabled: false),
            tonemap: false,
          ),
        )
        .frame;
    // #endregion first

    // #region post
    result = context.renderer.renderPost(
      hdr: picture,
      target: _output,
      settings: RenderSettings(
        exposure: exposure,
        bloom: BloomSettings(threshold: threshold, intensity: intensity),
      ),
    );
    // #endregion post
  }

  @override
  RenderSettings settings(DemoContext context) => const RenderSettings(
    bloom: BloomSettings(enabled: false),
    shadows: ShadowSettings(enabled: false),
    tonemap: false,
    exposure: 1.0,
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Threshold',
      min: 0.1,
      max: 1.5,
      value: () => threshold,
      onChanged: (double v) => threshold = v,
    ),
    SliderControl(
      'Intensity',
      min: 0,
      max: 1.5,
      value: () => intensity,
      onChanged: (double v) => intensity = v,
    ),
    SliderControl(
      'Exposure',
      min: 0.3,
      max: 3,
      value: () => exposure,
      onChanged: (double v) => exposure = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region answer
    final PostFrameResult? post = result;
    if (post == null) {
      throw StateError('renderPost was never called');
    }
    if (!identical(post.frame, _output)) {
      throw StateError('renderPost drew somewhere other than the target');
    }
    // #endregion answer
  }
}
