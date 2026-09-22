/// A dry-run frame graph compared with the frame that followed it.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class FrameGraphDemo extends ShowcaseDemo {
  bool bloom = true;
  bool antiAlias = true;

  late final Scene _scene;
  List<String> _planned = const <String>[];
  List<String> _skipped = const <String>[];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.5
      ..pitch = 0.25
      ..yaw = 0.45;
  }

  @override
  Scene build(DemoContext context) {
    // #region scene
    final Material bright = Material(
      name: 'bright metal',
      baseColor: Vector4(0.7, 0.2, 0.08, 1.0),
      emissive: Vector3(1.0, 0.16, 0.03),
      emissiveStrength: 2.5,
      metallic: 0.62,
      roughness: 0.22,
    );
    _scene = Scene()
      ..ambientColor = Vector3(0.38, 0.46, 0.64)
      ..ambientIntensity = 0.12
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const TorusShape(radius: 1.15, tubeRadius: 0.38).build(),
          ),
          bright,
          name: 'emissive torus',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.45, -0.82, -0.35)),
      );
    // #endregion scene
    return _scene;
  }

  @override
  RenderSettings settings(DemoContext context) {
    // #region settings
    final RenderSettings next = RenderSettings(
      bloom: BloomSettings(intensity: bloom ? 0.65 : 0.0),
      antiAlias: AntiAliasSettings(enabled: antiAlias),
    );
    // #endregion settings

    // #region plan
    final CompiledFrameGraph graph = context.renderer.planFrame(
      scene: _scene,
      views: <RenderView>[context.view],
      settings: next,
    );
    _planned = <String>[
      for (final FrameGraphNode node in graph.order) node.name,
    ];
    _skipped = <String>[
      for (final SkippedPass pass in graph.skipped) pass.name,
    ];
    // #endregion plan
    return next;
  }

  @override
  // #region controls
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Bloom pass',
      value: () => bloom,
      onChanged: (bool value) => bloom = value,
    ),
    ToggleControl(
      'Antialias pass',
      value: () => antiAlias,
      onChanged: (bool value) => antiAlias = value,
    ),
  ];
  // #endregion controls

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final List<String> drawn = <String>[
      for (final FramePass pass in frame.passes) pass.name,
    ];
    if (_planned.isEmpty ||
        !_planned.contains('scene') ||
        !_planned.contains('composite') ||
        bloom && !_planned.contains('bloom') ||
        antiAlias && !_planned.contains('antialias') ||
        !_sameNames(_planned, drawn) ||
        _skipped.any(drawn.contains)) {
      throw StateError('the planned graph did not match the drawn frame');
    }
    // #endregion check
  }
}

bool _sameNames(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
