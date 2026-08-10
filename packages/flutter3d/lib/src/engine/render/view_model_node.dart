import 'dart:developer' as developer;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../scene/camera_node.dart';
import '../scene/scene.dart';
import 'frame_graph.dart';
import 'frame_plan.dart';
import 'render_node.dart';

/// Draws the first-person view model over the finished scene.
///
/// Its own command buffer, because Metal allows one open encoder per buffer
/// and flutter_gpu offers no way to end a pass — the same rule that already
/// governs the shadow and post passes.
///
/// its own pass rather than the scene pass, and that is the
/// whole reason the stage exists: a weapon held at arm's length shares no
/// depth with the world, or every doorway would slice the barrel off.
final class ViewModelNode extends RenderNode {
  ViewModelNode({required this.scene, required this.camera});

  /// Holds only what is in the player's hands. Kept apart from the world so
  /// culling, picking and the shadow pass never see it.
  Scene scene;

  /// Usually around 55 degrees against the world camera's 90.
  CameraNode camera;

  @override
  String get name => 'view model';

  /// Reads the finished scene and draws over it, which is a read and a write of
  /// the same resource — a link in the chain rather than a consumer of one.
  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  bool get isActive => scene.meshes.isNotEmpty;

  @override
  void execute(NodeFrame frame) {
    final hdr = frame.sceneColor;
    if (hdr == null) return;
    developer.Timeline.startSync('ViewModelNode.encode');

    final width = frame.width;
    final height = frame.height;

    // Straight into the resolved target, without MSAA, whatever the scene
    // used. Loading a multisampled attachment would mean loading the resolved
    // image back into it, which the API does not offer — and a weapon is a
    // handful of large, close triangles whose silhouette is mostly off screen,
    // the one case where the resolve buys least.
    final target = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: hdr, loadAction: gpu.LoadAction.load),
      depthStencilAttachment: gpu.DepthStencilAttachment(
        // Its own depth, not the scene's: attachments in one target must agree
        // on sample count, and the scene's is four-sample whenever MSAA is on.
        texture: _depthFor(width, height),
        // Cleared, so nothing in the world can occlude what is in the player's
        // hands.
        depthClearValue: 1.0,
      ),
    );

    final buffer = gpu.gpuContext.createCommandBuffer();
    final encoder = buffer.createRenderPass(target);

    encoder
      ..setViewport(gpu.Viewport(x: 0, y: 0, width: width, height: height))
      ..setScissor(gpu.Scissor(x: 0, y: 0, width: width, height: height))
      ..setDepthWriteEnable(true)
      ..setDepthCompareOperation(gpu.CompareFunction.less)
      ..setPrimitiveType(gpu.PrimitiveType.triangle);

    // Nothing is bound in a new pass, so the state has to forget what the
    // scene pass left it believing.
    frame.state.invalidatePipeline();

    final aspect = height == 0 ? 1.0 : width / height;
    camera.readWorldPosition(_cameraPosition);

    frame.services.encodeScene(
      pass: encoder,
      host: frame.host,
      scene: scene,
      viewProjection: camera.viewProjection(aspect),
      cameraPosition: _cameraPosition,
      settings: frame.settings,
      state: frame.state,
    );

    buffer.submit();
    developer.Timeline.finishSync();
  }

  gpu.Texture _depthFor(int width, int height) {
    if (_depth != null && _depthWidth == width && _depthHeight == height) {
      return _depth!;
    }
    _depth = gpu.gpuContext.createTexture(
      gpu.StorageMode.deviceTransient,
      width,
      height,
      format: gpu.gpuContext.defaultDepthStencilFormat,
    );
    _depthWidth = width;
    _depthHeight = height;
    return _depth!;
  }

  gpu.Texture? _depth;
  int _depthWidth = 0;
  int _depthHeight = 0;
  final vm.Vector3 _cameraPosition = vm.Vector3.zero();
}
