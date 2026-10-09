/// A material channel in place of the light, wiped across the frame, and
/// what the frame says it cost.
///
/// Quoted by `debug_views.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class DebugViewsDemo extends ShowcaseDemo {
  /// An index into [_channels].
  int channel = 0;
  double split = 0.5;
  bool stepping = true;

  double _shown = 0.0;
  late DebugViewSettings _debug;

  // #region channels
  /// Every channel there is, in the order the page steps through them.
  static const List<DebugView> _channels = <DebugView>[
    DebugView.albedo,
    DebugView.normal,
    DebugView.roughness,
    DebugView.metallic,
    DebugView.occlusion,
    DebugView.emissive,
    DebugView.uv,
    DebugView.nonFinite,
  ];
  // #endregion channels

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) {
    // #region glow
    // Something that gives off light, so the emission channel has more to
    // show than black.
    final MeshNode lantern = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3.all(0.4)).build(),
      ),
      RenderMaterial(
        name: 'lantern',
        baseColor: LinearColor.fromSrgb(0.2, 0.2, 0.2, 1.0),
        emissive: LinearColor(0.3, 0.9, 0.5),
        emissiveStrength: 2.0 * Photometric.legacyNits,
      ),
      name: 'lantern',
    )..setPosition(0.0, 0.2, 1.6);
    // #endregion glow
    return PostStage.build(context).scene..add(lantern);
  }

  @override
  void update(DemoContext context, double dt) {
    if (!stepping) return;
    _shown += dt;
    if (_shown > 2.0) {
      _shown = 0.0;
      channel = (channel + 1) % _channels.length;
    }
  }

  @override
  RenderSettings settings(DemoContext context) {
    // #region view
    _debug = DebugViewSettings(view: _channels[channel], split: split);
    // #endregion view
    return RenderSettings(debugView: _debug);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Channel',
      options: <String>[for (final DebugView v in _channels) v.name],
      index: () => channel,
      onChanged: (int i) => channel = i,
    ),
    SliderControl(
      'Split (share left lit)',
      min: 0,
      max: 1,
      value: () => split,
      onChanged: (double v) => split = v,
    ),
    ToggleControl(
      'Step through the channels',
      value: () => stepping,
      onChanged: (bool v) => stepping = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!_debug.active) {
      throw StateError('no channel would be drawn with $_debug');
    }
    // #region stats
    final FramePass scenePass = frame.passes.firstWhere(
      (FramePass p) => p.name == 'scene',
    );
    final FramePass composite = frame.passes.firstWhere(
      (FramePass p) => p.name == 'composite',
    );
    final int passDraws = frame.passes.fold<int>(
      0,
      (int total, FramePass p) => total + p.drawCalls,
    );
    // The scene pass drew the five meshes' triangles, and the composite,
    // which passes the debug side through untoned, is one triangle's draw.
    if (scenePass.drawCalls < 5 ||
        scenePass.triangles <= 0 ||
        composite.drawCalls != 1 ||
        passDraws != frame.drawCalls ||
        frame.triangles < scenePass.triangles) {
      throw StateError('the pass costs do not add up to the frame');
    }
    // The scene's own colour target alone is at least as large as the
    // eight-bit picture handed back, so the targets cannot hold less.
    if (frame.targetBytes < textureBytes(frame.frame)) {
      throw StateError(
        'the targets hold ${frame.targetBytes} bytes, less than the picture',
      );
    }
    // #endregion stats
  }
}
